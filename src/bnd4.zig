//! BND4 archive reader/writer.
//!
//! Layout (little-endian; the regulation BND4 is LE with 64-bit sizes):
//!   0x00 "BND4"
//!   0x04 u8 unk04, u8 unk05, [2]u8 pad
//!   0x08 u8 big_endian, u8 bit_big_endian, [2]u8 pad
//!   0x0C u32 file_count
//!   0x10 u64 header_size (0x40)
//!   0x18 [8]u8 version string
//!   0x20 u64 file_header_size (0x24)
//!   0x28 u64 hashes/name-table offset
//!   0x30 u64 data_start
//!   0x38 u64 unk38
//!   0x40 file entries (file_count * 0x24)
//!   ...  UTF-16LE names, then file data
//!
//! Per-entry (0x24 bytes):
//!   0x00 u8 flags (0x40 = uncompressed), [3]u8 pad, u32 minus_one (0xFFFFFFFF)
//!   0x08 u64 size
//!   0x10 u64 uncompressed_size
//!   0x18 u32 data_offset
//!   0x1C u32 id
//!   0x20 u32 name_offset
//!
//! Everything we do not understand is preserved verbatim: the writer reuses the
//! original header and name table and only recomputes sizes and data offsets.

const std = @import("std");

pub const magic = "BND4";
pub const header_size = 0x40;
pub const entry_size = 0x24;

const flag_uncompressed = 0x40;

pub const Error = error{
    NotBnd4,
    UnsupportedBnd4,
    TruncatedBnd4,
    OutOfMemory,
};

pub const File = struct {
    /// UTF-16LE path as stored in the archive, e.g.
    /// `N:\GR\data\Param\param\GameParam\merged\DLC02\CharaInitParam.param`.
    /// Owned by the `Archive`.
    name: []const u8,
    id: u32,
    flags: u8,
    /// File contents. Owned by the `Archive`; mutate in place to edit,
    /// or replace via `Archive.setData`.
    data: []u8,
};

pub const Archive = struct {
    allocator: std.mem.Allocator,
    /// Original bytes from 0 up to the start of file data, reused on write so
    /// that unknown header fields and the name table survive untouched.
    prefix: []u8,
    /// Offset where file data actually begins (the smallest entry data offset).
    data_start: u64,
    files: []File,
    /// Set when a file's data was replaced and must be freed by us.
    owned_data: []bool,

    pub fn deinit(self: *Archive) void {
        for (self.files, self.owned_data) |f, owned| {
            if (owned) self.allocator.free(f.data);
            self.allocator.free(f.name);
        }
        self.allocator.free(self.files);
        self.allocator.free(self.owned_data);
        self.allocator.free(self.prefix);
        self.* = undefined;
    }

    /// Returns the file whose name ends with `basename`, e.g. "CharaInitParam.param".
    pub fn find(self: *const Archive, basename: []const u8) ?*File {
        for (self.files) |*f| {
            if (std.mem.endsWith(u8, f.name, basename)) return f;
        }
        return null;
    }

    /// Replaces a file's contents. Takes ownership of `data`.
    pub fn setData(self: *Archive, file: *File, data: []u8) void {
        const idx = (@intFromPtr(file) - @intFromPtr(self.files.ptr)) / @sizeOf(File);
        if (self.owned_data[idx]) self.allocator.free(file.data);
        file.data = data;
        self.owned_data[idx] = true;
    }
};

