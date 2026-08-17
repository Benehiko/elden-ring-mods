//! Synthetic input requests: the shape a simulated button press is asked
//! for, shared by the host trigger (`ermod-engine key` / `ermod-engine pad`
//! writes a request file the runtime polls), the `input` SDK module (a mod
//! asks) and the runtime's virtual device (`src/runtime/vinput.zig`, which
//! merges the synthetic state into what the game reads through DirectInput).
//! Pure data and parsing — host-tested; the hook side is in the runtime.
//!
//! Why this exists: the engine can already see the game (frame capture), but
//! could not touch it. Every live test that needed a button — reaching a
//! cutscene, loading a character, opening a menu — stalled on a human. A
//! press has to come from inside the process, because ELDEN RING reads its
//! keyboard and pad through DirectInput8, which keeps its own state and
//! never looks at the window message queue.
//!
//! A request names one input and how long to hold it, in frames. Frames
//! rather than milliseconds because the game samples input once per frame:
//! a press held for less than a frame can be missed entirely, and "3 frames"
//! is a promise the runtime can actually keep, where "50 ms" is not.

const std = @import("std");

/// The request file the host trigger writes and the runtime consumes.
pub const request_file = "C:\\ermod\\input.req";
/// The same, relative to the prefix's `drive_c`.
pub const request_file_rel = "ermod/input.req";

/// The longest a single press may be held. A test that wants a key down for
/// longer than ten seconds at 60 fps wants a different mechanism (and a
/// stuck key that outlives the test is worse than a refused request).
pub const max_hold = 600;
/// The most inputs one request may name. A request is a chord, not a macro:
/// sequences are several requests, so that each one's timing is visible.
pub const max_inputs = 4;

/// What the game can be told was pressed.
///
/// Two families, because the game reads two devices. Keyboard codes are
/// DirectInput scan codes (`DIK_*`), which is what `GetDeviceState` fills a
/// 256-byte array with — *not* Windows virtual-key codes, which is the trap
/// this enum exists to keep callers out of. Pad buttons are `XINPUT_GAMEPAD`
/// bits, which is how DirectInput reports an XInput pad's buttons.
pub const Input = union(enum) {
    key: Key,
    pad: Pad,

    /// Parse a name as written on the command line: `e`, `space`, `escape`
    /// for keys; `pad:a`, `pad:start` for buttons.
    pub fn parse(text: []const u8) ?Input {
        if (std.mem.startsWith(u8, text, "pad:")) {
            return .{ .pad = Pad.parse(text["pad:".len..]) orelse return null };
        }
        return .{ .key = Key.parse(text) orelse return null };
    }

    pub fn name(self: Input) []const u8 {
        return switch (self) {
            .key => |k| k.name(),
            .pad => |p| p.name(),
        };
    }
};

/// A keyboard key, as a DirectInput scan code.
///
/// Only the keys a test plausibly needs are named. The set is deliberately
/// small: an unnamed key is a compile-time-visible gap, where a raw number
/// would be a silent wrong-key press that looks like a broken hook.
pub const Key = enum(u8) {
    escape = 0x01,
    @"1" = 0x02,
    @"2" = 0x03,
    @"3" = 0x04,
    @"4" = 0x05,
    @"5" = 0x06,
    @"6" = 0x07,
    @"7" = 0x08,
    @"8" = 0x09,
    @"9" = 0x0A,
    @"0" = 0x0B,
    q = 0x10,
    w = 0x11,
    e = 0x12,
    r = 0x13,
    t = 0x14,
    y = 0x15,
    u = 0x16,
    i = 0x17,
    o = 0x18,
    p = 0x19,
    @"return" = 0x1C,
    lctrl = 0x1D,
    a = 0x1E,
    s = 0x1F,
    d = 0x20,
    f = 0x21,
    g = 0x22,
    h = 0x23,
    j = 0x24,
    k = 0x25,
    l = 0x26,
    lshift = 0x2A,
    z = 0x2C,
    x = 0x2D,
    c = 0x2E,
    v = 0x2F,
    b = 0x30,
    n = 0x31,
    m = 0x32,
    space = 0x39,
    f1 = 0x3B,
    f2 = 0x3C,
    f3 = 0x3D,
    f4 = 0x3E,
    up = 0xC8,
    left = 0xCB,
    right = 0xCD,
    down = 0xD0,

    pub fn parse(text: []const u8) ?Key {
        return std.meta.stringToEnum(Key, text);
    }

    pub fn name(self: Key) []const u8 {
        return @tagName(self);
    }

    /// The index into the 256-byte `GetDeviceState` keyboard array.
    pub fn index(self: Key) usize {
        return @intFromEnum(self);
    }
};

/// A gamepad button, named as the game's own prompts name it.
///
/// The values are `XINPUT_GAMEPAD_*` bits. DirectInput surfaces an XInput
/// pad's buttons in the same order, and the runtime maps them when it fills
/// a `DIJOYSTATE2`; keeping the XInput bit as the value means the mapping is
/// one shift rather than a second table to keep in step.
pub const Pad = enum(u16) {
    dpad_up = 0x0001,
    dpad_down = 0x0002,
    dpad_left = 0x0004,
    dpad_right = 0x0008,
    start = 0x0010,
    back = 0x0020,
    lstick = 0x0040,
    rstick = 0x0080,
    lb = 0x0100,
    rb = 0x0200,
    a = 0x1000,
    b = 0x2000,
    x = 0x4000,
    y = 0x8000,

    pub fn parse(text: []const u8) ?Pad {
        return std.meta.stringToEnum(Pad, text);
    }

    pub fn name(self: Pad) []const u8 {
        return @tagName(self);
    }

    pub fn bit(self: Pad) u16 {
        return @intFromEnum(self);
    }
};

