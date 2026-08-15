//! The engine services SDK modules call into.
//!
//! `Host` is an interface rather than a direct call into the runtime so the
//! SDK can be exercised on the host without a game: tests supply a capture
//! implementation, the injected runtime supplies the real one. Every effect
//! a mod can have on the world goes through here, which also makes the
//! blast radius of the sandbox easy to see — if it is not on this
//! interface, a mod cannot do it.

const std = @import("std");
const paramview = @import("../paramview.zig");
const perf = @import("../perf.zig");
const ui_backend = @import("../ui_backend.zig");
const param_writes = @import("../param_writes.zig");
const screen = @import("../screen.zig");

pub const Level = enum { info, warn, err };

/// How the `params` module reaches a live table by file name. Null when the
/// game has none (offline host, table not loaded, unsupported build).
pub const ParamLookup = *const fn (file: []const u8) ?paramview.Table;

/// How the `store` module reaches a mod's persisted bytes. `load` copies the
/// stored bytes for `mod_name` into `buf` and returns the filled slice, or
/// null when nothing is stored (or the store is unreadable). `save` writes
/// the whole store back; false means it did not land.
pub const StoreLoad = *const fn (mod_name: []const u8, buf: []u8) ?[]const u8;
pub const StoreSave = *const fn (mod_name: []const u8, bytes: []const u8) bool;

/// The most bytes one mod's store may hold. Settings, not save games.
pub const store_max_bytes = 64 * 1024;

/// How the `params` module reports a successful field write, so the host
/// can record who wrote what and warn on cross-mod conflicts.
pub const ParamWritten = *const fn (mod_name: []const u8, write: param_writes.Write) void;

/// How the `screen` module asks for a frame capture; the runtime queues it
/// for the next present. Returns whether it was accepted (false: capture is
/// unavailable on this host, or one is already pending).
pub const ScreenCapture = *const fn (mod_name: []const u8, request: screen.Request) bool;

pub const Host = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Write a log line attributed to `mod_name`.
        log: *const fn (ptr: *anyopaque, mod_name: []const u8, level: Level, msg: []const u8) void,
        /// The live PARAM table for a param file name, if the game has it.
        param_table: *const fn (ptr: *anyopaque, file: []const u8) ?paramview.Table,
        /// Frame/cost statistics, if the engine keeps them (null: `perf`
        /// reports zeros and no mods).
        perf: *const fn (ptr: *anyopaque) ?*perf.Stats,
        /// Persisted store bytes for a mod; see `StoreLoad` / `StoreSave`.
        store_load: *const fn (ptr: *anyopaque, mod_name: []const u8, buf: []u8) ?[]const u8,
        store_save: *const fn (ptr: *anyopaque, mod_name: []const u8, bytes: []const u8) bool,
        /// The overlay the `ui` module draws with, if this host has one.
        ui: *const fn (ptr: *anyopaque) ?ui_backend.Backend,
        /// A field write landed; see `ParamWritten`.
        param_written: *const fn (ptr: *anyopaque, mod_name: []const u8, write: param_writes.Write) void,
        /// Queue a frame capture; see `ScreenCapture`.
        screen_capture: *const fn (ptr: *anyopaque, mod_name: []const u8, request: screen.Request) bool,
    };

    pub fn log(self: Host, mod_name: []const u8, level: Level, msg: []const u8) void {
        self.vtable.log(self.ptr, mod_name, level, msg);
    }

    pub fn paramTable(self: Host, file: []const u8) ?paramview.Table {
        return self.vtable.param_table(self.ptr, file);
    }

    pub fn perfStats(self: Host) ?*perf.Stats {
        return self.vtable.perf(self.ptr);
    }

    pub fn storeLoad(self: Host, mod_name: []const u8, buf: []u8) ?[]const u8 {
        return self.vtable.store_load(self.ptr, mod_name, buf);
    }

    pub fn storeSave(self: Host, mod_name: []const u8, bytes: []const u8) bool {
        return self.vtable.store_save(self.ptr, mod_name, bytes);
    }

    pub fn uiBackend(self: Host) ?ui_backend.Backend {
        return self.vtable.ui(self.ptr);
    }

    pub fn paramWritten(self: Host, mod_name: []const u8, write: param_writes.Write) void {
        self.vtable.param_written(self.ptr, mod_name, write);
    }

    pub fn screenCapture(self: Host, mod_name: []const u8, request: screen.Request) bool {
        return self.vtable.screen_capture(self.ptr, mod_name, request);
    }
};

