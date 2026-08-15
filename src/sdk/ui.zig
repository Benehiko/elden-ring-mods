//! SDK module `ui`: immediate-mode overlay widgets.
//!
//! Every call is only legal inside a frame — from a handler running during
//! `on_present` (or the state events derived there); anywhere else it is a
//! Lua error, because there is no frame to draw into. Windows are scoped by
//! a closure so a handler that errors halfway can never leave one open:
//!
//!   sdk.ui.window("Runes", function()
//!     sdk.ui.text("held: " .. runes)
//!     if sdk.ui.button("Reset") then runes = 0 end
//!     enabled = sdk.ui.checkbox("Enabled", enabled)
//!     volume  = sdk.ui.slider("Volume", volume, 0, 1)
//!     count   = sdk.ui.slider_int("Count", count, 1, 10)
//!     name    = sdk.ui.input("Name", name)
//!     idx     = sdk.ui.combo("Mode", idx, {"Off", "On", "Auto"})   -- 1-based
//!     sdk.ui.plot("Frame ms", samples, {min = 0, max = 33, height = 60})
//!     sdk.ui.progress(0.4, "40%")
//!     sdk.ui.separator(); sdk.ui.same_line(); sdk.ui.spacing()
//!   end, {x = 20, y = 20, w = 300, h = 0, once = true, flags = {"no_resize"}})
//!   sdk.ui.focused()   -- overlay has input focus?
//!
//! Widgets that edit a value take the current value and return the new one
//! — the immediate-mode contract; the module keeps no state for the mod.
//! Labels are unique per window (ImGui's rule; use "Label##id" to
//! disambiguate). Colored text: `sdk.ui.text(str, {r, g, b [, a]})`.
//!
//! The drawing surface is a `ui_backend.Backend` from the host: the real
//! overlay in the injected runtime, a recording backend in tests. Without
//! one (`nil` from the host) every call is an error saying so.

const std = @import("std");
const c = @import("../lua/c.zig").c;
const sdk = @import("sdk.zig");
const backend_mod = @import("../ui_backend.zig");
const Backend = backend_mod.Backend;

/// LuaLS annotations for this module (see `stubs.zig`).
pub const stub =
    \\---@alias ermod.ui.color number[] # {r, g, b [, a]} in 0..1
    \\---@alias ermod.ui.flag "no_title"|"no_resize"|"no_move"|"no_background"|"auto_size"|"no_inputs"
    \\
    \\---@class ermod.ui.window_opts
    \\---@field x number?
    \\---@field y number?
    \\---@field w number?
    \\---@field h number?
    \\---@field once boolean? # apply position/size only the first time (default true)
    \\---@field flags ermod.ui.flag[]?
    \\
    \\---@class ermod.ui.plot_opts
    \\---@field min number?
    \\---@field max number?
    \\---@field height number?
    \\---@field overlay string?
    \\
    \\---Immediate-mode overlay widgets. Every call is only legal inside a
    \\---frame — from a handler running during on_present (or the state
    \\---events derived there); elsewhere it is an error. Widgets that edit a
    \\---value take the current value and return the new one. Labels are
    \\---unique per window; use "Label##id" to disambiguate.
    \\---@class ermod.sdk.ui
    \\local ui = {}
    \\
    \\---Draw a window; `body` runs between Begin/End and can never leave one open.
    \\---@param title string
    \\---@param body fun()
    \\---@param opts ermod.ui.window_opts?
    \\function ui.window(title, body, opts) end
    \\
    \\---@param s string
    \\---@param color ermod.ui.color?
    \\function ui.text(s, color) end
    \\
    \\---@param label string
    \\---@return boolean pressed
    \\function ui.button(label) end
    \\
    \\---@param label string
    \\---@param value boolean
    \\---@return boolean
    \\function ui.checkbox(label, value) end
    \\
    \\---@param label string
    \\---@param value number
    \\---@param min number
    \\---@param max number
    \\---@return number
    \\function ui.slider(label, value, min, max) end
    \\
    \\---@param label string
    \\---@param value integer
    \\---@param min integer
    \\---@param max integer
    \\---@return integer
    \\function ui.slider_int(label, value, min, max) end
    \\
    \\---Single-line text input (up to 255 bytes).
    \\---@param label string
    \\---@param value string
    \\---@return string
    \\function ui.input(label, value) end
    \\
    \\---Drop-down; `index` is 1-based into `items`.
    \\---@param label string
    \\---@param index integer
    \\---@param items string[]
    \\---@return integer
    \\function ui.combo(label, index, items) end
    \\
    \\---Line plot of up to 1024 samples.
    \\---@param label string
    \\---@param samples number[]
    \\---@param opts ermod.ui.plot_opts?
    \\function ui.plot(label, samples, opts) end
    \\
    \\---@param fraction number # 0..1
    \\---@param overlay string?
    \\function ui.progress(fraction, overlay) end
    \\
    \\function ui.separator() end
    \\function ui.same_line() end
    \\function ui.spacing() end
    \\
    \\---Whether the overlay currently has input focus (Insert toggles it).
    \\---@return boolean
    \\function ui.focused() end
    \\