pub fn read(allocator: std.mem.Allocator, bytes: []const u8) Error!Archive {
    if (bytes.len < header_size or !std.mem.eql(u8, bytes[0..4], magic)) return Error.NotBnd4;
    if (bytes[8] != 0) return Error.UnsupportedBnd4; // big-endian archives unsupported

    const file_count = std.mem.readInt(u32, bytes[0x0C..][0..4], .little);
    const hdr_size = std.mem.readInt(u64, bytes[0x10..][0..8], .little);
    const file_hdr_size = std.mem.readInt(u64, bytes[0x20..][0..8], .little);
    const data_start = std.mem.readInt(u64, bytes[0x30..][0..8], .little);

    if (hdr_size != header_size or file_hdr_size != entry_size) return Error.UnsupportedBnd4;
    if (data_start > bytes.len) return Error.TruncatedBnd4;

    const files = try allocator.alloc(File, file_count);
    var files_init: usize = 0;
    errdefer {
        for (files[0..files_init]) |f| allocator.free(f.name);
        allocator.free(files);
    }

    for (files, 0..) |*f, i| {
        const off = header_size + i * entry_size;
        if (off + entry_size > bytes.len) return Error.TruncatedBnd4;
        const e = bytes[off..][0..entry_size];

        const flags = e[0];
        if (flags != flag_uncompressed) return Error.UnsupportedBnd4;

        const size = std.mem.readInt(u64, e[0x08..][0..8], .little);
        const data_offset = std.mem.readInt(u32, e[0x18..][0..4], .little);
        const id = std.mem.readInt(u32, e[0x1C..][0..4], .little);
        const name_offset = std.mem.readInt(u32, e[0x20..][0..4], .little);

        if (@as(u64, data_offset) + size > bytes.len) return Error.TruncatedBnd4;

        f.* = .{
            .name = try readUtf16Name(allocator, bytes, name_offset),
            .id = id,
            .flags = flags,
            // Cast away const: callers may mutate in place. The archive owns the
            // copy made below only when setData replaces it, so we copy here.
            .data = try allocator.dupe(u8, bytes[data_offset..][0..size]),
        };
        files_init += 1;
    }

    const owned = try allocator.alloc(bool, file_count);
    errdefer allocator.free(owned);
    @memset(owned, true);

    // `data_start` from the header marks the end of the header/hash region and
    // can sit *after* the first file's data, so derive the real start from the
    // entries themselves.
    var real_data_start: u64 = if (file_count == 0) data_start else std.math.maxInt(u64);
    for (0..file_count) |i| {
        const off = header_size + i * entry_size;
        const data_offset = std.mem.readInt(u32, bytes[off + 0x18 ..][0..4], .little);
        real_data_start = @min(real_data_start, data_offset);
    }

    const prefix = try allocator.dupe(u8, bytes[0..real_data_start]);

    return .{
        .allocator = allocator,
        .prefix = prefix,
        .files = files,
        .owned_data = owned,
        .data_start = real_data_start,
    };
}

fn readUtf16Name(allocator: std.mem.Allocator, bytes: []const u8, offset: u32) Error![]u8 {
    var end = offset;
    while (end + 1 < bytes.len and !(bytes[end] == 0 and bytes[end + 1] == 0)) end += 2;
    if (end + 1 >= bytes.len) return Error.TruncatedBnd4;

    const units = (end - offset) / 2;
    const utf16 = try allocator.alloc(u16, units);
    defer allocator.free(utf16);
    for (utf16, 0..) |*u, i| {
        u.* = std.mem.readInt(u16, bytes[offset + i * 2 ..][0..2], .little);
    }
    return std.unicode.utf16LeToUtf8Alloc(allocator, utf16) catch Error.UnsupportedBnd4;
}

/// Serializes the archive, recomputing sizes and data offsets. Data is laid out
/// in entry order starting at the original `data_start`, each file aligned to 16
/// bytes as FromSoftware does.
pub fn write(allocator: std.mem.Allocator, archive: *const Archive) Error![]u8 {
    // Lay data out from where it actually started, not from the header's
    // `dataStart` field: in the shipped regulation the latter is larger than
    // the first entry's offset (it marks the end of the header+hash region),
    // so trusting it would shift every file forward and inflate the archive.
    const data_start = archive.data_start;

    var total: u64 = data_start;
    for (archive.files) |f| {
        total = std.mem.alignForward(u64, total + f.data.len, 16);
    }

    const out = try allocator.alloc(u8, @intCast(total));
    errdefer allocator.free(out);
    @memcpy(out[0..archive.prefix.len], archive.prefix);
    @memset(out[archive.prefix.len..], 0);

    var cursor: u64 = data_start;
    for (archive.files, 0..) |f, i| {
        const off = header_size + i * entry_size;
        const e = out[off..][0..entry_size];
        std.mem.writeInt(u64, e[0x08..][0..8], f.data.len, .little);
        std.mem.writeInt(u64, e[0x10..][0..8], f.data.len, .little);
        std.mem.writeInt(u32, e[0x18..][0..4], @intCast(cursor), .little);

        @memcpy(out[cursor..][0..f.data.len], f.data);
        cursor = std.mem.alignForward(u64, cursor + f.data.len, 16);
    }

    return out;
}

