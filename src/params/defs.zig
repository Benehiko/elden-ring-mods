//! Runtime lookup of generated paramdefs by param file name.
//!
//! `generated/paramdefs.zig` (vendored from the open `elden-ring-mods`
//! repo — see `make sync-paramdefs`) declares one struct per param file
//! (`CharaInitParam`, `EquipParamGoods`, …) with its `param_type`,
//! `row_size` and field table. Mods name files as strings, so this module
//! flattens those declarations into a table searchable at runtime.
//!
//! The game keeps some files that share one paramdef under suffixed names
//! (`ItemLotParam_map` / `ItemLotParam_enemy` are both `ITEMLOT_PARAM_ST`);
//! a lookup that misses tries the name up to its last `_`, so those resolve
//! to the shared def.

const std = @import("std");
const paramdef = @import("../paramdef.zig");
const paramdefs = @import("../generated/paramdefs.zig");

pub const Field = paramdef.Field;

pub const Def = struct {
    /// Param file name without extension, e.g. "CharaInitParam".
    name: []const u8,
    /// The header's type string, e.g. "CHARACTER_INIT_PARAM".
    param_type: []const u8,
    row_size: usize,
    fields: []const Field,

    pub fn field(self: *const Def, name: []const u8) ?*const Field {
        return paramdef.find(self.fields, name);
    }
};

/// Every generated def, in declaration order.
pub const all: []const Def = blk: {
    const decls = @typeInfo(paramdefs).@"struct".decls;
    var out: [decls.len]Def = undefined;
    for (decls, 0..) |d, i| {
        const T = @field(paramdefs, d.name);
        out[i] = .{
            .name = d.name,
            .param_type = T.param_type,
            .row_size = T.row_size,
            .fields = &T.fields,
        };
    }
    const frozen = out;
    break :blk &frozen;
};

/// The def for a param file name, exact or by shared-def prefix.
pub fn find(name: []const u8) ?*const Def {
    if (findExact(name)) |d| return d;
    if (std.mem.lastIndexOfScalar(u8, name, '_')) |i| return findExact(name[0..i]);
    return null;
}

fn findExact(name: []const u8) ?*const Def {
    for (all) |*d| {
        if (std.mem.eql(u8, d.name, name)) return d;
    }
    return null;
}

test "defs are flattened and searchable" {
    const testing = std.testing;
    try testing.expect(all.len >= 5);
    const d = find("CharaInitParam") orelse return error.Missing;
    try testing.expectEqualStrings("CHARACTER_INIT_PARAM", d.param_type);
    try testing.expectEqual(@as(usize, 320), d.row_size);
    const f = d.field("soulLv") orelse return error.MissingField;
    try testing.expectEqual(@as(usize, 192), f.offset);
    try testing.expectEqual(paramdef.Kind.s16, f.kind);
    try testing.expectEqual(@as(?*const Field, null), d.field("nope"));
    // Suffixed live names share the base def.
    const il = find("ItemLotParam_map") orelse return error.MissingSuffixed;
    try testing.expectEqualStrings("ITEMLOT_PARAM_ST", il.param_type);
    try testing.expectEqual(@as(?*const Def, null), find("NotAParam"));
}
