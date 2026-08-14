//! PARAM file reader/writer (Elden Ring 64-bit variant).
//!
//! Layout (little-endian):
//!   0x00 u32 strings_offset (also where the param type string lives)
//!   0x04 u16 unk04
//!   0x06 u16 unk06
//!   0x08 u16 paramdef_data_version
//!   0x0A u16 row_count
//!   0x10 u64 param_type_offset
//!   0x2E u16 paramdef_format_version
//!   0x40 row descriptors (row_count * 24):
//!          0x00 u32 id, 0x04 u32 pad, 0x08 u64 data_offset, 0x10 u64 name_offset
//!   ...  row data (fixed stride per param), then strings
//!
//! Rows are a fixed-size packed struct whose layout lives in community
//! paramdefs, not in the file. This module therefore exposes rows as raw byte
//! slices; `paramdef.zig` maps field names onto them.
//!
//! Editing is in place: row sizes never change, so the writer only needs to
//! copy the original bytes back with mutated row data.

const std = @import("std");

pub const header_size = 0x40;
pub const row_descriptor_size = 24;

pub const Error = error{
    TruncatedParam,
    MalformedParam,
    OutOfMemory,
};

pub const Row = struct {
    id: u32,
    /// Mutable view into `Param.bytes`; edits land directly in the file image.
    data: []u8,
};

pub const Param = struct {
    allocator: std.mem.Allocator,
    /// The complete file image. Row slices point into this buffer.
    bytes: []u8,
    rows: []Row,
    /// e.g. "CHARACTER_INIT_PARAM"
    param_type: []const u8,
    /// Bytes per row, derived from the gap between consecutive row offsets.
    row_size: usize,

    pub fn deinit(self: *Param) void {
        self.allocator.free(self.rows);
        self.allocator.free(self.bytes);
        self.* = undefined;
    }

    pub fn findRow(self: *const Param, id: u32) ?*Row {
        for (self.rows) |*r| {
            if (r.id == id) return r;
        }
        return null;
    }

    /// The serialized file image. Valid as long as the `Param` lives; edits to
    /// row data are already reflected here.
    pub fn serialize(self: *const Param) []const u8 {
        return self.bytes;
    }
};

pub fn read(allocator: std.mem.Allocator, input: []const u8) Error!Param {
    if (input.len < header_size) return Error.TruncatedParam;

    const strings_offset = std.mem.readInt(u32, input[0x00..][0..4], .little);
    const row_count = std.mem.readInt(u16, input[0x0A..][0..2], .little);
    const param_type_offset = std.mem.readInt(u64, input[0x10..][0..8], .little);

    if (param_type_offset >= input.len) return Error.MalformedParam;
    if (header_size + @as(usize, row_count) * row_descriptor_size > input.len) {
        return Error.TruncatedParam;
    }

    const bytes = try allocator.dupe(u8, input);
    errdefer allocator.free(bytes);

    const type_end = std.mem.indexOfScalarPos(u8, bytes, param_type_offset, 0) orelse
        return Error.MalformedParam;
    const param_type = bytes[param_type_offset..type_end];

    const rows = try allocator.alloc(Row, row_count);
    errdefer allocator.free(rows);

    // Row stride: distance between the first two rows, or up to the string
    // table when there is only one row.
    var row_size: usize = 0;
    if (row_count > 0) {
        const first = rowDataOffset(bytes, 0);
        const end = if (row_count > 1) rowDataOffset(bytes, 1) else strings_offset;
        if (end <= first) return Error.MalformedParam;
        row_size = end - first;
    }

    for (rows, 0..) |*r, i| {
        const desc = header_size + i * row_descriptor_size;
        const id = std.mem.readInt(u32, bytes[desc..][0..4], .little);
        const data_offset = rowDataOffset(bytes, i);
        if (data_offset + row_size > bytes.len) return Error.TruncatedParam;
        r.* = .{ .id = id, .data = bytes[data_offset..][0..row_size] };
    }

    return .{
        .allocator = allocator,
        .bytes = bytes,
        .rows = rows,
        .param_type = param_type,
        .row_size = row_size,
    };
}

fn rowDataOffset(bytes: []const u8, index: usize) usize {
    const desc = header_size + index * row_descriptor_size;
    return @intCast(std.mem.readInt(u64, bytes[desc + 8 ..][0..8], .little));
}

test "param parse of a synthetic file" {
    const allocator = std.testing.allocator;

    const row_count = 2;
    const row_size = 8;
    const rows_off = header_size + row_count * row_descriptor_size;
    const strings_off = rows_off + row_count * row_size;
    const total = strings_off + "TEST_PARAM_ST".len + 1;

    const buf = try allocator.alloc(u8, total);
    defer allocator.free(buf);
    @memset(buf, 0);

    std.mem.writeInt(u32, buf[0x00..][0..4], @intCast(strings_off), .little);
    std.mem.writeInt(u16, buf[0x0A..][0..2], row_count, .little);
    std.mem.writeInt(u64, buf[0x10..][0..8], @intCast(strings_off), .little);
    @memcpy(buf[strings_off..][0.."TEST_PARAM_ST".len], "TEST_PARAM_ST");

    for (0..row_count) |i| {
        const desc = header_size + i * row_descriptor_size;
        std.mem.writeInt(u32, buf[desc..][0..4], @intCast(100 + i), .little);
        std.mem.writeInt(u64, buf[desc + 8 ..][0..8], @intCast(rows_off + i * row_size), .little);
    }
    std.mem.writeInt(u32, buf[rows_off..][0..4], 0xDEADBEEF, .little);

    var param = try read(allocator, buf);
    defer param.deinit();

    try std.testing.expectEqualStrings("TEST_PARAM_ST", param.param_type);
    try std.testing.expectEqual(@as(usize, row_size), param.row_size);
    try std.testing.expectEqual(@as(usize, 2), param.rows.len);
    try std.testing.expectEqual(@as(u32, 100), param.rows[0].id);

    const row = param.findRow(101) orelse return error.TestUnexpectedResult;
    std.mem.writeInt(u32, row.data[0..4], 0x12345678, .little);

    var reparsed = try read(allocator, param.serialize());
    defer reparsed.deinit();
    const check = reparsed.findRow(101) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u32, 0x12345678), std.mem.readInt(u32, check.data[0..4], .little));
}
