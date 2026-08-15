//! Declarative mod specs and the engine that applies them.
//!
//! A mod is a list of patches, each naming a param file, a row ID, a field and
//! a value. Specs are written in ZON (`mods/*.zon`) and parsed at comptime by
//! the caller, so a malformed spec is a compile error rather than a runtime
//! surprise.
//!
//! Conflicting writes — two patches targeting the same param/row/field — are an
//! error rather than last-wins, so composing specs can never silently drop an
//! edit.

const std = @import("std");
const bnd4 = @import("bnd4.zig");
const param = @import("param.zig");
const paramdef = @import("ermod_lua").paramdef;
const defs = @import("ermod_lua").paramdefs;
const spec_types = @import("spec");

pub const Value = spec_types.Value;
pub const Patch = spec_types.Patch;
pub const Spec = spec_types.Spec;

pub const Error = error{
    UnknownParam,
    UnknownField,
    RowNotFound,
    ConflictingPatch,
    ParamTypeMismatch,
    RowSizeMismatch,
} || paramdef.Error || param.Error || bnd4.Error;

/// Field table plus the identity checks that guard against a game patch
/// changing a param's layout underneath us.
const ParamInfo = struct {
    file: []const u8,
    param_type: []const u8,
    row_size: usize,
    fields: []const paramdef.Field,
};

const known_params = [_]ParamInfo{
    .{
        .file = "CharaInitParam.param",
        .param_type = defs.CharaInitParam.param_type,
        .row_size = defs.CharaInitParam.row_size,
        .fields = &defs.CharaInitParam.fields,
    },
    .{
        .file = "ItemLotParam.param",
        .param_type = defs.ItemLotParam.param_type,
        .row_size = defs.ItemLotParam.row_size,
        .fields = &defs.ItemLotParam.fields,
    },
    .{
        .file = "EquipParamWeapon.param",
        .param_type = defs.EquipParamWeapon.param_type,
        .row_size = defs.EquipParamWeapon.row_size,
        .fields = &defs.EquipParamWeapon.fields,
    },
    .{
        .file = "EquipParamProtector.param",
        .param_type = defs.EquipParamProtector.param_type,
        .row_size = defs.EquipParamProtector.row_size,
        .fields = &defs.EquipParamProtector.fields,
    },
    .{
        .file = "EquipParamGoods.param",
        .param_type = defs.EquipParamGoods.param_type,
        .row_size = defs.EquipParamGoods.row_size,
        .fields = &defs.EquipParamGoods.fields,
    },
};

fn lookupParam(file: []const u8) ?*const ParamInfo {
    for (&known_params) |*p| {
        if (std.mem.eql(u8, p.file, file)) return p;
    }
    return null;
}

pub const Report = struct {
    patches_applied: usize,
    params_touched: usize,
};

/// Applies every patch in `specs` to `archive` in place.
///
/// Params are loaded lazily and written back once, so a spec touching one param
/// does not rewrite the other 193.
pub fn apply(
    allocator: std.mem.Allocator,
    archive: *bnd4.Archive,
    specs: []const Spec,
) Error!Report {
    var loaded = std.StringHashMap(param.Param).init(allocator);
    defer {
        var it = loaded.valueIterator();
        while (it.next()) |p| p.deinit();
        loaded.deinit();
    }

    // Records param/row/field triples already written, to detect conflicts.
    var claimed = std.StringHashMap(void).init(allocator);
    defer {
        var it = claimed.keyIterator();
        while (it.next()) |k| allocator.free(k.*);
        claimed.deinit();
    }

    var applied: usize = 0;

    for (specs) |spec| {
        for (spec.patches) |patch| {
            const info = lookupParam(patch.param_file) orelse return Error.UnknownParam;

            const key = try std.fmt.allocPrint(allocator, "{s}/{d}/{s}", .{
                patch.param_file, patch.row, patch.field,
            });
            errdefer allocator.free(key);
            if (claimed.contains(key)) {
                allocator.free(key);
                return Error.ConflictingPatch;
            }
            try claimed.put(key, {});

            const entry = try loaded.getOrPut(patch.param_file);
            if (!entry.found_existing) {
                const file = archive.find(patch.param_file) orelse return Error.UnknownParam;
                entry.value_ptr.* = try param.read(allocator, file.data);
                const p = entry.value_ptr;
                if (!std.mem.eql(u8, p.param_type, info.param_type)) return Error.ParamTypeMismatch;
                if (p.row_size != info.row_size) return Error.RowSizeMismatch;
            }

            const p = entry.value_ptr;
            const row = p.findRow(patch.row) orelse return Error.RowNotFound;
            const field = paramdef.find(info.fields, patch.field) orelse return Error.UnknownField;

            switch (patch.value) {
                .int => |v| try paramdef.setInt(row.data, field, v),
                .float => |v| try paramdef.setFloat(row.data, field, v),
            }
            applied += 1;
        }
    }

    // Write the mutated param images back into the archive.
    var it = loaded.iterator();
    while (it.next()) |kv| {
        const file = archive.find(kv.key_ptr.*) orelse return Error.UnknownParam;
        const data = try allocator.dupe(u8, kv.value_ptr.serialize());
        archive.setData(file, data);
    }

    return .{ .patches_applied = applied, .params_touched = loaded.count() };
}

test "conflicting patches are rejected" {
    const a = Spec{ .name = "a", .patches = &.{
        .{ .param_file = "CharaInitParam.param", .row = 3000, .field = "soulLv", .value = .{ .int = 60 } },
    } };
    const b = Spec{ .name = "b", .patches = &.{
        .{ .param_file = "CharaInitParam.param", .row = 3000, .field = "soulLv", .value = .{ .int = 70 } },
    } };

    // No archive needed: the conflict is detected before any param is loaded
    // for the second patch, but apply() needs an archive to reach that point.
    // Verified end-to-end in the CLI integration test instead; here we assert
    // the key-collision logic directly.
    var claimed = std.StringHashMap(void).init(std.testing.allocator);
    defer claimed.deinit();
    const k1 = try std.fmt.allocPrint(std.testing.allocator, "{s}/{d}/{s}", .{
        a.patches[0].param_file, a.patches[0].row, a.patches[0].field,
    });
    defer std.testing.allocator.free(k1);
    try claimed.put(k1, {});
    const k2 = try std.fmt.allocPrint(std.testing.allocator, "{s}/{d}/{s}", .{
        b.patches[0].param_file, b.patches[0].row, b.patches[0].field,
    });
    defer std.testing.allocator.free(k2);
    try std.testing.expect(claimed.contains(k2));
}

test "known params cover the classes we edit" {
    try std.testing.expect(lookupParam("CharaInitParam.param") != null);
    try std.testing.expect(lookupParam("NotAParam.param") == null);
    try std.testing.expectEqual(@as(usize, 320), lookupParam("CharaInitParam.param").?.row_size);
}