;

/// The most samples one `plot` call accepts.
const max_plot = 1024;
/// The most entries one `combo` call accepts.
const max_combo = 64;
/// Capacity of an `input` field, NUL included.
const input_cap = 256;

pub fn push(state: *c.lua_State, ctx: *sdk.Context) void {
    c.lua_createtable(state, 0, 16);
    const fns = [_]struct { name: [*:0]const u8, f: c.lua_CFunction }{
        .{ .name = "window", .f = window },
        .{ .name = "text", .f = text },
        .{ .name = "button", .f = button },
        .{ .name = "checkbox", .f = checkbox },
        .{ .name = "slider", .f = slider },
        .{ .name = "slider_int", .f = sliderInt },
        .{ .name = "input", .f = input },
        .{ .name = "combo", .f = combo },
        .{ .name = "plot", .f = plot },
        .{ .name = "progress", .f = progress },
        .{ .name = "separator", .f = separator },
        .{ .name = "same_line", .f = sameLine },
        .{ .name = "spacing", .f = spacing },
        .{ .name = "focused", .f = focused },
    };
    for (fns) |e| {
        sdk.pushBound(state, ctx, e.f);
        c.lua_setfield(state, -2, e.name);
    }
}

/// The backend, or a Lua error if there is none or no frame is open.
fn inFrame(state: ?*c.lua_State) Backend {
    const ctx = sdk.contextUpvalue(state);
    const b = ctx.host.uiBackend() orelse {
        _ = c.luaL_error(state, "ui is not available (no overlay on this host)");
        unreachable;
    };
    if (!b.vtable.in_frame(b.ptr)) {
        _ = c.luaL_error(state, "ui.* may only be called inside a frame handler (on_present)");
        unreachable;
    }
    return b;
}

fn checkString(state: ?*c.lua_State, idx: c_int) [*:0]const u8 {
    return c.luaL_checklstring(state, idx, null);
}

fn optString(state: ?*c.lua_State, idx: c_int) ?[*:0]const u8 {
    if (c.lua_isnoneornil(state, idx)) return null;
    return checkString(state, idx);
}

/// `ui.window(title, fn [, opts])`
fn window(state: ?*c.lua_State) callconv(.c) c_int {
    const b = inFrame(state);
    const title = checkString(state, 1);
    c.luaL_checktype(state, 2, c.LUA_TFUNCTION);
    const opts = windowOpts(state, 3);

    const visible = b.vtable.window_begin(b.ptr, title, opts);
    if (!visible) {
        b.vtable.window_end(b.ptr);
        return 0;
    }
    c.lua_pushvalue(state, 2);
    const rc = c.lua_pcallk(state, 0, 0, 0, 0, null);
    // End the window whether or not the body errored, then let the error
    // continue up to the dispatcher (which logs it and strikes the mod).
    b.vtable.window_end(b.ptr);
    if (rc != c.LUA_OK) return c.lua_error(state);
    return 0;
}

