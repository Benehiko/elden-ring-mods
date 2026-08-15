//! SDK module `params`: typed field access to the game's live param tables.
//!
//! One surface, two backends — a mod names a param file and a row, and
//! reads or writes fields by their paramdef names. Which bytes it reaches
//! is the host's `param_table`: the injected runtime hands out a
//! `paramview.Table` over the game's resident tables, so every `set` lands
//! in the memory the game reads, immediately, for the rest of the process
//! (nothing is saved; a mod reapplies its edits at every launch, which is
//! the intended model). `ermod apply` hands out the same view over an
//! unpacked `regulation.bin`, so the same `set` lands in the archive.
//!
//!   local r = sdk.params.row("CharaInitParam", 3000)   -- nil if no such row
//!   r.soulLv                   -- 9
//!   r.soulLv = 60
//!   r.id                       -- 3000 (unless the paramdef has a field "id")
//!   for row in sdk.params.rows("CharaInitParam") do ... end
//!
//! File names are accepted with or without the `.param` extension.
//!
//! Errors a mod author can fix are Lua errors (unknown file, unknown field,
//! value out of range, wrong type) so they surface at once through the
//! registry's error path; a missing row is `nil` because that is a normal
//! question to ask. A file the game has not loaded (or a host with no game)
//! is also an error — the mod cannot do its job, and silently doing nothing
//! is the worst outcome for it.
//!
//! Identity is checked before any access: the live table's type string and
//! row size must match the vendored paramdef, otherwise the paramdef would
//! be reading the wrong bytes.
//!
//! Row handles are full userdata (`ermod.params.row`) holding a raw pointer
//! into game memory; the game never frees or moves a param table, so the
//! pointer stays valid for the process. Handles cannot be forged from Lua.

const std = @import("std");
const c = @import("../lua/c.zig").c;
const sdk = @import("sdk.zig");
const defs = @import("../params/defs.zig");
const paramdef = @import("../paramdef.zig");
const paramview = @import("../paramview.zig");

/// LuaLS annotations for this module (see `stubs.zig`).
pub const stub =
    \\---A live param row. Fields are the paramdef's field names, read and
    \\---written by name; `id` is the row id unless the paramdef has such a
    \\---field. Writes land in game memory at once and last for the process.
    \\---@class ermod.params.row
    \\---@field id integer
    \\---@field [string] number
    \\
    \\---@class ermod.sdk.params
    \\local params = {}
    \\
    \\---One row of a param file by id, or nil if there is no such row.
    \\---Errors if the file is unknown, not loaded yet, or the live table
    \\---does not match the vendored paramdef.
    \\---@param file string # e.g. "CharaInitParam" (".param" optional)
    \\---@param id integer
    \\---@return ermod.params.row?
    \\function params.row(file, id) end
    \\
    \\---Iterate every row of a param file in table order.
    \\---@param file string
    \\---@return fun(): ermod.params.row?
    \\function params.rows(file) end
    \\
;

const row_meta = "ermod.params.row";
const iter_meta = "ermod.params.iter";

const RowHandle = struct {
    def: *const defs.Def,
    id: u32,
    data: []u8,
    /// The live table's identity (header address), for write recording.
    table: usize,
};

const Iter = struct {
    def: *const defs.Def,
    table: paramview.Table,
    index: usize,
};

pub fn push(state: *c.lua_State, ctx: *sdk.Context) void {
    // Row metatable: field reads/writes go through __index/__newindex.
    if (c.luaL_newmetatable(state, row_meta) != 0) {
        sdk.pushBound(state, ctx, rowIndex);
        c.lua_setfield(state, -2, "__index");
        sdk.pushBound(state, ctx, rowNewIndex);
        c.lua_setfield(state, -2, "__newindex");
    }
    c.lua_pop(state, 1);
    if (c.luaL_newmetatable(state, iter_meta) != 0) {}
    c.lua_pop(state, 1);

    c.lua_createtable(state, 0, 2);
    sdk.pushBound(state, ctx, row);
    c.lua_setfield(state, -2, "row");
    sdk.pushBound(state, ctx, rows);
    c.lua_setfield(state, -2, "rows");
}

