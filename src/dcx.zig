//! DCX container handling (Elden Ring regulation flavor: DCX + DCP ZSTD).
//!
//! Layout of the regulation DCX (all integers big-endian):
//!   0x00 "DCX\0", version
//!   0x18 "DCS\0", u32 uncompressed size, u32 compressed size
//!   0x24 "DCP\0" + "ZSTD" + compression params
//!   0x44 "DCA\0", u32 header size (8)
//!   0x4C compressed payload (zstd frame)
//!
//! Strategy: preserve the original header bytes verbatim on repack and patch
//! only the two size fields — avoids re-deriving FromSoftware's param fields.
//!
//! The zstd frame is written in the shape the game's own file has, not the
//! one-shot default: no content-size field in the frame header and a 64 MiB
//! window (windowLog 26, what zstd's level 21 through the streaming API
//! yields — the DCP block declares 0x15 = 21). `ZSTD_compress` at level 19
//! instead writes a frame with the content size present and an 8 MiB window,
//! and that file, decodable by every zstd we have, is refused by the game.
//! Whether the game's decoder rejects the content-size flag or the smaller
//! window is not established; a frame header byte-identical to the shipped
//! one removes the question.

const std = @import("std");
const c = @cImport(@cInclude("zstd.h"));

pub const header_len = 0x4C;
const dcs_uncompressed_off = 0x1C;
const dcs_compressed_off = 0x20;

pub const Error = error{
    NotDcx,
    UnsupportedDcx,
    DecompressFailed,
    CompressFailed,
    OutOfMemory,
};

pub const Unpacked = struct {
    /// Original header bytes, reused on repack.
    header: [header_len]u8,
    /// Decompressed payload (caller owns).
    data: []u8,

    pub fn deinit(self: *Unpacked, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
        self.* = undefined;
    }
};

pub fn unpack(allocator: std.mem.Allocator, bytes: []const u8) Error![]u8 {
    return (try unpackWithHeader(allocator, bytes)).data;
}

pub fn unpackWithHeader(allocator: std.mem.Allocator, bytes: []const u8) Error!Unpacked {
    if (bytes.len < header_len or !std.mem.eql(u8, bytes[0..4], "DCX\x00")) return Error.NotDcx;
    if (!std.mem.eql(u8, bytes[0x28..0x2C], "ZSTD")) return Error.UnsupportedDcx;

    const uncompressed_size = std.mem.readInt(u32, bytes[dcs_uncompressed_off..][0..4], .big);
    const compressed_size = std.mem.readInt(u32, bytes[dcs_compressed_off..][0..4], .big);
    if (header_len + @as(usize, compressed_size) > bytes.len) return Error.NotDcx;

    const out = try allocator.alloc(u8, uncompressed_size);
    errdefer allocator.free(out);

    const n = c.ZSTD_decompress(out.ptr, out.len, bytes.ptr + header_len, compressed_size);
    if (c.ZSTD_isError(n) != 0 or n != out.len) return Error.DecompressFailed;

    var result: Unpacked = .{ .header = undefined, .data = out };
    @memcpy(&result.header, bytes[0..header_len]);
    return result;
}

/// Compression level. Level 19 with the game's window and frame flags below;
/// the level itself only affects search effort, not the frame's shape.
const compression_level = 19;
/// The game's frame window: 2^26 = 64 MiB.
const window_log = 26;

/// Repacks `data` into a DCX using `header` as the template (sizes patched).
pub fn pack(allocator: std.mem.Allocator, header: [header_len]u8, data: []const u8) Error![]u8 {
    const bound = c.ZSTD_compressBound(data.len);
    const buf = try allocator.alloc(u8, header_len + bound);
    errdefer allocator.free(buf);

    const cctx = c.ZSTD_createCCtx() orelse return Error.OutOfMemory;
    defer _ = c.ZSTD_freeCCtx(cctx);
    if (c.ZSTD_isError(c.ZSTD_CCtx_setParameter(cctx, c.ZSTD_c_compressionLevel, compression_level)) != 0 or
        c.ZSTD_isError(c.ZSTD_CCtx_setParameter(cctx, c.ZSTD_c_windowLog, window_log)) != 0 or
        c.ZSTD_isError(c.ZSTD_CCtx_setParameter(cctx, c.ZSTD_c_contentSizeFlag, 0)) != 0 or
        c.ZSTD_isError(c.ZSTD_CCtx_setParameter(cctx, c.ZSTD_c_checksumFlag, 0)) != 0)
        return Error.CompressFailed;

    // Streamed with the source size unpledged, as the game's writer evidently
    // did: a one-shot compress knows the size and shrinks the window to fit
    // it, and the frame header would then say so. `bound` is enough for the
    // whole frame, so the end flush completes in one call.
    var input = c.ZSTD_inBuffer{ .src = data.ptr, .size = data.len, .pos = 0 };
    var output = c.ZSTD_outBuffer{ .dst = buf.ptr + header_len, .size = bound, .pos = 0 };
    while (input.pos < input.size) {
        if (c.ZSTD_isError(c.ZSTD_compressStream2(cctx, &output, &input, c.ZSTD_e_continue)) != 0)
            return Error.CompressFailed;
    }
    const remaining = c.ZSTD_compressStream2(cctx, &output, &input, c.ZSTD_e_end);
    if (c.ZSTD_isError(remaining) != 0 or remaining != 0) return Error.CompressFailed;
    const n = output.pos;

    @memcpy(buf[0..header_len], &header);
    std.mem.writeInt(u32, buf[dcs_uncompressed_off..][0..4], @intCast(data.len), .big);
    std.mem.writeInt(u32, buf[dcs_compressed_off..][0..4], @intCast(n), .big);

    return allocator.realloc(buf, header_len + n) catch buf[0 .. header_len + n];
}

test "dcx roundtrip" {
    const allocator = std.testing.allocator;
    var header: [header_len]u8 = [_]u8{0} ** header_len;
    @memcpy(header[0..4], "DCX\x00");
    @memcpy(header[0x28..0x2C], "ZSTD");

    const payload = "some param data " ** 100;
    const packed_bytes = try pack(allocator, header, payload);
    defer allocator.free(packed_bytes);

    var unpacked = try unpackWithHeader(allocator, packed_bytes);
    defer unpacked.deinit(allocator);
    try std.testing.expectEqualSlices(u8, payload, unpacked.data);
}

test "the zstd frame header is the game's: no content size, 64 MiB window" {
    // Frame_Header_Descriptor 0x00 (no FCS, no single-segment, no checksum,
    // no dictionary) then Window_Descriptor 0x80 (exponent 16 → windowLog
    // 10 + 16 = 26). These are the six bytes at 0x4C of the shipped file.
    const allocator = std.testing.allocator;
    var header: [header_len]u8 = [_]u8{0} ** header_len;
    @memcpy(header[0..4], "DCX\x00");
    @memcpy(header[0x28..0x2C], "ZSTD");

    const payload = "regulation payload " ** 4096;
    const packed_bytes = try pack(allocator, header, payload);
    defer allocator.free(packed_bytes);

    const frame = packed_bytes[header_len..];
    try std.testing.expectEqualSlices(u8, &.{ 0x28, 0xB5, 0x2F, 0xFD, 0x00, 0x80 }, frame[0..6]);
}
