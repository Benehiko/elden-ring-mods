//! SDK module `hooks`: subscribing to named engine events.
//!
//! Mods never see an address or a signature — they name an event
//! ("on_rune_gain") and the engine owns everything below that line. That
//! indirection is what lets a game patch move a hook site without touching
//! a single mod.
//!
//! Handlers are stored in the Lua registry via luaL_ref and referenced by
//! integer, so a handler stays alive (and unreachable from other mods)
//! until the mod is unloaded.

const std = @import("std");
const c = @import("../lua/c.zig").c;
const sdk = @import("sdk.zig");

/// Events the engine can raise. Adding one here is the whole public
/// contract; the AOB signature that drives it is an engine detail.
pub const Event = enum {
    /// A frame is about to be presented. Handlers must be cheap.
    on_present,
    /// The player gained runes. Payload: { amount = <integer> }.
    on_rune_gain,
    /// The player died. Payload: {}.
    on_death,
};

/// LuaLS annotations for this module (see `stubs.zig`).
pub const stub =
    \\---@alias ermod.event
    \\---| "on_present"    # a frame is about to be presented; handlers must be cheap. Payload: {}
    \\---| "on_rune_gain"  # the player gained runes. Payload: { amount = integer }
    \\---| "on_death"      # the player died. Payload: {}
    \\
    \\---@class ermod.event.payload
    \\---@field amount integer? # on_rune_gain only
    \\
    \\---@class ermod.sdk.hooks
    \\local hooks = {}
    \\
    \\---Subscribe to a named engine event. Unknown names are an error at
    \\---subscribe time. Handlers run under the instruction budget; a handler
    \\---that errors strikes the mod (three strikes disables it), one that
    \\---exhausts its budget disables it on the spot.
    \\---@param event ermod.event
    \\---@param handler fun(ev: ermod.event.payload)
    \\function hooks.on(event, handler) end
    \\
;

pub const Subscription = struct {
    event: Event,
    /// luaL_ref handle into LUA_REGISTRYINDEX.
    ref: c_int,
};

pub const Registry = struct {
    gpa: std.mem.Allocator,
    subscriptions: std.ArrayList(Subscription) = .empty,

    pub fn init(gpa: std.mem.Allocator) Registry {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *Registry) void {
        self.subscriptions.deinit(self.gpa);
        self.* = undefined;
    }

    pub fn add(self: *Registry, event: Event, ref: c_int) !void {
        try self.subscriptions.append(self.gpa, .{ .event = event, .ref = ref });
    }

    pub fn count(self: *const Registry, event: Event) usize {
        var n: usize = 0;
        for (self.subscriptions.items) |s| {
            if (s.event == event) n += 1;
        }
        return n;
    }
};

pub fn push(state: *c.lua_State, ctx: *sdk.Context) void {
    c.lua_createtable(state, 0, 1);
    sdk.pushBound(state, ctx, on);
    c.lua_setfield(state, -2, "on");
}

/// `hooks.on(event_name, handler)`
fn on(state: ?*c.lua_State) callconv(.c) c_int {
    const ctx = sdk.contextUpvalue(state);

    var len: usize = 0;
    const name_ptr = c.luaL_checklstring(state, 1, &len);
    const name = if (name_ptr) |p| p[0..len] else "";
    c.luaL_checktype(state, 2, c.LUA_TFUNCTION);

    const event = std.meta.stringToEnum(Event, name) orelse {
        // An unknown event name is almost always a typo, and silently never
        // firing is the worst possible failure mode for a mod author.
        return c.luaL_error(state, "unknown event '%s'", name_ptr);
    };

    // luaL_ref pops the value it stores, so push the handler on top first.
    c.lua_pushvalue(state, 2);
    const ref = c.luaL_ref(state, c.LUA_REGISTRYINDEX);

    ctx.hooks.add(event, ref) catch {
        c.luaL_unref(state, c.LUA_REGISTRYINDEX, ref);
        return c.luaL_error(state, "out of memory registering handler");
    };
    return 0;
}

/// Push the handler registered under `ref` onto the stack, ready to call.
pub fn pushHandler(state: *c.lua_State, ref: c_int) void {
    _ = c.lua_rawgeti(state, c.LUA_REGISTRYINDEX, ref);
}