/// Resolve `file` (Lua arg 1) to its def and live table, or raise.
fn openTable(state: ?*c.lua_State, ctx: *sdk.Context) struct { def: *const defs.Def, table: paramview.Table } {
    var len: usize = 0;
    const ptr = c.luaL_checklstring(state, 1, &len);
    var file = if (ptr) |p| p[0..len] else "";
    if (std.mem.endsWith(u8, file, ".param")) file = file[0 .. file.len - ".param".len];
    const def = defs.find(file) orelse {
        _ = c.luaL_error(state, "unknown param file '%s'", ptr);
        unreachable;
    };
    const table = ctx.host.paramTable(file) orelse {
        _ = c.luaL_error(state, "param file '%s' is not available (no live game, or not loaded)", ptr);
        unreachable;
    };
    if (!std.mem.eql(u8, table.param_type, def.param_type) or table.row_size != def.row_size) {
        _ = c.luaL_error(state, "param file '%s' does not match its paramdef (live %s/%d bytes, def %s/%d bytes)", ptr, table.param_type.ptr, @as(c_int, @intCast(table.row_size)), def.param_type.ptr, @as(c_int, @intCast(def.row_size)));
        unreachable;
    }
    return .{ .def = def, .table = table };
}

fn pushRow(state: ?*c.lua_State, def: *const defs.Def, table: paramview.Table, id: u32, data: []u8) void {
    const ud: *RowHandle = @ptrCast(@alignCast(c.lua_newuserdatauv(state, @sizeOf(RowHandle), 0).?));
    ud.* = .{ .def = def, .id = id, .data = data, .table = @intFromPtr(table.header) };
    _ = c.luaL_setmetatable(state, row_meta);
}

/// `params.row(file, id)` → row handle or nil.
fn row(state: ?*c.lua_State) callconv(.c) c_int {
    const ctx = sdk.contextUpvalue(state);
    const opened = openTable(state, ctx);
    const id_arg = c.luaL_checkinteger(state, 2);
    if (id_arg < 0 or id_arg > std.math.maxInt(u32)) return c.luaL_error(state, "row id out of range");
    const id: u32 = @intCast(id_arg);
    const data = opened.table.row(id) orelse {
        c.lua_pushnil(state);
        return 1;
    };
    pushRow(state, opened.def, opened.table, id, data);
    return 1;
}

/// `params.rows(file)` → iterator yielding row handles in table order.
fn rows(state: ?*c.lua_State) callconv(.c) c_int {
    const ctx = sdk.contextUpvalue(state);
    const opened = openTable(state, ctx);
    const ud: *Iter = @ptrCast(@alignCast(c.lua_newuserdatauv(state, @sizeOf(Iter), 0).?));
    ud.* = .{ .def = opened.def, .table = opened.table, .index = 0 };
    _ = c.luaL_setmetatable(state, iter_meta);
    c.lua_pushcclosure(state, rowsNext, 1);
    return 1;
}

fn rowsNext(state: ?*c.lua_State) callconv(.c) c_int {
    const it: *Iter = @ptrCast(@alignCast(c.lua_touserdata(state, c.lua_upvalueindex(1)).?));
    const r = it.table.rowAt(it.index) orelse {
        c.lua_pushnil(state);
        return 1;
    };
    it.index += 1;
    pushRow(state, it.def, it.table, r.id, r.data);
    return 1;
}

fn checkRow(state: ?*c.lua_State) *RowHandle {
    return @ptrCast(@alignCast(c.luaL_checkudata(state, 1, row_meta).?));
}

/// `row.<field>` → number (float fields) or integer; `row.id` → the row id
/// when the paramdef has no field of that name.
fn rowIndex(state: ?*c.lua_State) callconv(.c) c_int {
    const h = checkRow(state);
    var len: usize = 0;
    const ptr = c.luaL_checklstring(state, 2, &len);
    const name = if (ptr) |p| p[0..len] else "";
    const f = h.def.field(name) orelse {
        if (std.mem.eql(u8, name, "id")) {
            c.lua_pushinteger(state, h.id);
            return 1;
        }
        return c.luaL_error(state, "unknown field '%s' in %s", ptr, h.def.name.ptr);
    };
    if (f.kind.isFloat()) {
        const v = paramdef.getFloat(h.data, f) catch return c.luaL_error(state, "field read failed");
        c.lua_pushnumber(state, v);
    } else {
        const v = paramdef.getInt(h.data, f) catch return c.luaL_error(state, "field read failed");
        c.lua_pushinteger(state, v);
    }
    return 1;
}

/// `row.<field> = value` — lands in game memory at once, and is reported to
/// the host so cross-mod conflicts can be logged.
fn rowNewIndex(state: ?*c.lua_State) callconv(.c) c_int {
    const ctx = sdk.contextUpvalue(state);
    const h = checkRow(state);
    var len: usize = 0;
    const ptr = c.luaL_checklstring(state, 2, &len);
    const name = if (ptr) |p| p[0..len] else "";
    const f = h.def.field(name) orelse return c.luaL_error(state, "unknown field '%s' in %s", ptr, h.def.name.ptr);
    if (f.kind.isFloat()) {
        const v = c.luaL_checknumber(state, 3);
        paramdef.setFloat(h.data, f, v) catch return c.luaL_error(state, "field write failed");
    } else {
        const v = c.luaL_checkinteger(state, 3);
        paramdef.setInt(h.data, f, v) catch |e| return switch (e) {
            error.ValueOutOfRange => c.luaL_error(state, "value %I out of range for field '%s'", v, ptr),
            else => c.luaL_error(state, "field write failed"),
        };
    }
    ctx.host.paramWritten(ctx.mod_name, .{ .table = h.table, .def_name = h.def.name, .row = h.id, .field = name });
    return 0;
}

