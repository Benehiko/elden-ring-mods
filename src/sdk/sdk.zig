//! Building the `sdk` table a mod's entry point receives.
//!
//! The permission list in a mod's manifest is enforced here, by omission:
//! an undeclared module is simply never put on the table, so reaching for
//! it is a nil-index error inside the mod rather than a check the engine
//! has to remember to perform at every call site. A mod cannot widen its
//! own grant, because the table is built before its code ever runs.
//!
//! Per-mod context (which mod is calling, which host to call into) is
//! carried as an upvalue on each bound function rather than a global, so
//! it is unreachable and unforgeable from Lua.

const std = @import("std");
const c = @import("../lua/c.zig").c;
const manifest_mod = @import("../lua/manifest.zig");
const host_mod = @import("host.zig");
const log_module = @import("log.zig");
const hooks_module = @import("hooks.zig");
const params_module = @import("params.zig");
const perf_module = @import("perf.zig");
const store_module = @import("store.zig");
const ui_module = @import("ui.zig");
const screen_module = @import("screen.zig");

const Permission = manifest_mod.Permission;

/// Everything a bound SDK function needs to know about its caller.
///
/// One of these is owned by the mod's runtime state and pointed at from
/// every bound function's upvalue, so it must outlive the VM.
pub const Context = struct {
    gpa: std.mem.Allocator,
    /// Owned by the caller; must outlive the VM (the mod's name is copied
    /// out of the Lua state at load time for exactly this reason).
    mod_name: []const u8,
    host: host_mod.Host,
    hooks: hooks_module.Registry,
    /// The `store` module's hidden table (registry ref), once loaded.
    store_ref: c_int = c.LUA_NOREF,
    /// Scratch for reading and writing the store file, allocated on first
    /// use so mods that never touch `store` pay nothing.
    store_buf: ?[]u8 = null,
    /// Captures this mod asked for without naming them (`screen.capture()`
    /// numbers them `<mod>-<n>`).
    capture_seq: u32 = 0,

    pub fn init(gpa: std.mem.Allocator, mod_name: []const u8, host: host_mod.Host) Context {
        return .{
            .gpa = gpa,
            .mod_name = mod_name,
            .host = host,
            .hooks = hooks_module.Registry.init(gpa),
        };
    }

    /// The store scratch buffer, allocated on first call. Null on OOM.
    pub fn storeBuffer(self: *Context) ?[]u8 {
        if (self.store_buf == null) {
            self.store_buf = self.gpa.alloc(u8, host_mod.store_max_bytes) catch return null;
        }
        return self.store_buf;
    }

    /// Must run while the VM is still alive (the store ref belongs to it).
    pub fn deinit(self: *Context) void {
        if (self.store_buf) |b| self.gpa.free(b);
        self.hooks.deinit();
        self.* = undefined;
    }
};

/// Push a table exposing exactly the modules `permissions` grants.
///
/// `ctx` is borrowed by every function on the table, so it must outlive the
/// VM the table is pushed into.
pub fn push(
    state: *c.lua_State,
    ctx: *Context,
    permissions: manifest_mod.PermissionSet,
) void {
    c.lua_createtable(state, 0, @intCast(permissions.count()));

    if (permissions.contains(.log)) {
        log_module.push(state, ctx);
        c.lua_setfield(state, -2, "log");
    }
    if (permissions.contains(.hooks)) {
        hooks_module.push(state, ctx);
        c.lua_setfield(state, -2, "hooks");
    }
    if (permissions.contains(.params)) {
        params_module.push(state, ctx);
        c.lua_setfield(state, -2, "params");
    }
    if (permissions.contains(.perf)) {
        perf_module.push(state, ctx);
        c.lua_setfield(state, -2, "perf");
    }
    if (permissions.contains(.store)) {
        store_module.push(state, ctx);
        c.lua_setfield(state, -2, "store");
    }
    if (permissions.contains(.ui)) {
        ui_module.push(state, ctx);
        c.lua_setfield(state, -2, "ui");
    }
    if (permissions.contains(.screen)) {
        screen_module.push(state, ctx);
        c.lua_setfield(state, -2, "screen");
    }
}

/// Read the `Context` an SDK function was bound with. Every function this
/// module pushes carries it as upvalue 1.
pub fn contextUpvalue(state: ?*c.lua_State) *Context {
    const ptr = c.lua_touserdata(state, c.lua_upvalueindex(1)).?;
    return @ptrCast(@alignCast(ptr));
}

/// Push `func` as a closure carrying `ctx` as its first upvalue.
pub fn pushBound(state: *c.lua_State, ctx: *Context, func: c.lua_CFunction) void {
    c.lua_pushlightuserdata(state, ctx);
    c.lua_pushcclosure(state, func, 1);
}
