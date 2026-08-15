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
//! The zstd frame is written for the game's decoder, not for zstd's default:
//! a 64 KiB window, blocks of at most 64 KiB of source, no content-size
//! field, no checksum. Every one of those is a constraint the game imposes
//! or the shipped file exhibits — see `window_log` and `block_source_len` for
//! which is which and how each was found. `ZSTD_compress` at any level gives
//! a frame that every zstd decodes and the game does not survive.

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
/// Window: 2^16 = 64 KiB, and this one is load-bearing. The shipped frame
/// *declares* a 64 MiB window (descriptor 0x80), but the game's decoder —
/// `DLCM::Zstd::ZstdDecompressionStream` in the exe — keeps only 64 KiB of
/// history: a frame whose matches reach further back decodes to garbage and
/// the game dies in `DLRegularHeap.cpp(710)` ("given memory block seems to
/// be improper or freed already") a moment after the read. Any frame with
/// windowLog 26 did that, at every level and block size tried; the same data
/// with windowLog 16 booted the game and populated its params. So the game's
/// own encoder evidently never emitted a far offset either, whatever its
/// header says, and we bound ours the only way zstd offers: the window.
/// The cost is size — ~2.08 MB against ~1.77 MB at windowLog 26 for the
/// stock payload, still under the shipped 2.04 MB.
const window_log = 16;
/// Source bytes per zstd block. The shipped frame is 825 blocks over a
/// 53,945,424-byte payload: 824 of exactly 64 KiB and the tail, then an
/// empty block ending the frame — its writer flushed every 64 KiB. zstd's
/// default is 128 KiB blocks. Whether the game's decoder needs the smaller
/// blocks on their own was not isolated (the window turned out to be the
/// crash), but a decoder with 64 KiB of history is very likely to have a
/// 64 KiB output buffer too, and flushing at the game's own cadence costs
/// little. Kept, so the frame is shaped like the shipped one in every way
/// that is cheap to match.
const block_source_len = 64 * 1024;
/// zstd's two block splitters, off, by value: `ZSTD_c_splitAfterSequences`
/// (`ZSTD_c_experimentalParam13` = 1010, `ZSTD_ps_disable` = 2) and
/// `ZSTD_c_blockSplitterLevel` (`ZSTD_c_experimentalParam20` = 1017, 1 = no
/// splitting; 1.5.7+, and an unknown parameter is an error we tolerate below).
/// The names live in the experimental section of the header
/// (`ZSTD_STATIC_LINKING_ONLY`), but `ZSTD_CCtx_setParameter` accepts the
/// values from a normal build — the guard is on the declaration, not the
/// runtime.
const zstd_c_split_after_sequences: c.ZSTD_cParameter = 1010;
const zstd_ps_disable = 2;
const zstd_c_block_splitter_level: c.ZSTD_cParameter = 1017;
const zstd_block_splitter_off = 1;

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
        c.ZSTD_isError(c.ZSTD_CCtx_setParameter(cctx, c.ZSTD_c_checksumFlag, 0)) != 0 or
        // Level 19 turns the block splitter on, which cuts a 64 KiB input
        // into several blocks. Harmless for the size bound, but the shipped
        // frame is one block per 64 KiB and matching that is the point.
        c.ZSTD_isError(c.ZSTD_CCtx_setParameter(cctx, zstd_c_split_after_sequences, zstd_ps_disable)) != 0)
        return Error.CompressFailed;
    // Older than 1.5.7 has no pre-splitter and rejects the parameter; that
    // library also never splits this way, so the refusal is fine to ignore.
    _ = c.ZSTD_CCtx_setParameter(cctx, zstd_c_block_splitter_level, zstd_block_splitter_off);

    // Streamed with the source size unpledged, as the game's writer evidently
    // did: a one-shot compress knows the size and shrinks the window to fit
    // it, and the frame header would then say so. Fed in `block_source_len`
    // slices with a flush after each, so no block decodes to more than that
    // — see the constant. `bound` is enough for the whole frame, so every
    // flush and the end complete in one call.
    var output = c.ZSTD_outBuffer{ .dst = buf.ptr + header_len, .size = bound, .pos = 0 };
    var offset: usize = 0;
    while (offset < data.len) {
        const len = @min(block_source_len, data.len - offset);
        var input = c.ZSTD_inBuffer{ .src = data.ptr + offset, .size = len, .pos = 0 };
        const remaining = c.ZSTD_compressStream2(cctx, &output, &input, c.ZSTD_e_flush);
        if (c.ZSTD_isError(remaining) != 0 or remaining != 0 or input.pos != len) return Error.CompressFailed;
        offset += len;
    }
    var empty = c.ZSTD_inBuffer{ .src = data.ptr, .size = 0, .pos = 0 };
    const remaining = c.ZSTD_compressStream2(cctx, &output, &empty, c.ZSTD_e_end);
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