// ── tests ───────────────────────────────────────────────────────────────

const testing = std.testing;
const mod_instance = @import("mod_instance.zig");
const host_mod = @import("host.zig");

const level60_src = @embedFile("../lua/fixtures/level60.lua");

/// A synthetic CharaInitParam table the tests hand out as "the game's":
/// rows 3000–3009 at the real 320-byte stride, seeded with the vanilla
/// levels from the open repo's docs/classes.md.
const Fake = struct {
    const ids = [_]u32{ 3000, 3001, 3002, 3003, 3004, 3005, 3006, 3007, 3008, 3009 };
    const vanilla_lv = [_]i16{ 9, 8, 7, 5, 6, 7, 10, 9, 9, 1 };
    const row_size = 320;
    const rows_off = paramview.header_size + ids.len * paramview.row_descriptor_size;
    const strings_off = rows_off + ids.len * row_size;
    var img: [strings_off + 32]u8 = undefined;

    fn build() void {
        @memset(&img, 0);
        std.mem.writeInt(u32, img[0x00..][0..4], strings_off, .little);
        std.mem.writeInt(u16, img[0x0A..][0..2], ids.len, .little);
        std.mem.writeInt(u64, img[0x10..][0..8], strings_off, .little);
        @memcpy(img[strings_off..][0.."CHARACTER_INIT_PARAM".len], "CHARACTER_INIT_PARAM");
        for (ids, 0..) |id, i| {
            const d = paramview.header_size + i * paramview.row_descriptor_size;
            std.mem.writeInt(u32, img[d..][0..4], id, .little);
            std.mem.writeInt(u64, img[d + 8 ..][0..8], rows_off + i * row_size, .little);
            std.mem.writeInt(i16, img[rows_off + i * row_size + 192 ..][0..2], vanilla_lv[i], .little);
        }
    }

    fn lookup(file: []const u8) ?paramview.Table {
        if (!std.mem.eql(u8, file, "CharaInitParam")) return null;
        return paramview.Table.at(&img);
    }

    fn soulLv(i: usize) i16 {
        return std.mem.readInt(i16, img[rows_off + i * row_size + 192 ..][0..2], .little);
    }
    fn stat(i: usize, off: usize) u8 {
        return img[rows_off + i * row_size + off];
    }
};

test "level60 rewrites every class in the live table through params" {
    Fake.build();
    var capture = host_mod.CaptureHost.init(testing.allocator);
    defer capture.deinit();
    capture.params = Fake.lookup;

    const m = try mod_instance.load(testing.allocator, level60_src, "=level60.lua", capture.host());
    defer mod_instance.destroy(m);
    try m.start();

    try testing.expect(capture.contains("Vagabond: level 9 -> 60"));
    try testing.expect(capture.contains("Wretch: level 1 -> 60"));
    try testing.expect(capture.contains("level60 applied to 10/10 classes"));
    for (Fake.ids, 0..) |_, i| {
        try testing.expectEqual(@as(i16, 60), Fake.soulLv(i));
        // baseVit..baseLuc are the eight u8s from +194; each spread sums to 139.
        var total: u32 = 0;
        for (0..8) |k| total += Fake.stat(i, 194 + k);
        try testing.expectEqual(@as(u32, 139), total);
    }
    try testing.expectEqual(@as(u8, 30), Fake.stat(0, 194)); // Vagabond vigor
}

/// Run `body` as a launch mod. A Lua error from it is returned as the error
/// message the mod logged, null on success.
fn runSnippet(capture: *host_mod.CaptureHost, body: []const u8) !?[]const u8 {
    var buf: [2048]u8 = undefined;
    const src = try std.fmt.bufPrint(&buf,
        \\local mod = {{ name = "p", version = "1.0.0", run_at = "launch", permissions = {{ "params", "log" }} }}
        \\function mod.on_launch(sdk)
        \\{s}
        \\end
        \\return mod
    , .{body});
    const m = try mod_instance.load(testing.allocator, src, "=p.lua", capture.host());
    defer mod_instance.destroy(m);
    m.start() catch {
        // start() logged the Lua error under the mod's name; the last
        // captured line is it.
        return capture.lines.items[capture.lines.items.len - 1].msg;
    };
    return null;
}