fn windowOpts(state: ?*c.lua_State, idx: c_int) backend_mod.WindowOpts {
    var opts = backend_mod.WindowOpts{};
    if (c.lua_isnoneornil(state, idx)) return opts;
    c.luaL_checktype(state, idx, c.LUA_TTABLE);
    if (numField(state, idx, "x")) |x| {
        opts.x = x;
        opts.has_pos = true;
    }
    if (numField(state, idx, "y")) |y| {
        opts.y = y;
        opts.has_pos = true;
    }
    if (numField(state, idx, "w")) |w| {
        opts.w = w;
        opts.has_size = true;
    }
    if (numField(state, idx, "h")) |h| {
        opts.h = h;
        opts.has_size = true;
    }
    _ = c.lua_getfield(state, idx, "once");
    if (!c.lua_isnil(state, -1)) opts.once = c.lua_toboolean(state, -1) != 0;
    c.lua_pop(state, 1);
    _ = c.lua_getfield(state, idx, "flags");
    if (c.lua_istable(state, -1)) {
        var i: c.lua_Integer = 1;
        while (true) : (i += 1) {
            _ = c.lua_rawgeti(state, -1, i);
            defer c.lua_pop(state, 1);
            if (c.lua_isnil(state, -1)) break;
            var len: usize = 0;
            const p = c.lua_tolstring(state, -1, &len) orelse continue;
            const name = p[0..len];
            if (std.mem.eql(u8, name, "no_title")) {
                opts.flags.no_title = true;
            } else if (std.mem.eql(u8, name, "no_resize")) {
                opts.flags.no_resize = true;
            } else if (std.mem.eql(u8, name, "no_move")) {
                opts.flags.no_move = true;
            } else if (std.mem.eql(u8, name, "no_background")) {
                opts.flags.no_background = true;
            } else if (std.mem.eql(u8, name, "auto_size")) {
                opts.flags.auto_size = true;
            } else if (std.mem.eql(u8, name, "no_inputs")) {
                opts.flags.no_inputs = true;
            } else {
                _ = c.luaL_error(state, "unknown window flag '%s'", p);
            }
        }
    }
    c.lua_pop(state, 1);
    return opts;
}

fn numField(state: ?*c.lua_State, idx: c_int, name: [*:0]const u8) ?f32 {
    _ = c.lua_getfield(state, idx, name);
    defer c.lua_pop(state, 1);
    if (c.lua_isnil(state, -1)) return null;
    var ok: c_int = 0;
    const v = c.lua_tonumberx(state, -1, &ok);
    if (ok == 0) {
        _ = c.luaL_error(state, "window option '%s' must be a number", name);
    }
    return @floatCast(v);
}

/// `ui.text(str [, {r, g, b [, a]}])`
fn text(state: ?*c.lua_State) callconv(.c) c_int {
    const b = inFrame(state);
    const s = checkString(state, 1);
    var color: ?backend_mod.Color = null;
    if (!c.lua_isnoneornil(state, 2)) {
        c.luaL_checktype(state, 2, c.LUA_TTABLE);
        var col = backend_mod.Color{ 1, 1, 1, 1 };
        for (0..4) |i| {
            _ = c.lua_rawgeti(state, 2, @intCast(i + 1));
            defer c.lua_pop(state, 1);
            if (c.lua_isnil(state, -1)) {
                if (i < 3) _ = c.luaL_error(state, "text color needs {r, g, b [, a]}");
                break;
            }
            col[i] = @floatCast(c.luaL_checknumber(state, -1));
        }
        color = col;
    }
    b.vtable.text(b.ptr, s, color);
    return 0;
}

fn button(state: ?*c.lua_State) callconv(.c) c_int {
    const b = inFrame(state);
    c.lua_pushboolean(state, @intFromBool(b.vtable.button(b.ptr, checkString(state, 1))));
    return 1;
}

fn checkbox(state: ?*c.lua_State) callconv(.c) c_int {
    const b = inFrame(state);
    const label = checkString(state, 1);
    const value = c.lua_toboolean(state, 2) != 0;
    c.lua_pushboolean(state, @intFromBool(b.vtable.checkbox(b.ptr, label, value)));
    return 1;
}

fn slider(state: ?*c.lua_State) callconv(.c) c_int {
    const b = inFrame(state);
    const label = checkString(state, 1);
    const value: f32 = @floatCast(c.luaL_checknumber(state, 2));
    const lo: f32 = @floatCast(c.luaL_checknumber(state, 3));
    const hi: f32 = @floatCast(c.luaL_checknumber(state, 4));
    c.lua_pushnumber(state, b.vtable.slider(b.ptr, label, value, lo, hi));
    return 1;
}

