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

/// Repacks `data` into a DCX using `header` as the template (sizes patched).
pub fn pack(allocator: std.mem.Allocator, header: [header_len]u8, data: []const u8) Error![]u8 {
    const bound = c.ZSTD_compressBound(data.len);
    const buf = try allocator.alloc(u8, header_len + bound);
    errdefer allocator.free(buf);

    const n = c.ZSTD_compress(buf.ptr + header_len, bound, data.ptr, data.len, 19);
    if (c.ZSTD_isError(n) != 0) return Error.CompressFailed;

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
