//! SDK module `screen`: capture what the game is drawing.
//!
//!   local path = sdk.screen.capture()              -- captures/<mod>-<n>.png
//!   local path = sdk.screen.capture("boss-hp", 4)  -- named, downscaled 4x
//!
//! The runtime reads the swapchain's back buffer at the end of the next
//! presented frame — after the overlay has drawn, so a mod's own `ui`
//! shows up in the file — and writes it as a PNG under `C:\ermod\captures`
//! off the render thread. `capture` returns the path the file will appear
//! at, or `nil, reason` if the host has no capture (no overlay, or the
//! previous request has not been consumed yet: one capture is in flight at
//! a time). The name is restricted to `[A-Za-z0-9._-]` so a mod cannot
//! write outside the captures directory.
//!
//! This is the engine's own eyes as much as a mod's: `ermod-engine shot`
//! asks for the same capture from the host, and `ermod-dev img` measures
//! the result. A mod that wants to prove its overlay drew can capture and
//! log the path; a test harness can diff two captures.

const std = @import("std");
const c = @import("../lua/c.zig").c;
const sdk = @import("sdk.zig");
const screen = @import("../screen.zig");

/// LuaLS annotations for this module (see `stubs.zig`).
pub const stub =
    \\---@class ermod.sdk.screen
    \\local screen = {}
    \\
    \\---Capture the next presented frame to `C:\ermod\captures\<name>.png`
    \\---(the overlay included). `name` defaults to `<mod>-<n>`; it may only
    \\---contain letters, digits, `.`, `_`, `-`. `scale` (1..16, default 1)
    \\---box-downsamples the image by that factor. Returns the path the file
    \\---will be written to, or nil and a reason (no capture on this host, or
    \\---one is already pending).
    \\---@param name string?
    \\---@param scale integer?
    \\---@return string? path
    \\---@return string? reason
    \\function screen.capture(name, scale) end
    \\
;

pub fn push(state: *c.lua_State, ctx: *sdk.Context) void {
    c.lua_createtable(state, 0, 1);
    sdk.pushBound(state, ctx, capture);
    c.lua_setfield(state, -2, "capture");
}

/// `screen.capture([name [, scale]])`
fn capture(state: ?*c.lua_State) callconv(.c) c_int {
    const ctx = sdk.contextUpvalue(state);
    var name_buf: [screen.max_name + 32]u8 = undefined;
    var name: []const u8 = undefined;
    if (c.lua_isnoneornil(state, 1)) {
        ctx.capture_seq += 1;
        name = std.fmt.bufPrint(&name_buf, "{s}-{d}", .{ ctx.mod_name, ctx.capture_seq }) catch {
            return fail(state, "mod name too long for a default capture name");
        };
    } else {
        var len: usize = 0;
        const p = c.luaL_checklstring(state, 1, &len);
        name = p[0..len];
    }
    const scale: c.lua_Integer = if (c.lua_isnoneornil(state, 2)) 1 else c.luaL_checkinteger(state, 2);
    if (scale < 1 or scale > screen.max_scale) {
        return fail(state, "scale must be 1..16");
    }
    const req = screen.Request.init(name, @intCast(scale)) catch |err| return switch (err) {
        error.BadName => fail(state, "name may only contain [A-Za-z0-9._-] (max 48 chars)"),
        error.BadScale => fail(state, "scale must be 1..16"),
    };
    if (!ctx.host.screenCapture(ctx.mod_name, req)) {
        return fail(state, "capture unavailable (no overlay, or one already pending)");
    }
    var path_buf: [screen.path_buf_len]u8 = undefined;
    const path = req.path(&path_buf);
    _ = c.lua_pushlstring(state, path.ptr, path.len);
    return 1;
}

fn fail(state: ?*c.lua_State, reason: [*:0]const u8) c_int {
    c.lua_pushnil(state);
    _ = c.lua_pushstring(state, reason);
    return 2;
}

// ── tests ────────────────────────────────────────────────────────────────

const testing = std.testing;
const host_mod = @import("host.zig");
const mod_instance = @import("mod_instance.zig");

test "screen.capture queues a request on the host and returns the path" {
    var capture_host = host_mod.CaptureHost.init(testing.allocator);
    defer capture_host.deinit();
    const src =
        \\local mod = {
        \\  name = "shooter", version = "1.0.0",
        \\  run_at = "launch", permissions = { "screen", "log" },
        \\}
        \\function mod.on_launch(sdk)
        \\  local p = sdk.screen.capture()
        \\  sdk.log.info("first=" .. p)
        \\  local q = sdk.screen.capture("boss.hp", 4)
        \\  sdk.log.info("second=" .. q)
        \\  local r, why = sdk.screen.capture("../evil")
        \\  assert(r == nil and why:find("A%-Za%-z0%-9"))
        \\  local s, why2 = sdk.screen.capture("ok", 99)
        \\  assert(s == nil and why2:find("scale"))
        \\  assert(not pcall(sdk.screen.capture, {}))
        \\end
        \\return mod
    ;
    const m = try mod_instance.load(testing.allocator, src, "=shooter.lua", capture_host.host());
    defer mod_instance.destroy(m);
    try m.start();
    try testing.expect(capture_host.contains("first=C:\\ermod\\captures\\shooter-1.png"));
    try testing.expect(capture_host.contains("second=C:\\ermod\\captures\\boss.hp.png"));
    try testing.expectEqual(@as(usize, 2), capture_host.captures.items.len);
    try testing.expectEqualStrings("shooter-1", capture_host.captures.items[0].name());
    try testing.expectEqual(@as(u8, 1), capture_host.captures.items[0].scale);
    try testing.expectEqualStrings("boss.hp", capture_host.captures.items[1].name());
    try testing.expectEqual(@as(u8, 4), capture_host.captures.items[1].scale);
}

test "screen.capture reports an unavailable host as nil, reason" {
    var capture_host = host_mod.CaptureHost.init(testing.allocator);
    defer capture_host.deinit();
    capture_host.captures_available = false;
    const src =
        \\local mod = {
        \\  name = "blind", version = "1.0.0",
        \\  run_at = "launch", permissions = { "screen", "log" },
        \\}
        \\function mod.on_launch(sdk)
        \\  local p, why = sdk.screen.capture("x")
        \\  assert(p == nil)
        \\  sdk.log.info("why=" .. why)
        \\end
        \\return mod
    ;
    const m = try mod_instance.load(testing.allocator, src, "=blind.lua", capture_host.host());
    defer mod_instance.destroy(m);
    try m.start();
    try testing.expect(capture_host.contains("why=capture unavailable"));
    try testing.expectEqual(@as(usize, 0), capture_host.captures.items.len);
}

test "screen is absent without the permission" {
    var capture_host = host_mod.CaptureHost.init(testing.allocator);
    defer capture_host.deinit();
    const src =
        \\local mod = {
        \\  name = "noscreen", version = "1.0.0",
        \\  run_at = "launch", permissions = { "log" },
        \\}
        \\function mod.on_launch(sdk)
        \\  assert(sdk.screen == nil)
        \\end
        \\return mod
    ;
    const m = try mod_instance.load(testing.allocator, src, "=noscreen.lua", capture_host.host());
    defer mod_instance.destroy(m);
    try m.start();
}
