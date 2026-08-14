//! Field-level access to param rows using generated paramdef tables.
//!
//! A param row is a fixed-size packed struct whose layout is not described in
//! the file itself. `src/generated/paramdefs.zig` (produced by
//! `tools/gen_paramdef.py` from Paramdex XML) supplies the field tables; this
//! module reads and writes individual fields in a row's raw bytes.

const std = @import("std");

pub const Kind = enum {
    u8,
    s8,
    dummy8,
    u16,
    s16,
    u32,
    s32,
    f32,
    u64,
    s64,
    f64,

    pub fn size(self: Kind) usize {
        return switch (self) {
            .u8, .s8, .dummy8 => 1,
            .u16, .s16 => 2,
            .u32, .s32, .f32 => 4,
            .u64, .s64, .f64 => 8,
        };
    }

    pub fn isSigned(self: Kind) bool {
        return switch (self) {
            .s8, .s16, .s32, .s64 => true,
            else => false,
        };
    }

    pub fn isFloat(self: Kind) bool {
        return switch (self) {
            .f32, .f64 => true,
            else => false,
        };
    }
};

pub const Field = struct {
    name: []const u8,
    kind: Kind,
    offset: usize,
    count: usize,
    /// Set for bitfields: position within the storage unit at `offset`.
    bit_offset: ?u6,
    bit_width: ?u6,
};

pub const Error = error{
    UnknownField,
    RowTooSmall,
    ValueOutOfRange,
    TypeMismatch,
};

/// Looks up a field by name in a generated field table.
pub fn find(fields: []const Field, name: []const u8) ?*const Field {
    for (fields) |*f| {
        if (std.mem.eql(u8, f.name, name)) return f;
    }
    return null;
}

/// Reads an integer field as i64. Bitfields are masked and shifted out.
pub fn getInt(row: []const u8, field: *const Field) Error!i64 {
    if (field.kind.isFloat()) return Error.TypeMismatch;
    if (field.offset + field.kind.size() > row.len) return Error.RowTooSmall;

    const raw = readRaw(row, field);
    if (field.bit_width) |width| {
        const mask: u64 = (@as(u64, 1) << width) - 1;
        return @intCast((raw >> field.bit_offset.?) & mask);
    }
    if (field.kind.isSigned()) {
        return signExtend(raw, field.kind.size());
    }
    return @intCast(raw);
}

/// Writes an integer field, preserving neighbouring bits for bitfields.
pub fn setInt(row: []u8, field: *const Field, value: i64) Error!void {
    if (field.kind.isFloat()) return Error.TypeMismatch;
    if (field.offset + field.kind.size() > row.len) return Error.RowTooSmall;

    if (field.bit_width) |width| {
        const mask: u64 = (@as(u64, 1) << width) - 1;
        if (value < 0 or @as(u64, @intCast(value)) > mask) return Error.ValueOutOfRange;
        const cleared = readRaw(row, field) & ~(mask << field.bit_offset.?);
        const merged = cleared | (@as(u64, @intCast(value)) << field.bit_offset.?);
        writeRaw(row, field, merged);
        return;
    }

    try checkRange(field.kind, value);
    writeRaw(row, field, @bitCast(value));
}

pub fn getFloat(row: []const u8, field: *const Field) Error!f64 {
    if (!field.kind.isFloat()) return Error.TypeMismatch;
    if (field.offset + field.kind.size() > row.len) return Error.RowTooSmall;
    return switch (field.kind) {
        .f32 => @floatCast(@as(f32, @bitCast(std.mem.readInt(u32, row[field.offset..][0..4], .little)))),
        .f64 => @bitCast(std.mem.readInt(u64, row[field.offset..][0..8], .little)),
        else => unreachable,
    };
}

pub fn setFloat(row: []u8, field: *const Field, value: f64) Error!void {
    if (!field.kind.isFloat()) return Error.TypeMismatch;
    if (field.offset + field.kind.size() > row.len) return Error.RowTooSmall;
    switch (field.kind) {
        .f32 => std.mem.writeInt(u32, row[field.offset..][0..4], @bitCast(@as(f32, @floatCast(value))), .little),
        .f64 => std.mem.writeInt(u64, row[field.offset..][0..8], @bitCast(value), .little),
        else => unreachable,
    }
}

