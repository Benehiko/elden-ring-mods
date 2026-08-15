//! Screen capture requests: the shape a capture is asked for, shared by
//! the `screen` SDK module (a mod asks), the host trigger (`ermod-engine
//! shot` writes a request file the runtime polls) and the runtime's
//! capture path (the render thread reads back the frame, a worker encodes
//! it). Pure data and parsing — host-tested; the D3D12 side is in
//! `src/runtime/screenshot.zig`. Lives in `common/` because the launcher
//! (`ermod-engine shot`) writes the request the runtime reads.
//!
//! A request names the output (`captures/<name>.png` in the prefix's
//! `C:\ermod`) and an integer downscale factor. Names are restricted to
//! `[A-Za-z0-9._-]` so a mod cannot point the write anywhere else.

const std = @import("std");

pub const max_name = 48;
pub const max_scale = 16;

/// Where captures land, in the prefix (raw Win32 path; the runtime writes
/// it, the host resolves it under `<compatdata>/pfx/drive_c`).
pub const dir = "C:\\ermod\\captures";
/// The request file the host trigger writes and the runtime consumes.
pub const request_file = "C:\\ermod\\capture.req";
/// The same, relative to the prefix's `drive_c`.
pub const dir_rel = "ermod/captures";
pub const request_file_rel = "ermod/capture.req";

pub const Request = struct {
    name_buf: [max_name]u8 = undefined,
    name_len: u8 = 0,
    scale: u8 = 1,

    pub fn name(self: *const Request) []const u8 {
        return self.name_buf[0..self.name_len];
    }

    pub const InitError = error{ BadName, BadScale };

    pub fn init(name_text: []const u8, scale: u32) InitError!Request {
        if (name_text.len == 0 or name_text.len > max_name) return error.BadName;
        for (name_text) |ch| {
            const ok = std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '-' or ch == '.';
            if (!ok) return error.BadName;
        }
        if (std.mem.eql(u8, name_text, ".") or std.mem.eql(u8, name_text, "..")) return error.BadName;
        if (scale < 1 or scale > max_scale) return error.BadScale;
        var r = Request{ .name_len = @intCast(name_text.len), .scale = @intCast(scale) };
        @memcpy(r.name_buf[0..name_text.len], name_text);
        return r;
    }

    /// The output path in the prefix, e.g. `C:\ermod\captures\shot-1.png`.
    pub fn path(self: *const Request, buf: []u8) []const u8 {
        return std.fmt.bufPrint(buf, "{s}\\{s}.png", .{ dir, self.name() }) catch unreachable;
    }

    /// The temp path the file is written to before an atomic rename, so a
    /// waiting host never reads a half-written PNG.
    pub fn tmpPath(self: *const Request, buf: []u8) []const u8 {
        return std.fmt.bufPrint(buf, "{s}\\{s}.png.part", .{ dir, self.name() }) catch unreachable;
    }

    /// The request-file line: `<name> [scale]`. Whitespace-trimmed; an
    /// empty or malformed file is no request.
    pub fn parse(text: []const u8) ?Request {
        var it = std.mem.tokenizeAny(u8, text, " \t\r\n");
        const nm = it.next() orelse return null;
        var scale: u32 = 1;
        if (it.next()) |s| scale = std.fmt.parseInt(u32, s, 10) catch return null;
        if (it.next() != null) return null;
        return init(nm, scale) catch null;
    }

    /// The request-file line for `parse` (what the host writes).
    pub fn format(self: *const Request, buf: []u8) []const u8 {
        return std.fmt.bufPrint(buf, "{s} {d}\n", .{ self.name(), self.scale }) catch unreachable;
    }
};

pub const path_buf_len = dir.len + 1 + max_name + ".png.part".len;

const testing = std.testing;

test "requests validate the name and scale" {
    const r = try Request.init("shot-1.a_b", 4);
    try testing.expectEqualStrings("shot-1.a_b", r.name());
    try testing.expectEqual(@as(u8, 4), r.scale);
    try testing.expectError(error.BadName, Request.init("", 1));
    try testing.expectError(error.BadName, Request.init("../etc", 1));
    try testing.expectError(error.BadName, Request.init("a b", 1));
    try testing.expectError(error.BadName, Request.init("..", 1));
    try testing.expectError(error.BadName, Request.init("x" ** 49, 1));
    try testing.expectError(error.BadScale, Request.init("ok", 0));
    try testing.expectError(error.BadScale, Request.init("ok", 17));
}

test "paths land under the captures directory" {
    const r = try Request.init("hud", 1);
    var buf: [path_buf_len]u8 = undefined;
    try testing.expectEqualStrings("C:\\ermod\\captures\\hud.png", r.path(&buf));
    try testing.expectEqualStrings("C:\\ermod\\captures\\hud.png.part", r.tmpPath(&buf));
}

test "the request file round-trips" {
    const r = try Request.init("frame-12", 2);
    var buf: [64]u8 = undefined;
    const line = r.format(&buf);
    try testing.expectEqualStrings("frame-12 2\n", line);
    const back = Request.parse(line).?;
    try testing.expectEqualStrings("frame-12", back.name());
    try testing.expectEqual(@as(u8, 2), back.scale);
    try testing.expectEqual(@as(u8, 1), Request.parse("bare\n").?.scale);
    try testing.expect(Request.parse("") == null);
    try testing.expect(Request.parse("a b c") == null);
    try testing.expect(Request.parse("name x") == null);
    try testing.expect(Request.parse("../x 1") == null);
}