pub const Request = struct {
    inputs: [max_inputs]Input = undefined,
    input_len: u8 = 0,
    /// How many frames to hold the inputs down.
    hold: u16 = 2,

    pub fn all(self: *const Request) []const Input {
        return self.inputs[0..self.input_len];
    }

    pub const InitError = error{ NoInputs, TooManyInputs, BadHold };

    pub fn init(inputs: []const Input, hold: u16) InitError!Request {
        if (inputs.len == 0) return error.NoInputs;
        if (inputs.len > max_inputs) return error.TooManyInputs;
        if (hold == 0 or hold > max_hold) return error.BadHold;
        var r = Request{ .input_len = @intCast(inputs.len), .hold = hold };
        @memcpy(r.inputs[0..inputs.len], inputs);
        return r;
    }

    /// The request-file line: `<name>[+<name>...] <hold>`. Whitespace-
    /// trimmed; an empty or malformed file is no request.
    pub fn parse(text: []const u8) ?Request {
        var it = std.mem.tokenizeAny(u8, text, " \t\r\n");
        const chord = it.next() orelse return null;
        var inputs: [max_inputs]Input = undefined;
        var n: usize = 0;
        var parts = std.mem.splitScalar(u8, chord, '+');
        while (parts.next()) |part| {
            if (n == max_inputs) return null;
            inputs[n] = Input.parse(part) orelse return null;
            n += 1;
        }
        var hold: u16 = 2;
        if (it.next()) |h| hold = std.fmt.parseInt(u16, h, 10) catch return null;
        if (it.next() != null) return null;
        return init(inputs[0..n], hold) catch null;
    }

    /// The request-file line for `parse` (what the host writes).
    pub fn format(self: *const Request, buf: []u8) []const u8 {
        var w: usize = 0;
        for (self.all(), 0..) |in, i| {
            if (i > 0) {
                buf[w] = '+';
                w += 1;
            }
            if (in == .pad) {
                @memcpy(buf[w..][0.."pad:".len], "pad:");
                w += "pad:".len;
            }
            const nm = in.name();
            @memcpy(buf[w..][0..nm.len], nm);
            w += nm.len;
        }
        const tail = std.fmt.bufPrint(buf[w..], " {d}\n", .{self.hold}) catch unreachable;
        return buf[0 .. w + tail.len];
    }
};

/// Enough for the longest chord plus its hold count.
pub const line_buf_len = max_inputs * ("pad:".len + 16 + 1) + 8;

const testing = std.testing;

test "inputs parse from their command-line names" {
    try testing.expectEqual(Key.space, Input.parse("space").?.key);
    try testing.expectEqual(Key.escape, Input.parse("escape").?.key);
    try testing.expectEqual(Pad.a, Input.parse("pad:a").?.pad);
    try testing.expectEqual(Pad.start, Input.parse("pad:start").?.pad);
    try testing.expect(Input.parse("nosuchkey") == null);
    try testing.expect(Input.parse("pad:nosuchbutton") == null);
    try testing.expect(Input.parse("") == null);
}

test "key scan codes are DirectInput codes, not virtual-key codes" {
    // The distinction this enum exists for: VK_ESCAPE is 0x1B and VK_SPACE
    // is 0x20, but DIK_ESCAPE is 0x01 and DIK_SPACE is 0x39. A regression
    // here presses the wrong key and looks like a dead hook.
    try testing.expectEqual(@as(usize, 0x01), Key.escape.index());
    try testing.expectEqual(@as(usize, 0x39), Key.space.index());
    try testing.expectEqual(@as(usize, 0x1C), Key.@"return".index());
    try testing.expectEqual(@as(usize, 0x12), Key.e.index());
}

test "pad buttons carry their XInput bits" {
    try testing.expectEqual(@as(u16, 0x1000), Pad.a.bit());
    try testing.expectEqual(@as(u16, 0x0010), Pad.start.bit());
}

test "requests validate their inputs and hold" {
    const space = Input{ .key = .space };
    const r = try Request.init(&.{space}, 4);
    try testing.expectEqual(@as(usize, 1), r.all().len);
    try testing.expectEqual(@as(u16, 4), r.hold);
    try testing.expectError(error.NoInputs, Request.init(&.{}, 1));
    try testing.expectError(error.BadHold, Request.init(&.{space}, 0));
    try testing.expectError(error.BadHold, Request.init(&.{space}, max_hold + 1));
    try testing.expectError(error.TooManyInputs, Request.init(&(.{space} ** (max_inputs + 1)), 1));
}

test "the request file round-trips" {
    const r = try Request.init(&.{ .{ .key = .lshift }, .{ .pad = .a } }, 6);
    var buf: [line_buf_len]u8 = undefined;
    const line = r.format(&buf);
    try testing.expectEqualStrings("lshift+pad:a 6\n", line);
    const back = Request.parse(line).?;
    try testing.expectEqual(@as(usize, 2), back.all().len);
    try testing.expectEqual(Key.lshift, back.all()[0].key);
    try testing.expectEqual(Pad.a, back.all()[1].pad);
    try testing.expectEqual(@as(u16, 6), back.hold);
}

test "a bare input line holds for the default frame count" {
    const back = Request.parse("space\n").?;
    try testing.expectEqual(Key.space, back.all()[0].key);
    try testing.expectEqual(@as(u16, 2), back.hold);
}

test "malformed request lines are no request" {
    try testing.expect(Request.parse("") == null);
    try testing.expect(Request.parse("space 2 extra") == null);
    try testing.expect(Request.parse("space bogus") == null);
    try testing.expect(Request.parse("nosuchkey 2") == null);
    try testing.expect(Request.parse("space 0") == null);
    try testing.expect(Request.parse("a+b+c+d+e 1") == null);
}
