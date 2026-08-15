//! The on-disk format of a mod's `store`: a line-per-key text file the
//! engine owns. Pure — parsing and writing work on slices, no allocation,
//! no I/O — so it is host-tested exhaustively and the `store` module only
//! has to glue it to a Lua table.
//!
//! ```
//! # ermod store v1
//! volume = 0.5
//! name = "Ash"
//! enabled = true
//! ```
//!
//! Keys are `[A-Za-z0-9_.-]+`. Values are Lua literals restricted to
//! integers, floats, `true`/`false`, and double-quoted strings with the
//! escapes `\"`, `\\`, `\n`, `\t`, `\r`. Blank lines and `#` comments are
//! skipped. A malformed line is an error the caller reports once and then
//! treats the file as empty — a corrupt store must never take a mod down.

const std = @import("std");

pub const header = "# ermod store v1";

pub const Value = union(enum) {
    integer: i64,
    number: f64,
    boolean: bool,
    /// Escaped as it appears in the file; see `unescape`.
    string: []const u8,
};

pub const Entry = struct {
    key: []const u8,
    value: Value,
};

pub const Error = error{
    BadKey,
    BadValue,
    MissingEquals,
    UnterminatedString,
    BadEscape,
    BufferTooSmall,
};

pub fn isKeyChar(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '.' or ch == '-';
}

pub fn isValidKey(key: []const u8) bool {
    if (key.len == 0 or key.len > 128) return false;
    for (key) |ch| {
        if (!isKeyChar(ch)) return false;
    }
    return true;
}

/// Iterates the entries of a store file. `next` returns null at end.
pub const Parser = struct {
    rest: []const u8,

    pub fn init(bytes: []const u8) Parser {
        return .{ .rest = bytes };
    }

    pub fn next(self: *Parser) Error!?Entry {
        while (self.rest.len > 0) {
            const nl = std.mem.indexOfScalar(u8, self.rest, '\n');
            var line = if (nl) |i| self.rest[0..i] else self.rest;
            self.rest = if (nl) |i| self.rest[i + 1 ..] else self.rest[self.rest.len..];
            line = std.mem.trim(u8, line, " \t\r");
            if (line.len == 0 or line[0] == '#') continue;
            return try parseLine(line);
        }
        return null;
    }
};

fn parseLine(line: []const u8) Error!Entry {
    const eq = std.mem.indexOfScalar(u8, line, '=') orelse return error.MissingEquals;
    const key = std.mem.trim(u8, line[0..eq], " \t");
    if (!isValidKey(key)) return error.BadKey;
    const raw = std.mem.trim(u8, line[eq + 1 ..], " \t");
    return .{ .key = key, .value = try parseValue(raw) };
}

fn parseValue(raw: []const u8) Error!Value {
    if (raw.len == 0) return error.BadValue;
    if (std.mem.eql(u8, raw, "true")) return .{ .boolean = true };
    if (std.mem.eql(u8, raw, "false")) return .{ .boolean = false };
    if (raw[0] == '"') {
        if (raw.len < 2 or raw[raw.len - 1] != '"') return error.UnterminatedString;
        const body = raw[1 .. raw.len - 1];
        // Validate escapes now so a bad line is rejected at parse time; the
        // trailing quote must not itself be escaped.
        var i: usize = 0;
        while (i < body.len) : (i += 1) {
            if (body[i] == '"') return error.UnterminatedString;
            if (body[i] != '\\') continue;
            i += 1;
            if (i >= body.len) return error.UnterminatedString;
            switch (body[i]) {
                '"', '\\', 'n', 't', 'r' => {},
                else => return error.BadEscape,
            }
        }
        return .{ .string = body };
    }
    if (std.fmt.parseInt(i64, raw, 10)) |n| return .{ .integer = n } else |_| {}
    if (std.fmt.parseFloat(f64, raw)) |f| {
        if (std.math.isFinite(f)) return .{ .number = f };
    } else |_| {}
    return error.BadValue;
}

/// Decode an escaped string body (as returned in `Value.string`) into
/// `out`. Returns the decoded slice.
pub fn unescape(body: []const u8, out: []u8) Error![]const u8 {
    var n: usize = 0;
    var i: usize = 0;
    while (i < body.len) : (i += 1) {
        var ch = body[i];
        if (ch == '\\') {
            i += 1;
            if (i >= body.len) return error.UnterminatedString;
            ch = switch (body[i]) {
                '"' => '"',
                '\\' => '\\',
                'n' => '\n',
                't' => '\t',
                'r' => '\r',
                else => return error.BadEscape,
            };
        }
        if (n >= out.len) return error.BufferTooSmall;
        out[n] = ch;
        n += 1;
    }
    return out[0..n];
}

