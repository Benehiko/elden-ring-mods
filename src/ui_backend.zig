//! The drawing surface the `ui` SDK module talks to.
//!
//! An interface rather than a direct call into ImGui so the module — its
//! argument checking, its window scoping, its frame gating — is host-tested
//! against a recording backend with no GPU or window anywhere. The injected
//! runtime supplies the real one (`overlay.zig`, over the C shim in
//! `ui/imgui_shim.cpp`).
//!
//! Strings are NUL-terminated because that is what ImGui takes and what
//! `luaL_checkstring` hands out; nothing is copied on the way through.

const std = @import("std");

pub const WindowOpts = struct {
    x: f32 = 0,
    y: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,
    has_pos: bool = false,
    has_size: bool = false,
    /// Apply position/size only the first time the window appears.
    once: bool = true,
    flags: Flags = .{},

    pub const Flags = packed struct(u32) {
        no_title: bool = false,
        no_resize: bool = false,
        no_move: bool = false,
        no_background: bool = false,
        auto_size: bool = false,
        no_inputs: bool = false,
        _pad: u26 = 0,
    };
};

pub const Color = [4]f32;

pub const Backend = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Whether widgets may be issued right now (between the engine's
        /// begin/end of a frame).
        in_frame: *const fn (ptr: *anyopaque) bool,
        /// Whether the overlay owns input.
        focused: *const fn (ptr: *anyopaque) bool,
        /// Returns whether the window is visible; `window_end` must follow
        /// regardless.
        window_begin: *const fn (ptr: *anyopaque, title: [*:0]const u8, opts: WindowOpts) bool,
        window_end: *const fn (ptr: *anyopaque) void,
        text: *const fn (ptr: *anyopaque, text: [*:0]const u8, color: ?Color) void,
        button: *const fn (ptr: *anyopaque, label: [*:0]const u8) bool,
        checkbox: *const fn (ptr: *anyopaque, label: [*:0]const u8, value: bool) bool,
        slider: *const fn (ptr: *anyopaque, label: [*:0]const u8, value: f32, lo: f32, hi: f32) f32,
        slider_int: *const fn (ptr: *anyopaque, label: [*:0]const u8, value: i32, lo: i32, hi: i32) i32,
        /// `buf` holds the NUL-terminated current text and receives the
        /// edited text (capacity `buf.len`). Returns whether it changed.
        input: *const fn (ptr: *anyopaque, label: [*:0]const u8, buf: []u8) bool,
        combo: *const fn (ptr: *anyopaque, label: [*:0]const u8, index: i32, items: []const [*:0]const u8) i32,
        plot: *const fn (ptr: *anyopaque, label: [*:0]const u8, values: []const f32, lo: f32, hi: f32, height: f32, overlay: ?[*:0]const u8) void,
        progress: *const fn (ptr: *anyopaque, fraction: f32, overlay: ?[*:0]const u8) void,
        separator: *const fn (ptr: *anyopaque) void,
        same_line: *const fn (ptr: *anyopaque) void,
        spacing: *const fn (ptr: *anyopaque) void,
    };
};