fn sliderInt(state: ?*c.lua_State) callconv(.c) c_int {
    const b = inFrame(state);
    const label = checkString(state, 1);
    const value: i32 = @intCast(c.luaL_checkinteger(state, 2));
    const lo: i32 = @intCast(c.luaL_checkinteger(state, 3));
    const hi: i32 = @intCast(c.luaL_checkinteger(state, 4));
    c.lua_pushinteger(state, b.vtable.slider_int(b.ptr, label, value, lo, hi));
    return 1;
}

/// `ui.input(label, value) -> value`
fn input(state: ?*c.lua_State) callconv(.c) c_int {
    const b = inFrame(state);
    const label = checkString(state, 1);
    var len: usize = 0;
    const p = c.luaL_optlstring(state, 2, "", &len);
    var buf: [input_cap]u8 = undefined;
    const n = @min(len, input_cap - 1);
    @memcpy(buf[0..n], p[0..n]);
    buf[n] = 0;
    _ = b.vtable.input(b.ptr, label, &buf);
    const out = std.mem.sliceTo(&buf, 0);
    _ = c.lua_pushlstring(state, out.ptr, out.len);
    return 1;
}

/// `ui.combo(label, index, items) -> index` (1-based)
fn combo(state: ?*c.lua_State) callconv(.c) c_int {
    const b = inFrame(state);
    const label = checkString(state, 1);
    const index = c.luaL_checkinteger(state, 2);
    c.luaL_checktype(state, 3, c.LUA_TTABLE);
    var items: [max_combo][*:0]const u8 = undefined;
    var n: usize = 0;
    while (n < max_combo) : (n += 1) {
        _ = c.lua_rawgeti(state, 3, @intCast(n + 1));
        if (c.lua_isnil(state, -1)) {
            c.lua_pop(state, 1);
            break;
        }
        // Left on the stack so the string pointer stays valid for the call.
        items[n] = c.lua_tolstring(state, -1, null) orelse {
            _ = c.luaL_error(state, "combo items must be strings");
            unreachable;
        };
    }
    if (n == max_combo) return c.luaL_error(state, "combo has too many items (max %d)", @as(c_int, max_combo));
    const idx0: i32 = @intCast(std.math.clamp(index - 1, 0, @as(c.lua_Integer, @intCast(n)) - 1));
    const out = b.vtable.combo(b.ptr, label, if (n == 0) 0 else idx0, items[0..n]);
    c.lua_pushinteger(state, out + 1);
    return 1;
}

/// `ui.plot(label, values [, {min=, max=, height=, overlay=}])`
fn plot(state: ?*c.lua_State) callconv(.c) c_int {
    const b = inFrame(state);
    const label = checkString(state, 1);
    c.luaL_checktype(state, 2, c.LUA_TTABLE);
    var values: [max_plot]f32 = undefined;
    var n: usize = 0;
    while (n < max_plot) : (n += 1) {
        _ = c.lua_rawgeti(state, 2, @intCast(n + 1));
        defer c.lua_pop(state, 1);
        if (c.lua_isnil(state, -1)) break;
        values[n] = @floatCast(c.luaL_checknumber(state, -1));
    }
    var lo: f32 = std.math.floatMax(f32); // ImGui: FLT_MAX means auto
    var hi: f32 = std.math.floatMax(f32);
    var height: f32 = 0;
    var overlay: ?[*:0]const u8 = null;
    if (!c.lua_isnoneornil(state, 3)) {
        c.luaL_checktype(state, 3, c.LUA_TTABLE);
        if (numField(state, 3, "min")) |v| lo = v;
        if (numField(state, 3, "max")) |v| hi = v;
        if (numField(state, 3, "height")) |v| height = v;
        _ = c.lua_getfield(state, 3, "overlay");
        // Stays on the stack for the duration of the call.
        if (!c.lua_isnil(state, -1)) overlay = c.luaL_checklstring(state, -1, null);
    }
    b.vtable.plot(b.ptr, label, values[0..n], lo, hi, height, overlay);
    return 0;
}

