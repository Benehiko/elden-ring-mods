//! Frame timing and per-mod script cost — the data source for the `perf`
//! SDK module.
//!
//! Pure over its inputs: the present hook pushes one `frame(now)` per
//! presented frame, the dispatcher records each handler call's duration
//! against the mod that ran it. Both come from a clock the owner supplies
//! (`clock`), so on the host tests drive it with synthetic timestamps and
//! in the injected runtime it is `QueryPerformanceCounter` in nanoseconds.
//! Nothing here allocates or does I/O; it runs inside the game's frame.
//!
//! Every loaded mod registers a `ModCost` slot at load time; the `perf`
//! module reports all of them, not just the caller's, because a
//! performance monitor exists to show which mod is eating the frame.

const std = @import("std");

/// A monotonic clock in nanoseconds.
pub const Clock = *const fn () u64;

/// How many recent frame intervals `fps()` averages over. Two seconds at
/// 60 Hz; short enough to react, long enough not to flicker.
pub const ring_len = 120;

/// The most mods the runtime tracks cost for. A mod past this limit still
/// runs, it just reports no cost.
pub const max_mods = 64;

pub const ModCost = struct {
    /// Borrowed from the mod instance, which outlives the stats.
    name: []const u8 = "",
    used: bool = false,
    /// Duration of the most recent handler call, ns.
    last_ns: u64 = 0,
    /// Exponential moving average of handler duration, ns (alpha 1/16).
    avg_ns: u64 = 0,
    /// Handler calls recorded.
    calls: u64 = 0,
    /// Sum of all recorded durations, ns.
    total_ns: u64 = 0,

    pub fn record(self: *ModCost, elapsed_ns: u64) void {
        self.last_ns = elapsed_ns;
        self.calls += 1;
        self.total_ns += elapsed_ns;
        // EMA with alpha = 1/16, seeded by the first sample so a single call
        // is reported at face value rather than diluted towards zero.
        self.avg_ns = if (self.calls == 1) elapsed_ns else self.avg_ns - self.avg_ns / 16 + elapsed_ns / 16;
    }
};

pub const Stats = struct {
    clock: Clock,
    /// Frames presented since the hook went live.
    frames: u64 = 0,
    /// Timestamp of the previous frame, or null before the first.
    last_frame_ns: ?u64 = null,
    /// Ring of the most recent frame intervals, ns.
    ring: [ring_len]u64 = [_]u64{0} ** ring_len,
    ring_count: usize = 0,
    ring_pos: usize = 0,
    /// Interval between the last two frames, ns.
    last_interval_ns: u64 = 0,
    mods: [max_mods]ModCost = [_]ModCost{.{}} ** max_mods,

    pub fn init(clock: Clock) Stats {
        return .{ .clock = clock };
    }

    /// Record a presented frame at `now_ns`.
    pub fn frame(self: *Stats, now_ns: u64) void {
        self.frames += 1;
        if (self.last_frame_ns) |prev| {
            const dt = now_ns -| prev;
            self.last_interval_ns = dt;
            self.ring[self.ring_pos] = dt;
            self.ring_pos = (self.ring_pos + 1) % ring_len;
            if (self.ring_count < ring_len) self.ring_count += 1;
        }
        self.last_frame_ns = now_ns;
    }

    /// Record a frame at the clock's current time.
    pub fn frameNow(self: *Stats) void {
        self.frame(self.clock());
    }

    /// Last frame interval, ms.
    pub fn frameMs(self: *const Stats) f64 {
        return @as(f64, @floatFromInt(self.last_interval_ns)) / std.time.ns_per_ms;
    }

    /// Frames per second averaged over the ring. Zero before two frames.
    pub fn fps(self: *const Stats) f64 {
        if (self.ring_count == 0) return 0;
        var sum: u64 = 0;
        for (self.ring[0..self.ring_count]) |dt| sum += dt;
        if (sum == 0) return 0;
        return @as(f64, @floatFromInt(self.ring_count)) * std.time.ns_per_s / @as(f64, @floatFromInt(sum));
    }

    /// Claim a cost slot for `name`. Null when all slots are taken.
    pub fn register(self: *Stats, name: []const u8) ?*ModCost {
        for (&self.mods) |*m| {
            if (m.used) continue;
            m.* = .{ .name = name, .used = true };
            return m;
        }
        return null;
    }

    /// Release a slot claimed by `register` (mod unloaded).
    pub fn unregister(self: *Stats, cost: *ModCost) void {
        _ = self;
        cost.* = .{};
    }

    /// The registered mods, in slot order (unused slots skipped by the
    /// caller via `used`).
    pub fn modSlots(self: *const Stats) []const ModCost {
        return &self.mods;
    }
};

// ── tests ───────────────────────────────────────────────────────────────

const testing = std.testing;

const FakeClock = struct {
    var now: u64 = 0;
    fn read() u64 {
        return now;
    }
};

test "frame timing: interval, fps and count" {
    var s = Stats.init(FakeClock.read);
    try testing.expectEqual(@as(f64, 0), s.fps());
    var t: u64 = 1_000_000_000;
    // Four frames at exactly 60 Hz.
    for (0..4) |_| {
        s.frame(t);
        t += 16_666_667;
    }
    try testing.expectEqual(@as(u64, 4), s.frames);
    try testing.expectApproxEqAbs(@as(f64, 16.666667), s.frameMs(), 0.001);
    try testing.expectApproxEqAbs(@as(f64, 60.0), s.fps(), 0.01);
}

test "fps averages over the ring only" {
    var s = Stats.init(FakeClock.read);
    var t: u64 = 0;
    // A long stretch of slow frames, then more than a full ring of fast ones:
    // the slow ones must have aged out.
    for (0..10) |_| {
        s.frame(t);
        t += 100_000_000; // 10 fps
    }
    for (0..ring_len + 1) |_| {
        s.frame(t);
        t += 10_000_000; // 100 fps
    }
    try testing.expectApproxEqAbs(@as(f64, 100.0), s.fps(), 0.01);
    try testing.expectEqual(@as(usize, ring_len), s.ring_count);
}

test "frameNow reads the clock" {
    FakeClock.now = 5_000_000;
    var s = Stats.init(FakeClock.read);
    s.frameNow();
    FakeClock.now = 9_000_000;
    s.frameNow();
    try testing.expectApproxEqAbs(@as(f64, 4.0), s.frameMs(), 0.0001);
}

test "mod cost: last, average, calls, register/unregister" {
    var s = Stats.init(FakeClock.read);
    const a = s.register("a").?;
    const b = s.register("b").?;
    try testing.expect(a != b);
    a.record(1_000_000);
    try testing.expectEqual(@as(u64, 1_000_000), a.avg_ns); // seeded by first sample
    a.record(3_000_000);
    try testing.expectEqual(@as(u64, 3_000_000), a.last_ns);
    try testing.expectEqual(@as(u64, 2), a.calls);
    try testing.expectEqual(@as(u64, 4_000_000), a.total_ns);
    try testing.expect(a.avg_ns > 1_000_000 and a.avg_ns < 3_000_000);
    try testing.expectEqual(@as(u64, 0), b.calls);

    s.unregister(a);
    try testing.expect(!a.used);
    // The freed slot is reused.
    const c = s.register("c").?;
    try testing.expect(c == a);
    try testing.expectEqualStrings("c", c.name);
}

test "register returns null once every slot is taken" {
    var s = Stats.init(FakeClock.read);
    for (0..max_mods) |_| try testing.expect(s.register("m") != null);
    try testing.expect(s.register("one too many") == null);
}