fn readRaw(row: []const u8, field: *const Field) u64 {
    return switch (field.kind.size()) {
        1 => row[field.offset],
        2 => std.mem.readInt(u16, row[field.offset..][0..2], .little),
        4 => std.mem.readInt(u32, row[field.offset..][0..4], .little),
        8 => std.mem.readInt(u64, row[field.offset..][0..8], .little),
        else => unreachable,
    };
}

fn writeRaw(row: []u8, field: *const Field, value: u64) void {
    switch (field.kind.size()) {
        1 => row[field.offset] = @truncate(value),
        2 => std.mem.writeInt(u16, row[field.offset..][0..2], @truncate(value), .little),
        4 => std.mem.writeInt(u32, row[field.offset..][0..4], @truncate(value), .little),
        8 => std.mem.writeInt(u64, row[field.offset..][0..8], value, .little),
        else => unreachable,
    }
}

fn signExtend(raw: u64, size: usize) i64 {
    return switch (size) {
        1 => @as(i8, @bitCast(@as(u8, @truncate(raw)))),
        2 => @as(i16, @bitCast(@as(u16, @truncate(raw)))),
        4 => @as(i32, @bitCast(@as(u32, @truncate(raw)))),
        8 => @bitCast(raw),
        else => unreachable,
    };
}

fn checkRange(kind: Kind, value: i64) Error!void {
    const ok = switch (kind) {
        .u8, .dummy8 => value >= 0 and value <= std.math.maxInt(u8),
        .s8 => value >= std.math.minInt(i8) and value <= std.math.maxInt(i8),
        .u16 => value >= 0 and value <= std.math.maxInt(u16),
        .s16 => value >= std.math.minInt(i16) and value <= std.math.maxInt(i16),
        .u32 => value >= 0 and value <= std.math.maxInt(u32),
        .s32 => value >= std.math.minInt(i32) and value <= std.math.maxInt(i32),
        .u64 => value >= 0,
        .s64 => true,
        .f32, .f64 => unreachable,
    };
    if (!ok) return Error.ValueOutOfRange;
}

test "int and bitfield access" {
    const fields = [_]Field{
        .{ .name = "soulLv", .kind = .s16, .offset = 0, .count = 1, .bit_offset = null, .bit_width = null },
        .{ .name = "baseVit", .kind = .u8, .offset = 2, .count = 1, .bit_offset = null, .bit_width = null },
        .{ .name = "vowType", .kind = .u8, .offset = 3, .count = 1, .bit_offset = 0, .bit_width = 4 },
        .{ .name = "isSyncTarget", .kind = .u8, .offset = 3, .count = 1, .bit_offset = 4, .bit_width = 1 },
    };
    var row = [_]u8{0} ** 8;

    const lv = find(&fields, "soulLv").?;
    try setInt(&row, lv, 60);
    try std.testing.expectEqual(@as(i64, 60), try getInt(&row, lv));

    const vit = find(&fields, "baseVit").?;
    try setInt(&row, vit, 40);
    try std.testing.expectEqual(@as(i64, 40), try getInt(&row, vit));
    try std.testing.expectError(Error.ValueOutOfRange, setInt(&row, vit, 300));

    // Bitfields must not disturb each other.
    const vow = find(&fields, "vowType").?;
    const sync = find(&fields, "isSyncTarget").?;
    try setInt(&row, vow, 9);
    try setInt(&row, sync, 1);
    try std.testing.expectEqual(@as(i64, 9), try getInt(&row, vow));
    try std.testing.expectEqual(@as(i64, 1), try getInt(&row, sync));
    try std.testing.expectEqual(@as(u8, 0b0001_1001), row[3]);

    try std.testing.expect(find(&fields, "nope") == null);
}

test "signed fields round-trip negatives" {
    const fields = [_]Field{
        .{ .name = "v", .kind = .s32, .offset = 0, .count = 1, .bit_offset = null, .bit_width = null },
    };
    var row = [_]u8{0} ** 4;
    const f = find(&fields, "v").?;
    try setInt(&row, f, -1);
    try std.testing.expectEqual(@as(i64, -1), try getInt(&row, f));
}