fn progress(state: ?*c.lua_State) callconv(.c) c_int {
    const b = inFrame(state);
    const fraction: f32 = @floatCast(c.luaL_checknumber(state, 1));
    b.vtable.progress(b.ptr, fraction, optString(state, 2));
    return 0;
}

fn separator(state: ?*c.lua_State) callconv(.c) c_int {
    const b = inFrame(state);
    b.vtable.separator(b.ptr);
    return 0;
}

fn sameLine(state: ?*c.lua_State) callconv(.c) c_int {
    const b = inFrame(state);
    b.vtable.same_line(b.ptr);
    return 0;
}

fn spacing(state: ?*c.lua_State) callconv(.c) c_int {
    const b = inFrame(state);
    b.vtable.spacing(b.ptr);
    return 0;
}

/// `ui.focused()` — legal outside a frame too; false without a backend.
fn focused(state: ?*c.lua_State) callconv(.c) c_int {
    const ctx = sdk.contextUpvalue(state);
    const f = if (ctx.host.uiBackend()) |b| b.vtable.focused(b.ptr) else false;
    c.lua_pushboolean(state, @intFromBool(f));
    return 1;
}

// ── tests ───────────────────────────────────────────────────────────────

const testing = std.testing;
const host_mod = @import("host.zig");
const mod_instance = @import("mod_instance.zig");

const draw_src =
    \\local mod = {
    \\  name = "draw", version = "1.0.0",
    \\  run_at = "events", permissions = { "ui", "hooks", "log" },
    \\}
    \\local enabled, volume, count, name, mode = false, 0.5, 3, "Ash", 2
    \\function mod.setup(sdk)
    \\  sdk.hooks.on("on_present", function()
    \\    sdk.ui.window("Panel", function()
    \\      sdk.ui.text("hello")
    \\      sdk.ui.text("warn", {1, 0.5, 0})
    \\      if sdk.ui.button("Go") then sdk.log.info("pressed") end
    \\      enabled = sdk.ui.checkbox("Enabled", enabled)
    \\      volume = sdk.ui.slider("Volume", volume, 0, 1)
    \\      count = sdk.ui.slider_int("Count", count, 1, 10)
    \\      name = sdk.ui.input("Name", name)
    \\      mode = sdk.ui.combo("Mode", mode, {"Off", "On", "Auto"})
    \\      sdk.ui.plot("Frame", {1, 2, 3}, {min = 0, max = 4, height = 40, overlay = "ms"})
    \\      sdk.ui.progress(0.25, "25%")
    \\      sdk.ui.separator(); sdk.ui.same_line(); sdk.ui.spacing()
    \\    end, {x = 10, y = 20, w = 300, once = false, flags = {"no_resize", "auto_size"}})
    \\    sdk.log.info(string.format("enabled=%s volume=%.2f count=%d name=%s mode=%d focused=%s",
    \\      tostring(enabled), volume, count, name, mode, tostring(sdk.ui.focused())))
    \\  end)
    \\end
    \\return mod
;

test "ui widgets reach the backend and round-trip values" {
    var capture = host_mod.CaptureHost.init(testing.allocator);
    defer capture.deinit();
    var rec = backend_mod.Recording.init(testing.allocator);
    defer rec.deinit();
    capture.ui = rec.backend();

    const m = try mod_instance.load(testing.allocator, draw_src, "=draw.lua", capture.host());
    defer mod_instance.destroy(m);
    try m.start();

    rec.in_frame = true;
    rec.button_pressed = true;
    rec.delta = 1;
    rec.input_replacement = "Tarnished";
    rec.focused = true;
    m.fire(.on_present, .none);

    try testing.expect(rec.contains("window_begin Panel pos=10,20(true) size=300,0(true) once=false"));
    try testing.expect(rec.contains("no_resize = true"));
    try testing.expect(rec.contains("auto_size = true"));
    try testing.expect(rec.contains("text hello\n"));
    try testing.expect(rec.contains("text warn color=1,0.5,0,1"));
    try testing.expect(rec.contains("button Go"));
    try testing.expect(capture.contains("pressed"));
    try testing.expect(rec.contains("checkbox Enabled false"));
    try testing.expect(rec.contains("slider Volume 0.5 [0,1]"));
    try testing.expect(rec.contains("slider_int Count 3 [1,10]"));
    try testing.expect(rec.contains("input Name \"Ash\" cap=256"));
    try testing.expect(rec.contains("combo Mode 1 of 3")); // 0-based at the backend
    try testing.expect(rec.contains("  item Auto"));
    try testing.expect(rec.contains("plot Frame n=3 [0,4] h=40 overlay=ms"));
    try testing.expect(rec.contains("progress 0.25 overlay=25%"));
    try testing.expect(rec.contains("separator\nsame_line\nspacing\nwindow_end\n"));
    // Returned values: checkbox flipped, slider +1, count +1, input replaced,
    // combo +1 (back to 1-based), focused true.
    try testing.expect(capture.contains("enabled=true volume=1.50 count=4 name=Tarnished mode=3 focused=true"));
    try testing.expectEqual(@as(usize, 0), rec.depth);
    try testing.expectEqual(@as(usize, 1), rec.max_depth);
}

