//! SDK module `log`: structured logging, tagged with the calling mod.
//!
//! Mods have no `print` — the sandbox strips it — so this is the only way a
//! mod can say anything. Lines are attributed to the mod by the engine
//! rather than by the caller, so a mod cannot log under another's name.

const std = @import("std");
const c = @import("../lua/c.zig").c;
const host_mod = @import("host.zig");
const sdk = @import("sdk.zig");

/// LuaLS annotations for this module, assembled by `stubs.zig` into the
/// file `ermod stubs` emits. Kept beside the bindings so a new function
/// without a stub is visible in the same diff.
pub const stub =
    \\---@class ermod.sdk.log
    \\local log = {}
    \\
    \\---Write an info line to the engine log, tagged with this mod's name.
    \\---@param msg string
    \\function log.info(msg) end
    \\
    \\---Write a warning line.
    \\---@param msg string
    \\function log.warn(msg) end
    \\
    \\---Write an error line.
    \\---@param msg string
    \\function log.error(msg) end
    \\
;

pub fn push(state: *c.lua_State, ctx: *sdk.Context) void {
    c.lua_createtable(state, 0, 3);

    sdk.pushBound(state, ctx, info);
    c.lua_setfield(state, -2, "info");
    sdk.pushBound(state, ctx, warn);
    c.lua_setfield(state, -2, "warn");
    sdk.pushBound(state, ctx, err);
    c.lua_setfield(state, -2, "error");
}

fn info(state: ?*c.lua_State) callconv(.c) c_int {
    return logAt(state, .info);
}

fn warn(state: ?*c.lua_State) callconv(.c) c_int {
    return logAt(state, .warn);
}

fn err(state: ?*c.lua_State) callconv(.c) c_int {
    return logAt(state, .err);
}

fn logAt(state: ?*c.lua_State, level: host_mod.Level) c_int {
    const ctx = sdk.contextUpvalue(state);

    // luaL_checklstring raises a Lua error on a non-string argument, which
    // is the behaviour we want: a mod logging a table is a bug in the mod.
    var len: usize = 0;
    const ptr = c.luaL_checklstring(state, 1, &len);
    const msg = if (ptr) |p| p[0..len] else "";

    ctx.host.log(ctx.mod_name, level, msg);
    return 0;
}
