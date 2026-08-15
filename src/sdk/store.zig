//! SDK module `store`: per-mod persistent key/value — the only sanctioned
//! filesystem access a mod has.
//!
//!   local v = sdk.store.get("volume", 0.8)   -- default when unset (nil if none given)
//!   sdk.store.set("volume", 0.5)             -- string | number | boolean; nil deletes
//!   sdk.store.keys()                          -- sorted list of keys
//!
//! The values live in a hidden Lua table owned by this module (not
//! reachable from the mod), loaded once from the host on first access and
//! written back whole on every `set` — settings are small and rare, so a
//! full rewrite is simpler to reason about than partial writes. Where the
//! bytes go is the host's business (`Host.storeLoad`/`storeSave`, keyed by
//! the mod's name); a mod cannot name a file.
//!
//! Failures a mod author can fix are Lua errors (bad key, unsupported value
//! type). A corrupt store file or a failed write are reported through the
//! log and otherwise tolerated: the mod keeps running with what it has.

const std = @import("std");
const c = @import("../lua/c.zig").c;
const sdk = @import("sdk.zig");
const host_mod = @import("host.zig");
const format = @import("../store_format.zig");

/// LuaLS annotations for this module (see `stubs.zig`).
pub const stub =
    \\---@alias ermod.store.value string|number|boolean
    \\
    \\---@class ermod.sdk.store
    \\local store = {}
    \\
    \\---A stored value, or `default` when unset. Keys match [A-Za-z0-9_.-]+.
    \\---@generic T : ermod.store.value
    \\---@param key string
    \\---@param default T?
    \\---@return T
    \\function store.get(key, default) end
    \\
    \\---Persist a value (the whole store is written at once). nil deletes.
    \\---@param key string
    \\---@param value ermod.store.value|nil
    \\function store.set(key, value) end
    \\
    \\---Every stored key, sorted.
    \\---@return string[]
    \\function store.keys() end
    \\
;

/// The most keys one store holds; the serializer collects them for sorting.
const max_keys = 512;

pub fn push(state: *c.lua_State, ctx: *sdk.Context) void {
    c.lua_createtable(state, 0, 3);
    sdk.pushBound(state, ctx, get);
    c.lua_setfield(state, -2, "get");
    sdk.pushBound(state, ctx, set);
    c.lua_setfield(state, -2, "set");
    sdk.pushBound(state, ctx, keys);
    c.lua_setfield(state, -2, "keys");
}

/// Push the hidden store table, loading it from the host on first use.
fn pushTable(state: ?*c.lua_State, ctx: *sdk.Context) void {
    if (ctx.store_ref != c.LUA_NOREF) {
        _ = c.lua_rawgeti(state, c.LUA_REGISTRYINDEX, ctx.store_ref);
        return;
    }
    c.lua_newtable(state);
    load(state, ctx);
    c.lua_pushvalue(state, -1);
    ctx.store_ref = c.luaL_ref(state, c.LUA_REGISTRYINDEX);
}

/// Fill the table on top of the stack from the host's bytes.
fn load(state: ?*c.lua_State, ctx: *sdk.Context) void {
    const buf = ctx.storeBuffer() orelse return;
    const bytes = ctx.host.storeLoad(ctx.mod_name, buf) orelse return;
    var parser = format.Parser.init(bytes);
    // Decoded strings can be no longer than the file; heap scratch rather
    // than a 64 KiB stack frame on the render thread.
    const sbuf = ctx.gpa.alloc(u8, bytes.len + 1) catch return;
    defer ctx.gpa.free(sbuf);
    while (true) {
        const entry = parser.next() catch |err| {
            var msg: [160]u8 = undefined;
            const line = std.fmt.bufPrint(&msg, "store is corrupt ({s}); entries after the bad line are ignored", .{@errorName(err)}) catch "store is corrupt";
            ctx.host.log(ctx.mod_name, .warn, line);
            return;
        } orelse return;
        _ = c.lua_pushlstring(state, entry.key.ptr, entry.key.len);
        switch (entry.value) {
            .integer => |n| c.lua_pushinteger(state, n),
            .number => |f| c.lua_pushnumber(state, f),
            .boolean => |b| c.lua_pushboolean(state, @intFromBool(b)),
            .string => |raw| {
                const s = format.unescape(raw, sbuf) catch {
                    c.lua_pop(state, 1);
                    continue;
                };
                _ = c.lua_pushlstring(state, s.ptr, s.len);
            },
        }
        c.lua_rawset(state, -3);
    }
}