test "ui outside a frame is an error, and the window still closes on a body error" {
    var capture = host_mod.CaptureHost.init(testing.allocator);
    defer capture.deinit();
    var rec = backend_mod.Recording.init(testing.allocator);
    defer rec.deinit();
    capture.ui = rec.backend();

    const src =
        \\local mod = {
        \\  name = "oops", version = "1.0.0",
        \\  run_at = "events", permissions = { "ui", "hooks" },
        \\}
        \\function mod.setup(sdk)
        \\  assert(not pcall(sdk.ui.text, "too early"))
        \\  local ok, err = pcall(sdk.ui.text, "too early")
        \\  assert(err:find("inside a frame"), err)
        \\  sdk.hooks.on("on_present", function()
        \\    sdk.ui.window("W", function()
        \\      sdk.ui.text("before")
        \\      error("body failed")
        \\    end)
        \\  end)
        \\end
        \\return mod
    ;
    const m = try mod_instance.load(testing.allocator, src, "=oops.lua", capture.host());
    defer mod_instance.destroy(m);
    try m.start();
    try testing.expect(!rec.contains("too early"));

    rec.in_frame = true;
    m.fire(.on_present, .none);
    try testing.expect(rec.contains("text before"));
    try testing.expectEqual(@as(usize, 0), rec.depth); // window_end ran despite the error
    try testing.expect(capture.contains("body failed")); // and the error still reached the log
    try testing.expectEqual(@as(u32, 1), m.strikes);
}

test "an invisible (collapsed) window skips its body but still ends" {
    var capture = host_mod.CaptureHost.init(testing.allocator);
    defer capture.deinit();
    var rec = backend_mod.Recording.init(testing.allocator);
    defer rec.deinit();
    capture.ui = rec.backend();
    rec.window_visible = false;

    const src =
        \\local mod = {
        \\  name = "hidden", version = "1.0.0",
        \\  run_at = "events", permissions = { "ui", "hooks" },
        \\}
        \\function mod.setup(sdk)
        \\  sdk.hooks.on("on_present", function()
        \\    sdk.ui.window("W", function() sdk.ui.text("never") end)
        \\  end)
        \\end
        \\return mod
    ;
    const m = try mod_instance.load(testing.allocator, src, "=hidden.lua", capture.host());
    defer mod_instance.destroy(m);
    try m.start();
    rec.in_frame = true;
    m.fire(.on_present, .none);
    try testing.expect(!rec.contains("never"));
    try testing.expect(rec.contains("window_end"));
    try testing.expectEqual(@as(usize, 0), rec.depth);
}

test "ui without a backend reports itself unavailable" {
    var capture = host_mod.CaptureHost.init(testing.allocator);
    defer capture.deinit();

    const src =
        \\local mod = {
        \\  name = "nobackend", version = "1.0.0",
        \\  run_at = "launch", permissions = { "ui" },
        \\}
        \\function mod.on_launch(sdk)
        \\  local ok, err = pcall(sdk.ui.text, "x")
        \\  assert(not ok and err:find("not available"), err)
        \\  assert(sdk.ui.focused() == false)
        \\end
        \\return mod
    ;
    const m = try mod_instance.load(testing.allocator, src, "=nobackend.lua", capture.host());
    defer mod_instance.destroy(m);
    try m.start();
}