/// Host implementation that forwards each log line, formatted, to a single
/// sink function. The injected runtime uses this to route mod logs into its
/// own log file (the sink writes one line); anything with a
/// `fn ([]const u8) void` sink can reuse it. Formatting happens in a fixed
/// stack buffer, so it allocates nothing and is safe under the loader-lock
/// discipline the runtime keeps.
pub const CallbackHost = struct {
    sink: *const fn (line: []const u8) void,
    /// Live param lookup; null means `params` reports every file unavailable.
    params: ?ParamLookup = null,
    /// Frame/cost statistics the runtime keeps; null means `perf` is empty.
    perf: ?*perf.Stats = null,
    /// Store persistence; null means `store` never persists (get returns
    /// defaults, set is remembered for the process only).
    store_load: ?StoreLoad = null,
    store_save: ?StoreSave = null,
    /// The overlay; null means `ui` reports itself unavailable.
    ui: ?ui_backend.Backend = null,
    /// Write recording; null means writes are not tracked.
    param_written: ?ParamWritten = null,
    /// Frame capture; null means `screen.capture` reports unavailable.
    screen_capture: ?ScreenCapture = null,

    pub fn init(sink: *const fn (line: []const u8) void) CallbackHost {
        return .{ .sink = sink };
    }

    pub fn host(self: *CallbackHost) Host {
        return .{ .ptr = self, .vtable = &.{
            .log = logImpl,
            .param_table = paramTableImpl,
            .perf = perfImpl,
            .store_load = storeLoadImpl,
            .store_save = storeSaveImpl,
            .ui = uiImpl,
            .param_written = paramWrittenImpl,
            .screen_capture = screenCaptureImpl,
        } };
    }

    fn paramWrittenImpl(ptr: *anyopaque, mod_name: []const u8, write: param_writes.Write) void {
        const self: *CallbackHost = @ptrCast(@alignCast(ptr));
        const f = self.param_written orelse return;
        f(mod_name, write);
    }

    fn screenCaptureImpl(ptr: *anyopaque, mod_name: []const u8, request: screen.Request) bool {
        const self: *CallbackHost = @ptrCast(@alignCast(ptr));
        const f = self.screen_capture orelse return false;
        return f(mod_name, request);
    }

    fn perfImpl(ptr: *anyopaque) ?*perf.Stats {
        const self: *CallbackHost = @ptrCast(@alignCast(ptr));
        return self.perf;
    }

    fn uiImpl(ptr: *anyopaque) ?ui_backend.Backend {
        const self: *CallbackHost = @ptrCast(@alignCast(ptr));
        return self.ui;
    }

    fn storeLoadImpl(ptr: *anyopaque, mod_name: []const u8, buf: []u8) ?[]const u8 {
        const self: *CallbackHost = @ptrCast(@alignCast(ptr));
        const f = self.store_load orelse return null;
        return f(mod_name, buf);
    }

    fn storeSaveImpl(ptr: *anyopaque, mod_name: []const u8, bytes: []const u8) bool {
        const self: *CallbackHost = @ptrCast(@alignCast(ptr));
        const f = self.store_save orelse return false;
        return f(mod_name, bytes);
    }

    fn paramTableImpl(ptr: *anyopaque, file: []const u8) ?paramview.Table {
        const self: *CallbackHost = @ptrCast(@alignCast(ptr));
        const lookup = self.params orelse return null;
        return lookup(file);
    }

    fn logImpl(ptr: *anyopaque, mod_name: []const u8, level: Level, msg: []const u8) void {
        const self: *CallbackHost = @ptrCast(@alignCast(ptr));
        const tag = switch (level) {
            .info => "info",
            .warn => "warn",
            .err => "err",
        };
        var buf: [1024]u8 = undefined;
        // Best-effort: an over-long line is dropped rather than truncated to
        // something misleading. Logging must never break a mod.
        const line = std.fmt.bufPrint(&buf, "mod[{s}] {s}: {s}\n", .{ mod_name, tag, msg }) catch return;
        self.sink(line);
    }
};