/// A backend that records every call as one line of text and answers
/// widgets with scripted values. Tests read the transcript.
pub const Recording = struct {
    gpa: std.mem.Allocator,
    log: std.ArrayList(u8) = .empty,
    in_frame: bool = false,
    focused: bool = false,
    /// What `button` returns.
    button_pressed: bool = false,
    /// What `window_begin` returns.
    window_visible: bool = true,
    /// Value widgets return their input plus this delta (int-rounded for
    /// slider_int/combo), so a test can see the round trip.
    delta: f32 = 0,
    /// If set, `input` replaces the buffer with this and reports changed.
    input_replacement: ?[]const u8 = null,
    /// Open windows, to assert scoping.
    depth: usize = 0,
    max_depth: usize = 0,

    pub fn init(gpa: std.mem.Allocator) Recording {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *Recording) void {
        self.log.deinit(self.gpa);
        self.* = undefined;
    }

    pub fn backend(self: *Recording) Backend {
        return .{ .ptr = self, .vtable = &vtable };
    }

    pub fn transcript(self: *const Recording) []const u8 {
        return self.log.items;
    }

    pub fn contains(self: *const Recording, needle: []const u8) bool {
        return std.mem.indexOf(u8, self.log.items, needle) != null;
    }

    fn me(ptr: *anyopaque) *Recording {
        return @ptrCast(@alignCast(ptr));
    }

    fn put(self: *Recording, comptime fmt: []const u8, args: anytype) void {
        self.log.print(self.gpa, fmt ++ "\n", args) catch {};
    }

    const vtable = Backend.VTable{
        .in_frame = struct {
            fn f(ptr: *anyopaque) bool {
                return me(ptr).in_frame;
            }
        }.f,
        .focused = struct {
            fn f(ptr: *anyopaque) bool {
                return me(ptr).focused;
            }
        }.f,
        .window_begin = struct {
            fn f(ptr: *anyopaque, title: [*:0]const u8, opts: WindowOpts) bool {
                const self = me(ptr);
                self.depth += 1;
                self.max_depth = @max(self.max_depth, self.depth);
                self.put("window_begin {s} pos={d},{d}({any}) size={d},{d}({any}) once={any} flags={any}", .{
                    title, opts.x, opts.y, opts.has_pos, opts.w, opts.h, opts.has_size, opts.once, opts.flags,
                });
                return self.window_visible;
            }
        }.f,
        .window_end = struct {
            fn f(ptr: *anyopaque) void {
                const self = me(ptr);
                self.depth -= 1;
                self.put("window_end", .{});
            }
        }.f,
        .text = struct {
            fn f(ptr: *anyopaque, text: [*:0]const u8, color: ?Color) void {
                if (color) |col| {
                    me(ptr).put("text {s} color={d},{d},{d},{d}", .{ text, col[0], col[1], col[2], col[3] });
                } else {
                    me(ptr).put("text {s}", .{text});
                }
            }
        }.f,
        .button = struct {
            fn f(ptr: *anyopaque, label: [*:0]const u8) bool {
                me(ptr).put("button {s}", .{label});
                return me(ptr).button_pressed;
            }
        }.f,
        .checkbox = struct {
            fn f(ptr: *anyopaque, label: [*:0]const u8, value: bool) bool {
                me(ptr).put("checkbox {s} {any}", .{ label, value });
                return if (me(ptr).delta != 0) !value else value;
            }
        }.f,
        .slider = struct {
            fn f(ptr: *anyopaque, label: [*:0]const u8, value: f32, lo: f32, hi: f32) f32 {
                me(ptr).put("slider {s} {d} [{d},{d}]", .{ label, value, lo, hi });
                return value + me(ptr).delta;
            }
        }.f,
        .slider_int = struct {
            fn f(ptr: *anyopaque, label: [*:0]const u8, value: i32, lo: i32, hi: i32) i32 {
                me(ptr).put("slider_int {s} {d} [{d},{d}]", .{ label, value, lo, hi });
                return value + @as(i32, @intFromFloat(me(ptr).delta));
            }
        }.f,
        .input = struct {
            fn f(ptr: *anyopaque, label: [*:0]const u8, buf: []u8) bool {
                const self = me(ptr);
                const cur = std.mem.sliceTo(buf, 0);
                self.put("input {s} \"{s}\" cap={d}", .{ label, cur, buf.len });
                const rep = self.input_replacement orelse return false;
                const n = @min(rep.len, buf.len - 1);
                @memcpy(buf[0..n], rep[0..n]);
                buf[n] = 0;
                return true;
            }
        }.f,
        .combo = struct {
            fn f(ptr: *anyopaque, label: [*:0]const u8, index: i32, items: []const [*:0]const u8) i32 {
                const self = me(ptr);
                self.put("combo {s} {d} of {d}", .{ label, index, items.len });
                for (items) |it| self.put("  item {s}", .{it});
                return index + @as(i32, @intFromFloat(self.delta));
            }
        }.f,
        .plot = struct {
            fn f(ptr: *anyopaque, label: [*:0]const u8, values: []const f32, lo: f32, hi: f32, height: f32, overlay: ?[*:0]const u8) void {
                me(ptr).put("plot {s} n={d} [{d},{d}] h={d} overlay={s}", .{ label, values.len, lo, hi, height, overlay orelse "" });
            }
        }.f,
        .progress = struct {
            fn f(ptr: *anyopaque, fraction: f32, overlay: ?[*:0]const u8) void {
                me(ptr).put("progress {d} overlay={s}", .{ fraction, overlay orelse "" });
            }
        }.f,
        .separator = struct {
            fn f(ptr: *anyopaque) void {
                me(ptr).put("separator", .{});
            }
        }.f,
        .same_line = struct {
            fn f(ptr: *anyopaque) void {
                me(ptr).put("same_line", .{});
            }
        }.f,
        .spacing = struct {
            fn f(ptr: *anyopaque) void {
                me(ptr).put("spacing", .{});
            }
        }.f,
    };
};

test "recording backend tracks window depth" {
    var r = Recording.init(std.testing.allocator);
    defer r.deinit();
    const b = r.backend();
    _ = b.vtable.window_begin(b.ptr, "w", .{});
    try std.testing.expectEqual(@as(usize, 1), r.depth);
    b.vtable.window_end(b.ptr);
    try std.testing.expectEqual(@as(usize, 0), r.depth);
    try std.testing.expect(r.contains("window_begin w"));
}