/// Serialize the table at `idx` and hand it to the host. Errors are logged.
fn save(state: ?*c.lua_State, ctx: *sdk.Context, idx: c_int) void {
    const buf = ctx.storeBuffer() orelse {
        ctx.host.log(ctx.mod_name, .warn, "store not saved: out of memory");
        return;
    };
    // Collect keys so the file is written in sorted order — stable output,
    // readable diffs. Values are looked up again by key when writing.
    var key_list: [max_keys][]const u8 = undefined;
    var n: usize = 0;
    const t = c.lua_absindex(state, idx);
    c.lua_pushnil(state);
    while (c.lua_next(state, t) != 0) {
        defer c.lua_pop(state, 1); // value; keep key for next
        if (n >= max_keys) {
            c.lua_pop(state, 1); // key
            ctx.host.log(ctx.mod_name, .warn, "store not saved: too many keys");
            return;
        }
        var len: usize = 0;
        const p = c.lua_tolstring(state, -2, &len);
        key_list[n] = p[0..len];
        n += 1;
    }
    std.mem.sort([]const u8, key_list[0..n], {}, lessThan);

    var w = format.Writer.init(buf) catch {
        ctx.host.log(ctx.mod_name, .warn, "store not saved: buffer too small");
        return;
    };
    for (key_list[0..n]) |key| {
        _ = c.lua_pushlstring(state, key.ptr, key.len);
        _ = c.lua_rawget(state, t);
        defer c.lua_pop(state, 1);
        const value = valueAt(state, -1) orelse continue; // set() already filtered types
        w.entry(key, value) catch |err| {
            var msg: [128]u8 = undefined;
            const line = std.fmt.bufPrint(&msg, "store not saved: {s}", .{@errorName(err)}) catch "store not saved";
            ctx.host.log(ctx.mod_name, .warn, line);
            return;
        };
    }
    if (!ctx.host.storeSave(ctx.mod_name, w.bytes())) {
        ctx.host.log(ctx.mod_name, .warn, "store not saved: write failed");
    }
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

/// The store `Value` for the Lua value at `idx`, or null if unsupported.
fn valueAt(state: ?*c.lua_State, idx: c_int) ?format.Value {
    switch (c.lua_type(state, idx)) {
        c.LUA_TBOOLEAN => return .{ .boolean = c.lua_toboolean(state, idx) != 0 },
        c.LUA_TNUMBER => {
            if (c.lua_isinteger(state, idx) != 0) return .{ .integer = c.lua_tointegerx(state, idx, null) };
            return .{ .number = c.lua_tonumberx(state, idx, null) };
        },
        c.LUA_TSTRING => {
            var len: usize = 0;
            const p = c.lua_tolstring(state, idx, &len);
            return .{ .string = p[0..len] };
        },
        else => return null,
    }
}

fn checkKey(state: ?*c.lua_State) [*c]const u8 {
    var len: usize = 0;
    const p = c.luaL_checklstring(state, 1, &len);
    if (!format.isValidKey(p[0..len])) {
        _ = c.luaL_error(state, "bad store key '%s' (use letters, digits, '_', '.', '-')", p);
    }
    return p;
}

/// `store.get(key [, default])`
fn get(state: ?*c.lua_State) callconv(.c) c_int {
    const ctx = sdk.contextUpvalue(state);
    _ = checkKey(state);
    c.lua_settop(state, 2); // key, default (nil if absent)
    pushTable(state, ctx); // key, default, store
    c.lua_pushvalue(state, 1);
    _ = c.lua_rawget(state, 3); // key, default, store, value
    if (c.lua_isnil(state, -1)) {
        c.lua_pushvalue(state, 2);
    }
    return 1;
}

/// `store.set(key, value)` — nil deletes.
fn set(state: ?*c.lua_State) callconv(.c) c_int {
    const ctx = sdk.contextUpvalue(state);
    _ = checkKey(state);
    c.lua_settop(state, 2);
    if (!c.lua_isnil(state, 2) and valueAt(state, 2) == null) {
        return c.luaL_error(state, "store values must be string, number or boolean (got %s)", c.luaL_typename(state, 2));
    }
    pushTable(state, ctx); // key, value, store
    c.lua_pushvalue(state, 1);
    c.lua_pushvalue(state, 2);
    c.lua_rawset(state, 3);
    save(state, ctx, 3);
    return 0;
}

/// `store.keys()` — sorted.
fn keys(state: ?*c.lua_State) callconv(.c) c_int {
    const ctx = sdk.contextUpvalue(state);
    pushTable(state, ctx); // store
    var key_list: [max_keys][]const u8 = undefined;
    var n: usize = 0;
    c.lua_pushnil(state);
    while (c.lua_next(state, 1) != 0) {
        c.lua_pop(state, 1);
        if (n >= max_keys) {
            c.lua_pop(state, 1);
            break;
        }
        var len: usize = 0;
        const p = c.lua_tolstring(state, -1, &len);
        key_list[n] = p[0..len];
        n += 1;
    }
    std.mem.sort([]const u8, key_list[0..n], {}, lessThan);
    c.lua_createtable(state, @intCast(n), 0);
    for (key_list[0..n], 1..) |key, i| {
        _ = c.lua_pushlstring(state, key.ptr, key.len);
        c.lua_rawseti(state, -2, @intCast(i));
    }
    return 1;
}

// ── tests ───────────────────────────────────────────────────────────────

const testing = std.testing;
const mod_instance = @import("mod_instance.zig");

const settings_src =
    \\local mod = {
    \\  name = "settings", version = "1.0.0",
    \\  run_at = "launch", permissions = { "store", "log" },
    \\}
    \\function mod.on_launch(sdk)
    \\  local n = sdk.store.get("launches", 0)
    \\  sdk.store.set("launches", n + 1)
    \\  sdk.store.set("name", "Ash \"Tarnished\"")
    \\  sdk.store.set("volume", 0.25)
    \\  sdk.store.set("enabled", true)
    \\  sdk.log.info("launches=" .. sdk.store.get("launches"))
    \\  sdk.log.info("keys=" .. table.concat(sdk.store.keys(), ","))
    \\end
    \\return mod
;

test "store persists across a reload of the same mod through the host" {
    var capture = host_mod.CaptureHost.init(testing.allocator);
    defer capture.deinit();

    {
        const m = try mod_instance.load(testing.allocator, settings_src, "=settings.lua", capture.host());
        defer mod_instance.destroy(m);
        try m.start();
        try testing.expect(capture.contains("launches=1"));
        try testing.expect(capture.contains("keys=enabled,launches,name,volume"));
    }
    const bytes = capture.storedBytes("settings").?;
    try testing.expect(std.mem.startsWith(u8, bytes, format.header ++ "\n"));
    try testing.expect(std.mem.indexOf(u8, bytes, "launches = 1\n") != null);
    try testing.expect(std.mem.indexOf(u8, bytes, "name = \"Ash \\\"Tarnished\\\"\"\n") != null);
    try testing.expect(std.mem.indexOf(u8, bytes, "volume = 0.25\n") != null);
    try testing.expect(std.mem.indexOf(u8, bytes, "enabled = true\n") != null);

    {
        const m = try mod_instance.load(testing.allocator, settings_src, "=settings.lua", capture.host());
        defer mod_instance.destroy(m);
        try m.start();
        try testing.expect(capture.contains("launches=2"));
    }
}

test "store: nil deletes, defaults apply, types and keys are checked" {
    var capture = host_mod.CaptureHost.init(testing.allocator);
    defer capture.deinit();

    const src =
        \\local mod = {
        \\  name = "kv", version = "1.0.0",
        \\  run_at = "launch", permissions = { "store" },
        \\}
        \\function mod.on_launch(sdk)
        \\  assert(sdk.store.get("missing") == nil)
        \\  assert(sdk.store.get("missing", "d") == "d")
        \\  sdk.store.set("a", 1)
        \\  assert(sdk.store.get("a") == 1)
        \\  sdk.store.set("a", nil)
        \\  assert(sdk.store.get("a", "gone") == "gone")
        \\  assert(#sdk.store.keys() == 0)
        \\  assert(not pcall(sdk.store.set, "bad key", 1))
        \\  assert(not pcall(sdk.store.set, "t", {}))
        \\  assert(not pcall(sdk.store.set, "f", function() end))
        \\  assert(not pcall(sdk.store.get, "spaces here"))
        \\end
        \\return mod
    ;
    const m = try mod_instance.load(testing.allocator, src, "=kv.lua", capture.host());
    defer mod_instance.destroy(m);
    try m.start();
    // Deleting the only key leaves a header-only file.
    try testing.expectEqualStrings(format.header ++ "\n", capture.storedBytes("kv").?);
}

test "a corrupt store is reported and treated as empty past the bad line" {
    var capture = host_mod.CaptureHost.init(testing.allocator);
    defer capture.deinit();
    const key = try testing.allocator.dupe(u8, "kv");
    const bad = try testing.allocator.dupe(u8, "# ermod store v1\ngood = 1\nthis is not a line\nlater = 2\n");
    try capture.stores.put(testing.allocator, key, bad);

    const src =
        \\local mod = {
        \\  name = "kv", version = "1.0.0",
        \\  run_at = "launch", permissions = { "store" },
        \\}
        \\function mod.on_launch(sdk)
        \\  assert(sdk.store.get("good") == 1)
        \\  assert(sdk.store.get("later") == nil)
        \\end
        \\return mod
    ;
    const m = try mod_instance.load(testing.allocator, src, "=kv.lua", capture.host());
    defer mod_instance.destroy(m);
    try m.start();
    try testing.expect(capture.contains("store is corrupt"));
}

test "stores are per mod" {
    var capture = host_mod.CaptureHost.init(testing.allocator);
    defer capture.deinit();
    const a_src =
        \\local mod = { name = "a", version = "1", run_at = "launch", permissions = { "store" } }
        \\function mod.on_launch(sdk) sdk.store.set("k", "from a") end
        \\return mod
    ;
    const b_src =
        \\local mod = { name = "b", version = "1", run_at = "launch", permissions = { "store" } }
        \\function mod.on_launch(sdk) assert(sdk.store.get("k") == nil) sdk.store.set("k", "from b") end
        \\return mod
    ;
    const a = try mod_instance.load(testing.allocator, a_src, "=a.lua", capture.host());
    defer mod_instance.destroy(a);
    try a.start();
    const b = try mod_instance.load(testing.allocator, b_src, "=b.lua", capture.host());
    defer mod_instance.destroy(b);
    try b.start();
    try testing.expect(std.mem.indexOf(u8, capture.storedBytes("a").?, "from a") != null);
    try testing.expect(std.mem.indexOf(u8, capture.storedBytes("b").?, "from b") != null);
}