/// Host implementation that records log lines in memory. Used by tests to
/// assert what a mod actually did.
pub const CaptureHost = struct {
    gpa: std.mem.Allocator,
    lines: std.ArrayList(Line) = .empty,
    /// Tests that exercise `params` install a lookup over a synthetic table.
    params: ?ParamLookup = null,
    /// Tests that exercise `perf` install stats fed by a fake clock.
    perf: ?*perf.Stats = null,
    /// Tests that exercise `ui` install a recording backend.
    ui: ?ui_backend.Backend = null,
    /// In-memory store: mod name → persisted bytes. What `store` wrote is
    /// readable back by tests, and survives a reload of the same mod.
    stores: std.StringHashMapUnmanaged([]u8) = .empty,
    /// Write recording, as the runtime keeps it; a conflict is logged as an
    /// "engine" warning line so tests can assert on it.
    writes: param_writes.Ledger = .{},
    /// Field writes reported, in order (for tests that check recording).
    write_count: usize = 0,
    /// Capture requests accepted, in order; `captures_available` false
    /// makes the host refuse them (as a runtime with no overlay would).
    captures: std.ArrayList(screen.Request) = .empty,
    captures_available: bool = true,

    pub const Line = struct {
        mod_name: []const u8,
        level: Level,
        msg: []const u8,
    };

    pub fn init(gpa: std.mem.Allocator) CaptureHost {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *CaptureHost) void {
        for (self.lines.items) |line| {
            self.gpa.free(line.mod_name);
            self.gpa.free(line.msg);
        }
        self.lines.deinit(self.gpa);
        var it = self.stores.iterator();
        while (it.next()) |e| {
            self.gpa.free(e.key_ptr.*);
            self.gpa.free(e.value_ptr.*);
        }
        self.stores.deinit(self.gpa);
        self.captures.deinit(self.gpa);
        self.* = undefined;
    }

    pub fn host(self: *CaptureHost) Host {
        return .{ .ptr = self, .vtable = &.{
            .log = logImpl,
            .param_table = paramTableImpl,
            .perf = perfImpl,
            .store_load = storeLoadImpl,
            .store_save = storeSaveImpl,
            .ui = uiImpl,
            .param_written = paramWrittenImpl,
            .screen_capture = screenCaptureImpl,
        } };
    }

    fn screenCaptureImpl(ptr: *anyopaque, mod_name: []const u8, request: screen.Request) bool {
        _ = mod_name;
        const self: *CaptureHost = @ptrCast(@alignCast(ptr));
        if (!self.captures_available) return false;
        self.captures.append(self.gpa, request) catch return false;
        return true;
    }

    fn paramWrittenImpl(ptr: *anyopaque, mod_name: []const u8, write: param_writes.Write) void {
        const self: *CaptureHost = @ptrCast(@alignCast(ptr));
        self.write_count += 1;
        const conflict = self.writes.record(mod_name, write) orelse return;
        var buf: [512]u8 = undefined;
        logImpl(ptr, "engine", .warn, param_writes.formatConflict(&buf, mod_name, write, conflict));
    }

    fn uiImpl(ptr: *anyopaque) ?ui_backend.Backend {
        const self: *CaptureHost = @ptrCast(@alignCast(ptr));
        return self.ui;
    }

    /// The bytes last saved for `mod_name`, if any.
    pub fn storedBytes(self: *const CaptureHost, mod_name: []const u8) ?[]const u8 {
        return self.stores.get(mod_name);
    }

    fn perfImpl(ptr: *anyopaque) ?*perf.Stats {
        const self: *CaptureHost = @ptrCast(@alignCast(ptr));
        return self.perf;
    }

    fn storeLoadImpl(ptr: *anyopaque, mod_name: []const u8, buf: []u8) ?[]const u8 {
        const self: *CaptureHost = @ptrCast(@alignCast(ptr));
        const bytes = self.stores.get(mod_name) orelse return null;
        if (bytes.len > buf.len) return null;
        @memcpy(buf[0..bytes.len], bytes);
        return buf[0..bytes.len];
    }

    fn storeSaveImpl(ptr: *anyopaque, mod_name: []const u8, bytes: []const u8) bool {
        const self: *CaptureHost = @ptrCast(@alignCast(ptr));
        const copy = self.gpa.dupe(u8, bytes) catch return false;
        if (self.stores.getPtr(mod_name)) |slot| {
            self.gpa.free(slot.*);
            slot.* = copy;
            return true;
        }
        const key = self.gpa.dupe(u8, mod_name) catch {
            self.gpa.free(copy);
            return false;
        };
        self.stores.put(self.gpa, key, copy) catch {
            self.gpa.free(key);
            self.gpa.free(copy);
            return false;
        };
        return true;
    }

    fn paramTableImpl(ptr: *anyopaque, file: []const u8) ?paramview.Table {
        const self: *CaptureHost = @ptrCast(@alignCast(ptr));
        const lookup = self.params orelse return null;
        return lookup(file);
    }

    fn logImpl(ptr: *anyopaque, mod_name: []const u8, level: Level, msg: []const u8) void {
        const self: *CaptureHost = @ptrCast(@alignCast(ptr));
        // Both slices borrow Lua-owned memory that is freed when the call
        // returns, so they must be copied to outlive it. A failed copy is
        // dropped rather than propagated: logging must never break a mod.
        const name_copy = self.gpa.dupe(u8, mod_name) catch return;
        errdefer self.gpa.free(name_copy);
        const msg_copy = self.gpa.dupe(u8, msg) catch {
            self.gpa.free(name_copy);
            return;
        };
        self.lines.append(self.gpa, .{
            .mod_name = name_copy,
            .level = level,
            .msg = msg_copy,
        }) catch {
            self.gpa.free(name_copy);
            self.gpa.free(msg_copy);
        };
    }

    /// True if any captured line contains `needle`.
    pub fn contains(self: *const CaptureHost, needle: []const u8) bool {
        for (self.lines.items) |line| {
            if (std.mem.indexOf(u8, line.msg, needle) != null) return true;
        }
        return false;
    }
};

const CallbackSink = struct {
    var buf: [4096]u8 = undefined;
    var len: usize = 0;
    fn reset() void {
        len = 0;
    }
    fn sink(line: []const u8) void {
        const n = @min(line.len, buf.len - len);
        @memcpy(buf[len .. len + n], line[0..n]);
        len += n;
    }
    fn text() []const u8 {
        return buf[0..len];
    }
};

test "callback host formats and forwards a line to its sink" {
    CallbackSink.reset();
    var ch = CallbackHost.init(CallbackSink.sink);
    const h = ch.host();
    h.log("rune-counter", .info, "gained 100 runes");
    h.log("overlay", .err, "boom");
    try std.testing.expect(std.mem.indexOf(u8, CallbackSink.text(), "mod[rune-counter] info: gained 100 runes\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, CallbackSink.text(), "mod[overlay] err: boom\n") != null);
}

test "capture host records lines" {
    var capture = CaptureHost.init(std.testing.allocator);
    defer capture.deinit();

    const h = capture.host();
    h.log("m", .info, "hello");

    try std.testing.expectEqual(@as(usize, 1), capture.lines.items.len);
    try std.testing.expectEqualStrings("m", capture.lines.items[0].mod_name);
    try std.testing.expect(capture.contains("hello"));
}