/// Appends entries to a fixed buffer, in the order given, after the header.
pub const Writer = struct {
    w: std.Io.Writer,

    pub fn init(buf: []u8) Error!Writer {
        var self = Writer{ .w = std.Io.Writer.fixed(buf) };
        self.w.writeAll(header ++ "\n") catch return error.BufferTooSmall;
        return self;
    }

    pub fn entry(self: *Writer, key: []const u8, value: Value) Error!void {
        if (!isValidKey(key)) return error.BadKey;
        self.write(key, value) catch return error.BufferTooSmall;
    }

    fn write(self: *Writer, key: []const u8, value: Value) !void {
        try self.w.writeAll(key);
        try self.w.writeAll(" = ");
        switch (value) {
            .integer => |n| try self.w.print("{d}", .{n}),
            // {d} on a float prints the shortest round-tripping decimal
            // form; a whole float still gets a fraction so it reads back as
            // a float, not an integer.
            .number => |f| {
                if (!std.math.isFinite(f)) return error.BadValue;
                if (f == @trunc(f) and @abs(f) < 1e15) {
                    try self.w.print("{d}.0", .{@as(i64, @intFromFloat(f))});
                } else {
                    try self.w.print("{d}", .{f});
                }
            },
            .boolean => |b| try self.w.writeAll(if (b) "true" else "false"),
            .string => |s| {
                try self.w.writeByte('"');
                for (s) |ch| {
                    switch (ch) {
                        '"' => try self.w.writeAll("\\\""),
                        '\\' => try self.w.writeAll("\\\\"),
                        '\n' => try self.w.writeAll("\\n"),
                        '\t' => try self.w.writeAll("\\t"),
                        '\r' => try self.w.writeAll("\\r"),
                        else => try self.w.writeByte(ch),
                    }
                }
                try self.w.writeByte('"');
            },
        }
        try self.w.writeByte('\n');
    }

    /// The bytes written so far.
    pub fn bytes(self: *const Writer) []const u8 {
        return self.w.buffered();
    }
};

// ── tests ───────────────────────────────────────────────────────────────

const testing = std.testing;

test "round-trips every value kind" {
    var buf: [512]u8 = undefined;
    var w = try Writer.init(&buf);
    try w.entry("volume", .{ .number = 0.5 });
    try w.entry("count", .{ .integer = -42 });
    try w.entry("whole", .{ .number = 3.0 });
    try w.entry("enabled", .{ .boolean = true });
    try w.entry("off", .{ .boolean = false });
    try w.entry("name", .{ .string = "Ash \"the\" one\\\n\ttab" });
    try w.entry("empty", .{ .string = "" });
    const out = w.bytes();
    try testing.expect(std.mem.startsWith(u8, out, header ++ "\n"));
    try testing.expect(std.mem.indexOf(u8, out, "whole = 3.0\n") != null);
    try testing.expect(std.mem.indexOf(u8, out, "count = -42\n") != null);

    var p = Parser.init(out);
    const e1 = (try p.next()).?;
    try testing.expectEqualStrings("volume", e1.key);
    try testing.expectEqual(@as(f64, 0.5), e1.value.number);
    const e2 = (try p.next()).?;
    try testing.expectEqual(@as(i64, -42), e2.value.integer);
    const e3 = (try p.next()).?;
    try testing.expectEqual(@as(f64, 3.0), e3.value.number);
    try testing.expect(e3.value == .number);
    try testing.expectEqual(true, (try p.next()).?.value.boolean);
    try testing.expectEqual(false, (try p.next()).?.value.boolean);
    const e6 = (try p.next()).?;
    var sbuf: [64]u8 = undefined;
    try testing.expectEqualStrings("Ash \"the\" one\\\n\ttab", try unescape(e6.value.string, &sbuf));
    const e7 = (try p.next()).?;
    try testing.expectEqualStrings("", try unescape(e7.value.string, &sbuf));
    try testing.expect((try p.next()) == null);
}

test "skips blank lines and comments, trims whitespace" {
    const text = "# ermod store v1\n\n   # a comment\r\n  a =  1 \r\n\nb=\"x\"\n";
    var p = Parser.init(text);
    const a = (try p.next()).?;
    try testing.expectEqualStrings("a", a.key);
    try testing.expectEqual(@as(i64, 1), a.value.integer);
    const b = (try p.next()).?;
    try testing.expectEqualStrings("b", b.key);
    try testing.expectEqualStrings("x", b.value.string);
    try testing.expect((try p.next()) == null);
}

test "rejects malformed lines" {
    const cases = [_]struct { line: []const u8, err: Error }{
        .{ .line = "novalue", .err = error.MissingEquals },
        .{ .line = "bad key = 1", .err = error.BadKey },
        .{ .line = "k = ", .err = error.BadValue },
        .{ .line = "k = maybe", .err = error.BadValue },
        .{ .line = "k = \"open", .err = error.UnterminatedString },
        .{ .line = "k = \"a\"b\"", .err = error.UnterminatedString },
        .{ .line = "k = \"\\q\"", .err = error.BadEscape },
        .{ .line = "k = nan", .err = error.BadValue },
    };
    for (cases) |cse| {
        var p = Parser.init(cse.line);
        try testing.expectError(cse.err, p.next());
    }
}

test "writer refuses bad keys and overflow" {
    var buf: [40]u8 = undefined;
    var w = try Writer.init(&buf);
    try testing.expectError(error.BadKey, w.entry("has space", .{ .integer = 1 }));
    try testing.expectError(error.BadKey, w.entry("", .{ .integer = 1 }));
    try w.entry("ok", .{ .integer = 1 });
    try testing.expectError(error.BufferTooSmall, w.entry("this_one_does_not_fit", .{ .string = "xxxxxxxxxxxxxxxx" }));
}

test "unescape reports a short buffer" {
    var small: [2]u8 = undefined;
    try testing.expectError(error.BufferTooSmall, unescape("abc", &small));
}
