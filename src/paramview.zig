//! A view over one PARAM table, in place.
//!
//! Elden Ring keeps every `.param` resident byte-for-byte in the on-disk
//! PARAM layout, which is why this one view serves both backends of the
//! `params` SDK module: live, `Table.at` is handed a header inside the
//! game's address space (the `SoloParamRepository` walk in the engine's
//! `params_live.zig`); offline, it is handed the bytes `ermod unpack`
//! produced. A field write through `row()` lands in whichever of the two it
//! was opened over, at the same offset, which is what makes "author live,
//! ship offline" one code path rather than two.
//!
//! Nothing here allocates or copies — a `Table` is a view, and its rows are
//! mutable slices into the caller's memory. Pure pointer reads, so the whole
//! thing is exercised on the host against a synthetic layout.
//!
//! The header/row parsing intentionally mirrors `param.zig` in this repo
//! (same offsets, same 24-byte row descriptors); that reader owns a copy of
//! the file, this one must not, hence the separate view.

const std = @import("std");

/// PARAM header/row-descriptor layout (Elden Ring 64-bit variant).
pub const header_size = 0x40;
pub const row_descriptor_size = 24;

/// A PARAM file image is a few MiB at most; a strings offset beyond this is
/// garbage, not a table.
pub const max_table_bytes: usize = 64 * 1024 * 1024;

/// One PARAM table: a view over its bytes, live or unpacked.
pub const Table = struct {
    header: [*]u8,
    /// e.g. "CHARACTER_INIT_PARAM" — from the header's own type string.
    param_type: []const u8,
    row_count: u16,
    /// Bytes per row, from the gap between the first two rows (0 if unknown).
    row_size: usize,

    /// Parse the header at `header`. Null if the header is not a plausible
    /// PARAM (type offset outside a sane bound, missing terminator).
    pub fn at(header: [*]u8) ?Table {
        const strings_offset = std.mem.readInt(u32, header[0x00..][0..4], .little);
        const row_count = std.mem.readInt(u16, header[0x0A..][0..2], .little);
        const type_off = std.mem.readInt(u64, header[0x10..][0..8], .little);
        // The type string lives in the string block, past the rows: bound it
        // by the strings offset (a header claiming otherwise is not ours).
        if (type_off < header_size or type_off > strings_offset or strings_offset > max_table_bytes) return null;
        const t = header + type_off;
        var len: usize = 0;
        while (len < 64 and t[len] != 0) : (len += 1) {}
        if (len == 0 or len == 64) return null;

        var row_size: usize = 0;
        if (row_count > 0) {
            const first = rowDataOffset(header, 0);
            const end = if (row_count > 1) rowDataOffset(header, 1) else strings_offset;
            if (end > first) row_size = end - first;
        }
        return .{ .header = header, .param_type = t[0..len], .row_count = row_count, .row_size = row_size };
    }

    /// Row `index` (0-based, descriptor order) with its id, or null past the end.
    pub fn rowAt(self: Table, index: usize) ?struct { id: u32, data: []u8 } {
        if (index >= self.row_count) return null;
        const desc = self.header + header_size + index * row_descriptor_size;
        return .{
            .id = std.mem.readInt(u32, desc[0..4], .little),
            .data = (self.header + rowDataOffset(self.header, index))[0..self.row_size],
        };
    }

    /// The row with this id, as a mutable slice into the underlying bytes.
    pub fn row(self: Table, id: u32) ?[]u8 {
        var i: usize = 0;
        while (i < self.row_count) : (i += 1) {
            const desc = self.header + header_size + i * row_descriptor_size;
            if (std.mem.readInt(u32, desc[0..4], .little) == id) {
                return (self.header + rowDataOffset(self.header, i))[0..self.row_size];
            }
        }
        return null;
    }
};

fn rowDataOffset(header: [*]const u8, index: usize) usize {
    const desc = header + header_size + index * row_descriptor_size;
    return @intCast(std.mem.readInt(u64, desc[8..16], .little));
}

// ── tests ───────────────────────────────────────────────────────────────

const testing = std.testing;

/// Build a synthetic PARAM image: `ids` rows of `row_size` bytes, one type
/// string. Shared with the engine's `params_live` tests through this module.
pub fn synthParam(buf: []u8, param_type: []const u8, ids: []const u32, row_size: usize) void {
    @memset(buf, 0);
    const rows_off = header_size + ids.len * row_descriptor_size;
    const strings_off = rows_off + ids.len * row_size;
    std.mem.writeInt(u32, buf[0x00..][0..4], @intCast(strings_off), .little);
    std.mem.writeInt(u16, buf[0x0A..][0..2], @intCast(ids.len), .little);
    std.mem.writeInt(u64, buf[0x10..][0..8], @intCast(strings_off), .little);
    @memcpy(buf[strings_off..][0..param_type.len], param_type);
    for (ids, 0..) |id, i| {
        const d = header_size + i * row_descriptor_size;
        std.mem.writeInt(u32, buf[d..][0..4], id, .little);
        std.mem.writeInt(u64, buf[d + 8 ..][0..8], @intCast(rows_off + i * row_size), .little);
    }
}

test "Table.at parses a synthetic image and rows are written in place" {
    var img = [_]u8{0} ** 0x200;
    synthParam(&img, "CHARACTER_INIT_PARAM", &.{ 3000, 3001 }, 16);
    img[header_size + 2 * row_descriptor_size + 16 + 4] = 9; // row 3001, byte 4

    const t = Table.at(&img) orelse return error.NotFound;
    try testing.expectEqualStrings("CHARACTER_INIT_PARAM", t.param_type);
    try testing.expectEqual(@as(u16, 2), t.row_count);
    try testing.expectEqual(@as(usize, 16), t.row_size);
    try testing.expectEqual(@as(?[]u8, null), t.row(42));
    try testing.expectEqual(@as(u32, 3000), (t.rowAt(0) orelse return error.NoRow).id);
    try testing.expectEqual(@as(u32, 3001), (t.rowAt(1) orelse return error.NoRow).id);
    try testing.expect(t.rowAt(2) == null);

    const row = t.row(3001) orelse return error.NoRow;
    try testing.expectEqual(@as(u8, 9), row[4]);
    row[4] = 60;
    try testing.expectEqual(@as(u8, 60), img[header_size + 2 * row_descriptor_size + 16 + 4]);
}

test "Table.at rejects a header that is not a PARAM" {
    var junk = [_]u8{0xFF} ** 0x80;
    try testing.expectEqual(@as(?Table, null), Table.at(&junk));
    var zero = [_]u8{0} ** 0x80;
    try testing.expectEqual(@as(?Table, null), Table.at(&zero)); // type offset 0 < header
}