test "the zstd frame header: no content size, 64 KiB window" {
    // Frame_Header_Descriptor 0x00 (no FCS, no single-segment, no checksum,
    // no dictionary) then Window_Descriptor 0x30 (exponent 6 → windowLog
    // 10 + 6 = 16). The shipped file declares 0x80 (64 MiB) here; ours says
    // what it actually uses, which is what the game's decoder can follow.
    const allocator = std.testing.allocator;
    var header: [header_len]u8 = [_]u8{0} ** header_len;
    @memcpy(header[0..4], "DCX\x00");
    @memcpy(header[0x28..0x2C], "ZSTD");

    const payload = "regulation payload " ** 4096;
    const packed_bytes = try pack(allocator, header, payload);
    defer allocator.free(packed_bytes);

    const frame = packed_bytes[header_len..];
    try std.testing.expectEqualSlices(u8, &.{ 0x28, 0xB5, 0x2F, 0xFD, 0x00, 0x30 }, frame[0..6]);
}

test "blocks hold at most 64 KiB of source, like the shipped frame's" {
    // 200,000 bytes of random (incompressible) source → ceil(200000 / 65536)
    // = 4 raw blocks, not the 2 that 128 KiB blocks would give, and raw
    // blocks carry their source size in the header so it can be checked
    // too. Walked as: 3-byte little-endian header, bit 0 = last, bits 1-2 =
    // type (0 = raw, 1 = RLE with one byte of payload), bits 3+ = size.
    const allocator = std.testing.allocator;
    var header: [header_len]u8 = [_]u8{0} ** header_len;
    @memcpy(header[0..4], "DCX\x00");
    @memcpy(header[0x28..0x2C], "ZSTD");

    const source = try allocator.alloc(u8, 200_000);
    defer allocator.free(source);
    var rng = std.Random.DefaultPrng.init(7);
    rng.random().bytes(source);

    const packed_bytes = try pack(allocator, header, source);
    defer allocator.free(packed_bytes);

    const frame = packed_bytes[header_len..];
    var pos: usize = 6; // magic + FHD + window descriptor
    var blocks: usize = 0;
    var last_size: usize = 0;
    while (true) {
        const h = @as(u32, frame[pos]) | @as(u32, frame[pos + 1]) << 8 | @as(u32, frame[pos + 2]) << 16;
        const last = h & 1 == 1;
        const kind = (h >> 1) & 3;
        const size: usize = h >> 3;
        blocks += 1;
        try std.testing.expectEqual(@as(u32, 0), kind); // raw
        try std.testing.expect(size <= block_source_len);
        pos += 3 + (if (kind == 1) 1 else size);
        if (last) {
            last_size = size;
            break;
        }
    }
    // Four data blocks, then the empty raw block that ends a flushed frame —
    // the shipped frame ends the same way (824 data blocks + 1 empty).
    try std.testing.expectEqual(@as(usize, 5), blocks);
    try std.testing.expectEqual(@as(usize, 0), last_size);
    try std.testing.expectEqual(frame.len, pos);
}
