//! SDK module `perf`: frame timing and per-mod script cost.
//!
//! Read-only views over `perf.Stats`, which the engine feeds (the present
//! hook records frames, the dispatcher records each handler's duration). A
//! mod cannot write any of it. On a host with no stats every number is zero
//! and `mods()` is empty — the module is present but has nothing to say.
//!
//!   sdk.perf.frame_ms()   -- last present-to-present interval, ms
//!   sdk.perf.fps()        -- moving average over the last 120 frames
//!   sdk.perf.frame()      -- frames presented since the hook went live
//!   sdk.perf.now_ms()     -- monotonic clock, ms, for a mod's own timing
//!   sdk.perf.mods()       -- { {name=, last_ms=, avg_ms=, calls=, total_ms=}, ... }
//!
//! `mods()` lists every loaded mod, not only the caller: the point of a
//! performance monitor is to show which mod is eating the frame.

const std = @import("std");
const c = @import("../lua/c.zig").c;
const sdk = @import("sdk.zig");
const perf = @import("../perf.zig");

/// LuaLS annotations for this module (see `stubs.zig`).
pub const stub =
    \\---@class ermod.perf.mod
    \\---@field name string
    \\---@field last_ms number  # cost of the mod's most recent handler call
    \\---@field avg_ms number   # mean over the last 120 calls
    \\---@field total_ms number # since load
    \\---@field calls integer
    \\
    \\---@class ermod.sdk.perf
    \\local perf = {}
    \\
    \\---Last present-to-present interval in milliseconds.
    \\---@return number
    \\function perf.frame_ms() end
    \\
    \\---Moving-average frames per second over the last 120 frames.
    \\---@return number
    \\function perf.fps() end
    \\
    \\---Frames presented since the hook went live.
    \\---@return integer
    \\function perf.frame() end
    \\
    \\---Monotonic clock in milliseconds, for a mod's own timing.
    \\---@return number
    \\function perf.now_ms() end
    \\
    \\---Per-mod handler cost for every loaded mod (not only the caller).
    \\---@return ermod.perf.mod[]
    \\function perf.mods() end
    \\
;

pub fn push(state: *c.lua_State, ctx: *sdk.Context) void {
    c.lua_createtable(state, 0, 5);
    sdk.pushBound(state, ctx, frameMs);
    c.lua_setfield(state, -2, "frame_ms");
    sdk.pushBound(state, ctx, fps);
    c.lua_setfield(state, -2, "fps");
    sdk.pushBound(state, ctx, frame);
    c.lua_setfield(state, -2, "frame");
    sdk.pushBound(state, ctx, nowMs);
    c.lua_setfield(state, -2, "now_ms");
    sdk.pushBound(state, ctx, mods);
    c.lua_setfield(state, -2, "mods");
}

fn stats(state: ?*c.lua_State) ?*perf.Stats {
    return sdk.contextUpvalue(state).host.perfStats();
}

fn frameMs(state: ?*c.lua_State) callconv(.c) c_int {
    c.lua_pushnumber(state, if (stats(state)) |s| s.frameMs() else 0);
    return 1;
}

fn fps(state: ?*c.lua_State) callconv(.c) c_int {
    c.lua_pushnumber(state, if (stats(state)) |s| s.fps() else 0);
    return 1;
}

fn frame(state: ?*c.lua_State) callconv(.c) c_int {
    c.lua_pushinteger(state, if (stats(state)) |s| @intCast(s.frames) else 0);
    return 1;
}

fn nowMs(state: ?*c.lua_State) callconv(.c) c_int {
    const now: f64 = if (stats(state)) |s| @floatFromInt(s.clock()) else 0;
    c.lua_pushnumber(state, now / std.time.ns_per_ms);
    return 1;
}

fn nsToMs(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / std.time.ns_per_ms;
}

fn mods(state: ?*c.lua_State) callconv(.c) c_int {
    c.lua_newtable(state);
    const s = stats(state) orelse return 1;
    var n: c.lua_Integer = 0;
    for (s.modSlots()) |m| {
        if (!m.used) continue;
        n += 1;
        c.lua_createtable(state, 0, 5);
        _ = c.lua_pushlstring(state, m.name.ptr, m.name.len);
        c.lua_setfield(state, -2, "name");
        c.lua_pushnumber(state, nsToMs(m.last_ns));
        c.lua_setfield(state, -2, "last_ms");
        c.lua_pushnumber(state, nsToMs(m.avg_ns));
        c.lua_setfield(state, -2, "avg_ms");
        c.lua_pushnumber(state, nsToMs(m.total_ns));
        c.lua_setfield(state, -2, "total_ms");
        c.lua_pushinteger(state, @intCast(m.calls));
        c.lua_setfield(state, -2, "calls");
        c.lua_rawseti(state, -2, n);
    }
    return 1;
}

// ── tests ───────────────────────────────────────────────────────────────

const testing = std.testing;
const host_mod = @import("host.zig");
const mod_instance = @import("mod_instance.zig");

const FakeClock = struct {
    var now: u64 = 0;
    fn read() u64 {
        return now;
    }
};

test "perf reports frame stats and every mod's cost" {
    var capture = host_mod.CaptureHost.init(testing.allocator);
    defer capture.deinit();
    var stats_ = perf.Stats.init(FakeClock.read);
    capture.perf = &stats_;

    const src =
        \\local mod = {
        \\  name = "monitor", version = "1.0.0",
        \\  run_at = "events", permissions = { "perf", "hooks", "log" },
        \\}
        \\function mod.setup(sdk)
        \\  sdk.hooks.on("on_present", function()
        \\    sdk.log.info(string.format("fps=%.0f frame_ms=%.1f frame=%d now=%.0f",
        \\      sdk.perf.fps(), sdk.perf.frame_ms(), sdk.perf.frame(), sdk.perf.now_ms()))
        \\    for _, m in ipairs(sdk.perf.mods()) do
        \\      sdk.log.info(string.format("mod %s calls=%d", m.name, m.calls))
        \\    end
        \\  end)
        \\end
        \\return mod
    ;
    const m = try mod_instance.load(testing.allocator, src, "=monitor.lua", capture.host());
    defer mod_instance.destroy(m);
    try m.start();

    // Two frames 20 ms apart, then a dispatch: the handler sees them.
    stats_.frame(1_000_000_000);
    stats_.frame(1_020_000_000);
    FakeClock.now = 1_020_000_000;
    m.fire(.on_present, .none);
    try testing.expect(capture.contains("fps=50 frame_ms=20.0 frame=2 now=1020"));
    // The dispatcher recorded the call under the mod's registered slot.
    try testing.expect(capture.contains("mod monitor calls=0")); // seen mid-call, before record
    m.fire(.on_present, .none);
    try testing.expect(capture.contains("mod monitor calls=1"));
}

test "perf without stats reports zeros and no mods" {
    var capture = host_mod.CaptureHost.init(testing.allocator);
    defer capture.deinit();

    const src =
        \\local mod = {
        \\  name = "quiet", version = "1.0.0",
        \\  run_at = "launch", permissions = { "perf" },
        \\}
        \\function mod.on_launch(sdk)
        \\  assert(sdk.perf.fps() == 0)
        \\  assert(sdk.perf.frame_ms() == 0)
        \\  assert(sdk.perf.frame() == 0)
        \\  assert(sdk.perf.now_ms() == 0)
        \\  assert(#sdk.perf.mods() == 0)
        \\end
        \\return mod
    ;
    const m = try mod_instance.load(testing.allocator, src, "=quiet.lua", capture.host());
    defer mod_instance.destroy(m);
    try m.start();
}