test "bnd4 roundtrip on synthetic archive" {
    const allocator = std.testing.allocator;

    // Build a minimal two-file archive by hand.
    const name0 = std.unicode.utf8ToUtf16LeStringLiteral("A.param");
    const name1 = std.unicode.utf8ToUtf16LeStringLiteral("B.param");
    const names_off = header_size + 2 * entry_size;
    const name0_off = names_off;
    const name1_off = name0_off + (name0.len + 1) * 2;
    const data_start = std.mem.alignForward(usize, name1_off + (name1.len + 1) * 2, 16);

    const data0 = "first file contents";
    const data1 = "second";
    const total = std.mem.alignForward(usize, data_start + data0.len, 16) + data1.len;

    const buf = try allocator.alloc(u8, total);
    defer allocator.free(buf);
    @memset(buf, 0);

    @memcpy(buf[0..4], magic);
    std.mem.writeInt(u32, buf[0x0C..][0..4], 2, .little);
    std.mem.writeInt(u64, buf[0x10..][0..8], header_size, .little);
    @memcpy(buf[0x18..][0..8], "11611000");
    std.mem.writeInt(u64, buf[0x20..][0..8], entry_size, .little);
    std.mem.writeInt(u64, buf[0x30..][0..8], data_start, .little);

    const offsets = [_]usize{ data_start, std.mem.alignForward(usize, data_start + data0.len, 16) };
    const datas = [_][]const u8{ data0, data1 };
    const name_offs = [_]usize{ name0_off, name1_off };
    const names = [_][]const u16{ name0, name1 };

    for (0..2) |i| {
        const e = buf[header_size + i * entry_size ..][0..entry_size];
        e[0] = flag_uncompressed;
        std.mem.writeInt(u32, e[0x04..][0..4], 0xFFFFFFFF, .little);
        std.mem.writeInt(u64, e[0x08..][0..8], datas[i].len, .little);
        std.mem.writeInt(u64, e[0x10..][0..8], datas[i].len, .little);
        std.mem.writeInt(u32, e[0x18..][0..4], @intCast(offsets[i]), .little);
        std.mem.writeInt(u32, e[0x1C..][0..4], @intCast(i), .little);
        std.mem.writeInt(u32, e[0x20..][0..4], @intCast(name_offs[i]), .little);
        for (names[i], 0..) |u, j| {
            std.mem.writeInt(u16, buf[name_offs[i] + j * 2 ..][0..2], u, .little);
        }
        @memcpy(buf[offsets[i]..][0..datas[i].len], datas[i]);
    }

    var archive = try read(allocator, buf);
    defer archive.deinit();

    try std.testing.expectEqual(@as(usize, 2), archive.files.len);
    try std.testing.expectEqualStrings("A.param", archive.files[0].name);
    try std.testing.expectEqualStrings("second", archive.files[1].data);
    try std.testing.expect(archive.find("B.param") != null);

    const written = try write(allocator, &archive);
    defer allocator.free(written);

    var reparsed = try read(allocator, written);
    defer reparsed.deinit();
    try std.testing.expectEqualStrings("first file contents", reparsed.files[0].data);
    try std.testing.expectEqualStrings("B.param", reparsed.files[1].name);
}