fn expectError(capture: *host_mod.CaptureHost, body: []const u8, needle: []const u8) !void {
    const msg = (try runSnippet(capture, body)) orelse return error.ExpectedLuaError;
    testing.expect(std.mem.indexOf(u8, msg, needle) != null) catch |e| {
        std.debug.print("error was: {s}\n", .{msg});
        return e;
    };
}

test "params: rows iterates in table order, .param suffix accepted, id readable" {
    Fake.build();
    var capture = host_mod.CaptureHost.init(testing.allocator);
    defer capture.deinit();
    capture.params = Fake.lookup;
    try testing.expectEqual(@as(?[]const u8, null), try runSnippet(&capture,
        \\local ids = {}
        \\for row in sdk.params.rows("CharaInitParam.param") do ids[#ids + 1] = row.id end
        \\sdk.log.info(table.concat(ids, ","))
        \\local r = sdk.params.row("CharaInitParam", 3009)
        \\sdk.log.info("wretch " .. r.soulLv .. " " .. tostring(sdk.params.row("CharaInitParam", 42)))
    ));
    try testing.expect(capture.contains("3000,3001,3002,3003,3004,3005,3006,3007,3008,3009"));
    try testing.expect(capture.contains("wretch 1 nil"));
}

test "params: author mistakes are Lua errors, reported through the mod's error path" {
    Fake.build();
    var capture = host_mod.CaptureHost.init(testing.allocator);
    defer capture.deinit();
    capture.params = Fake.lookup;

    try expectError(&capture, "sdk.params.row(\"NotAParam\", 1)", "unknown param file 'NotAParam'");
    try expectError(&capture, "local r = sdk.params.row(\"CharaInitParam\", 3000); sdk.log.info(r.nope)", "unknown field 'nope' in CharaInitParam");
    try expectError(&capture, "local r = sdk.params.row(\"CharaInitParam\", 3000); r.baseVit = 300", "out of range for field 'baseVit'");
    try testing.expectEqual(@as(u8, 0), Fake.stat(0, 194)); // untouched
    // A file the host has no table for.
    try expectError(&capture, "sdk.params.row(\"EquipParamGoods\", 1)", "param file 'EquipParamGoods' is not available");
}

test "params: a table that does not match its paramdef is refused" {
    Fake.build();
    // Lie about the row size: the def says 320.
    std.mem.writeInt(u64, Fake.img[paramview.header_size + paramview.row_descriptor_size + 8 ..][0..8], Fake.rows_off + 16, .little);
    var capture = host_mod.CaptureHost.init(testing.allocator);
    defer capture.deinit();
    capture.params = Fake.lookup;
    try expectError(&capture, "sdk.params.row(\"CharaInitParam\", 3000)", "does not match its paramdef");
}

test "every field write is reported and a second mod on the same field is a logged conflict" {
    Fake.build();
    var capture = host_mod.CaptureHost.init(testing.allocator);
    defer capture.deinit();
    capture.params = Fake.lookup;

    const a_src =
        \\local mod = { name = "class-tweaks", version = "1", run_at = "launch", permissions = { "params" } }
        \\function mod.on_launch(sdk)
        \\  local r = sdk.params.row("CharaInitParam", 3000)
        \\  r.soulLv = 12
        \\  r.baseVit = 20
        \\end
        \\return mod
    ;
    const b_src =
        \\local mod = { name = "level-60", version = "1", run_at = "launch", permissions = { "params" } }
        \\function mod.on_launch(sdk)
        \\  sdk.params.row("CharaInitParam", 3000).soulLv = 60
        \\  sdk.params.row("CharaInitParam", 3001).soulLv = 60
        \\end
        \\return mod
    ;
    const a = try mod_instance.load(testing.allocator, a_src, "=a.lua", capture.host());
    defer mod_instance.destroy(a);
    try a.start();
    try testing.expectEqual(@as(usize, 2), capture.write_count);
    try testing.expect(!capture.contains("params conflict"));

    // The same mod again (a hot-reload) is not a conflict.
    const a2 = try mod_instance.load(testing.allocator, a_src, "=a.lua", capture.host());
    defer mod_instance.destroy(a2);
    try a2.start();
    try testing.expect(!capture.contains("params conflict"));

    const b = try mod_instance.load(testing.allocator, b_src, "=b.lua", capture.host());
    defer mod_instance.destroy(b);
    try b.start();
    try testing.expectEqual(@as(usize, 6), capture.write_count);
    try testing.expect(capture.contains("params conflict — level-60 wrote CharaInitParam[3000].soulLv, previously written by class-tweaks"));
    // Row 3001 had no previous writer; baseVit was not touched by b.
    try testing.expect(!capture.contains("CharaInitParam[3001]"));
    try testing.expect(!capture.contains("baseVit"));
    // Last-wins still holds: the write landed.
    try testing.expectEqual(@as(i16, 60), Fake.soulLv(0));
}
