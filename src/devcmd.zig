//! Mod-author tooling: `check`, `perf`, `stubs` and `img`.
//!
//! These run the very front end the game runs — the same loader, sandbox,
//! manifest rules, instruction budget and SDK modules, compiled for the host
//! — so "passes `check`" means "would load in-game", and `perf`'s numbers
//! come from the real dispatcher rather than an estimate.
//!
//!   ermod check <mod.lua>...              would each load in-game?
//!   ermod perf  <mod.lua> [--frames N] [--runes N] [--deaths N]
//!                                         [--regulation <regulation.bin>]
//!                                         cost per event under the real budget model
//!   ermod stubs [out.lua]                 LuaLS annotations for the SDK
//!   ermod img stat <png> [--rect x,y,w,h] measure a capture (mean colour, lit coverage)
//!   ermod img diff <a.png> <b.png>        how much changed between two captures
//!
//! `perf` starts the mod against a capture host and fires a synthetic
//! session; it is a pre-flight, not a promise, and says so. Without
//! `--regulation` there are no params, so a `params` mod fails at start
//! exactly as it would before the game's tables load; with one, `on_launch`
//! runs against the unpacked archive — `apply` without the pack — which
//! gives an honest cost for launch mods too.
//!
//! These lived in the engine repo as `ermod-dev` until the front end became
//! a package. `sigs` did not come with them: it needs the private signature
//! tables and stays there as `ermod-engine sigs`.

const std = @import("std");
const Io = std.Io;
const ermod_lua = @import("ermod_lua");
const sdk = ermod_lua.sdk;
const image = ermod_lua.image;
const crypto = @import("crypto.zig");
const dcx = @import("dcx.zig");
const bnd4 = @import("bnd4.zig");

fn arg(a: [*:0]const u8) []const u8 {
    return std.mem.sliceTo(a, 0);
}

fn readMod(gpa: std.mem.Allocator, io: Io, path: []const u8) ![]u8 {
    return Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(1 << 20));
}

fn baseName(path: []const u8) []const u8 {
    return std.fs.path.basename(path);
}

// ── check ───────────────────────────────────────────────────────────────

pub fn check(gpa: std.mem.Allocator, io: Io, out: *Io.Writer, files: []const [*:0]const u8) !bool {
    if (files.len == 0) {
        try out.writeAll("ermod check: no files given\n");
        return false;
    }
    var all_ok = true;
    for (files) |f| {
        const path = arg(f);
        if (!try checkOne(gpa, io, out, path)) all_ok = false;
    }
    return all_ok;
}

fn checkOne(gpa: std.mem.Allocator, io: Io, out: *Io.Writer, path: []const u8) !bool {
    const source = readMod(gpa, io, path) catch |e| {
        try out.print("{s}: FAIL cannot read ({s})\n", .{ path, @errorName(e) });
        return false;
    };
    defer gpa.free(source);
    var name_buf: [std.fs.max_name_bytes + 2]u8 = undefined;
    const chunk = std.fmt.bufPrintZ(&name_buf, "={s}", .{baseName(path)}) catch "=mod.lua";

    var capture = sdk.CaptureHost.init(gpa);
    defer capture.deinit();
    const m = sdk.load(gpa, source, chunk, capture.host()) catch |e| {
        try out.print("{s}: FAIL {s}\n", .{ path, describeLoadError(e) });
        return false;
    };
    defer sdk.destroy(m);

    try out.print("{s}: ok  name={s} run_at={s} entry={s} permissions=", .{
        path, m.name, @tagName(m.run_at), m.run_at.entryPoint(),
    });
    var first = true;
    var it = m.permissions.iterator();
    while (it.next()) |p| {
        try out.print("{s}{s}", .{ if (first) "" else ",", @tagName(p) });
        first = false;
    }
    if (first) try out.writeAll("(none)");
    try out.writeAll("\n");
    return true;
}

fn describeLoadError(e: anyerror) []const u8 {
    return switch (e) {
        error.SyntaxError => "syntax error",
        error.RuntimeError => "script errored while returning its mod table",
        error.BudgetExceeded => "script exceeded the instruction budget at load",
        error.NotAModTable => "script did not return a mod table",
        error.BadManifest => "manifest: missing or mistyped name/version/run_at",
        error.UnknownPermission => "manifest: unknown permission name",
        error.UnknownRunAt => "manifest: run_at must be \"launch\" or \"events\"",
        error.MissingEntryPoint => "manifest: entry point missing (on_launch for launch mods, setup for event mods)",
        else => @errorName(e),
    };
}

// ── stubs ───────────────────────────────────────────────────────────────

pub fn stubs(io: Io, out: *Io.Writer, rest: []const [*:0]const u8) !bool {
    if (rest.len == 0) {
        try out.writeAll(sdk.stubs.text);
        return true;
    }
    const path = arg(rest[0]);
    Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = sdk.stubs.text }) catch |e| {
        try out.print("ermod stubs: cannot write {s} ({s})\n", .{ path, @errorName(e) });
        return false;
    };
    try out.print("wrote {s} ({d} bytes)\n", .{ path, sdk.stubs.text.len });
    return true;
}

// ── perf ────────────────────────────────────────────────────────────────

var perf_io: Io = undefined;

fn hostClockNs() u64 {
    const t = Io.Timestamp.now(perf_io, .awake);
    return @intCast(@max(t.nanoseconds, 0));
}

const Trace = struct {
    frames: u64 = 600,
    runes: u64 = 10,
    deaths: u64 = 1,
};

/// The archive `--regulation` opened, for `perfParamLookup`. A `ParamLookup`
/// is a plain function pointer with no context word, so the one archive a
/// `perf` run uses lives here rather than being threaded through it.
var perf_archive: ?*bnd4.Archive = null;

/// `params` over an unpacked archive: the same mapping the offline host in
/// `apply` does, so a mod sees the same tables under `perf --regulation` as
/// it would when packed.
fn perfParamLookup(file: []const u8) ?ermod_lua.paramview.Table {
    const a = perf_archive orelse return null;
    // The SDK strips a trailing ".param"; BND4 entries carry it.
    var buf: [128]u8 = undefined;
    const name = std.fmt.bufPrint(&buf, "{s}.param", .{file}) catch return null;
    const f = a.find(name) orelse return null;
    if (f.data.len < ermod_lua.paramview.header_size) return null;
    return ermod_lua.paramview.Table.at(f.data.ptr);
}

pub fn perf(gpa: std.mem.Allocator, io: Io, out: *Io.Writer, rest: []const [*:0]const u8) !bool {
    if (rest.len == 0) {
        try out.writeAll("ermod perf: no file given\n");
        return false;
    }
    const path = arg(rest[0]);
    var trace: Trace = .{};
    var regulation: ?[]const u8 = null;
    var i: usize = 1;
    while (i < rest.len) : (i += 1) {
        const a = arg(rest[i]);
        const next: ?[]const u8 = if (i + 1 < rest.len) arg(rest[i + 1]) else null;
        const val: ?u64 = if (next) |n| std.fmt.parseInt(u64, n, 10) catch null else null;
        if (std.mem.eql(u8, a, "--frames") and val != null) {
            trace.frames = val.?;
            i += 1;
        } else if (std.mem.eql(u8, a, "--runes") and val != null) {
            trace.runes = val.?;
            i += 1;
        } else if (std.mem.eql(u8, a, "--deaths") and val != null) {
            trace.deaths = val.?;
            i += 1;
        } else if (std.mem.eql(u8, a, "--regulation") and next != null) {
            regulation = next.?;
            i += 1;
        } else {
            try out.print("ermod perf: bad argument '{s}'\n", .{a});
            return false;
        }
    }

    const source = readMod(gpa, io, path) catch |e| {
        try out.print("{s}: cannot read ({s})\n", .{ path, @errorName(e) });
        return false;
    };
    defer gpa.free(source);
    var name_buf: [std.fs.max_name_bytes + 2]u8 = undefined;
    const chunk = std.fmt.bufPrintZ(&name_buf, "={s}", .{baseName(path)}) catch "=mod.lua";

    perf_io = io;
    var stats = ermod_lua.perf.Stats.init(hostClockNs);
    var rec = ermod_lua.ui_backend.Recording.init(gpa);
    defer rec.deinit();
    rec.in_frame = true;

    var capture = sdk.CaptureHost.init(gpa);
    defer capture.deinit();
    capture.perf = &stats;
    capture.ui = rec.backend();

    // With `--regulation`, `params` reads the unpacked archive — `apply`
    // without the pack — so a launch mod's real work is timed instead of
    // failing at its first `params` call. The rest of the host stays the
    // capture one: `perf` measures event handlers, which need the recording
    // overlay and the stats the offline host deliberately withholds. The
    // archive is only ever read back from memory; `perf` writes no file.
    var archive: ?bnd4.Archive = if (regulation) |bin| openRegulation(gpa, io, bin) catch |e| {
        try out.print("ermod perf: cannot open {s} ({s})\n", .{ bin, @errorName(e) });
        return false;
    } else null;
    defer if (archive) |*a| a.deinit();
    if (archive) |*a| {
        perf_archive = a;
        capture.params = perfParamLookup;
    }

    const m = sdk.load(gpa, source, chunk, capture.host()) catch |e| {
        try out.print("{s}: FAIL {s}\n", .{ path, describeLoadError(e) });
        return false;
    };
    defer sdk.destroy(m);

    try out.print("{s}: {s} ({s} mod) — synthetic session: {d} frames, {d} rune pickups, {d} deaths\n", .{
        path, m.name, @tagName(m.run_at), trace.frames, trace.runes, trace.deaths,
    });
    if (regulation) |bin| {
        try out.print(
            "host pre-flight: params from {s} (unpacked, never written back), recording overlay, in-memory store\n\n",
            .{bin},
        );
    } else {
        try out.writeAll("host pre-flight: no live params (params calls fail as they do before the tables load), recording overlay, in-memory store\n\n");
    }

    const t_start = hostClockNs();
    m.start() catch {
        try out.writeAll("start: FAIL — entry point errored (logged under the mod's name below)\n");
        try flushLog(out, &capture, 0);
        return false;
    };
    const start_ns = hostClockNs() -| t_start;
    try out.print("start ({s}): {d:.3} ms\n", .{ m.run_at.entryPoint(), nsToMs(start_ns) });
    if (archive != null) {
        try out.print("start wrote {d} param field(s) (into memory; nothing is packed)\n", .{capture.write_count});
    }

    const events = [_]sdk.Event{ .on_present, .on_rune_gain, .on_death };
    var per = [_]EventCost{.{}} ** events.len;
    const handlers = [_]usize{
        m.ctx.hooks.count(.on_present), m.ctx.hooks.count(.on_rune_gain), m.ctx.hooks.count(.on_death),
    };

    var log_seen: usize = capture.lines.items.len;
    var frame: u64 = 0;
    while (frame < trace.frames and m.isActive()) : (frame += 1) {
        stats.frameNow();
        if (trace.runes > 0 and frame % @max(trace.frames / trace.runes, 1) == 0 and per[1].fires < trace.runes) {
            timed(m, &per[1], .on_rune_gain, .{ .rune_gain = .{ .amount = 100 } });
        }
        if (trace.deaths > 0 and frame % @max(trace.frames / trace.deaths, 1) == trace.frames / trace.deaths / 2 and per[2].fires < trace.deaths) {
            timed(m, &per[2], .on_death, .none);
        }
        timed(m, &per[0], .on_present, .none);
        // Surface log lines as the session goes so a spammy handler is obvious.
        if (capture.lines.items.len > log_seen + 20) {
            try flushLog(out, &capture, log_seen);
            log_seen = capture.lines.items.len;
        }
    }
    try flushLog(out, &capture, log_seen);

    try out.writeAll("\nevent          handlers   fires   total ms    avg/fire ms   max/fire ms\n");
    for (events, 0..) |ev, k| {
        const p = per[k];
        try out.print("{s:<14} {d:>8} {d:>7} {d:>10.3} {d:>13.4} {d:>13.4}\n", .{
            @tagName(ev),                                          handlers[k],      p.fires, nsToMs(p.total_ns),
            if (p.fires == 0) 0 else nsToMs(p.total_ns / p.fires), nsToMs(p.max_ns),
        });
    }
    const budget_frac = if (per[0].fires == 0) 0 else nsToMs(per[0].max_ns) / (1000.0 / 60.0) * 100.0;
    try out.print("\nworst on_present frame cost {d:.4} ms = {d:.2}% of a 60 fps frame\n", .{ nsToMs(per[0].max_ns), budget_frac });
    try out.print("strikes {d}/{d}; {s}\n", .{
        m.strikes,                                                                                                 sdk.ModInstance.max_strikes,
        if (m.isActive()) "mod still active at end of session" else "MOD DISABLED during session (see log above)",
    });
    return m.isActive();
}

const EventCost = struct {
    fires: u64 = 0,
    total_ns: u64 = 0,
    max_ns: u64 = 0,
};

fn timed(m: *sdk.ModInstance, cost: *EventCost, ev: sdk.Event, payload: sdk.ModInstance.Payload) void {
    const t0 = hostClockNs();
    m.fire(ev, payload);
    const dt = hostClockNs() -| t0;
    cost.fires += 1;
    cost.total_ns += dt;
    if (dt > cost.max_ns) cost.max_ns = dt;
}

fn flushLog(out: *Io.Writer, capture: *const sdk.CaptureHost, from: usize) !void {
    for (capture.lines.items[from..]) |l| {
        try out.print("  log[{s}] {s}: {s}\n", .{ l.mod_name, @tagName(l.level), l.msg });
    }
}

fn nsToMs(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / 1e6;
}

fn openRegulation(gpa: std.mem.Allocator, io: Io, path: []const u8) !bnd4.Archive {
    const raw = try Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(512 << 20));
    defer gpa.free(raw);
    const plain = try crypto.decrypt(gpa, crypto.er_regulation_key, raw);
    defer gpa.free(plain);
    const bnd = try dcx.unpack(gpa, plain);
    defer gpa.free(bnd);
    return bnd4.read(gpa, bnd);
}

// ── img ─────────────────────────────────────────────────────────────────
// Reading frame captures without eyes: `sdk.screen.capture` / `ermod-engine
// shot` produce a PNG; these turn it into numbers a check can assert on.
// "Did the overlay draw?" is `img stat --rect` over the window's area
// showing lit coverage above the background's; "did anything change
// between two frames?" is `img diff`.

pub fn img(gpa: std.mem.Allocator, io: Io, out: *Io.Writer, rest: []const [*:0]const u8) !bool {
    if (rest.len == 0) {
        try out.writeAll("ermod img: stat <png> [--rect x,y,w,h] | diff <a.png> <b.png> [--threshold N] [--rect x,y,w,h]\n");
        return false;
    }
    const sub = arg(rest[0]);
    if (std.mem.eql(u8, sub, "stat")) return imgStat(gpa, io, out, rest[1..]);
    if (std.mem.eql(u8, sub, "diff")) return imgDiff(gpa, io, out, rest[1..]);
    try out.print("ermod img: unknown subcommand '{s}'\n", .{sub});
    return false;
}

fn loadPng(gpa: std.mem.Allocator, io: Io, out: *Io.Writer, path: []const u8) !?image.Image {
    const bytes = Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(256 << 20)) catch |e| {
        try out.print("{s}: cannot read ({s})\n", .{ path, @errorName(e) });
        return null;
    };
    defer gpa.free(bytes);
    return image.decodePng(gpa, bytes) catch |e| {
        try out.print("{s}: not a decodable PNG ({s}; 8-bit RGB/RGBA non-interlaced only)\n", .{ path, @errorName(e) });
        return null;
    };
}

fn optValue(rest: []const [*:0]const u8, flag: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i + 1 < rest.len) : (i += 1) {
        if (std.mem.eql(u8, arg(rest[i]), flag)) return arg(rest[i + 1]);
    }
    return null;
}

fn imgStat(gpa: std.mem.Allocator, io: Io, out: *Io.Writer, rest: []const [*:0]const u8) !bool {
    if (rest.len == 0) {
        try out.writeAll("ermod img stat: no file given\n");
        return false;
    }
    const path = arg(rest[0]);
    var region: ?image.Rect = null;
    if (optValue(rest, "--rect")) |r| {
        region = image.Rect.parse(r) orelse {
            try out.print("img stat: --rect wants x,y,w,h, got {s}\n", .{r});
            return false;
        };
    }
    var im = (try loadPng(gpa, io, out, path)) orelse return false;
    defer im.deinit(gpa);
    const st = image.stats(im, region);
    try out.print("{s}: {d}x{d}\n", .{ path, im.width, im.height });
    try out.print("region      x={d} y={d} w={d} h={d}\n", .{ st.rect.x, st.rect.y, st.rect.w, st.rect.h });
    try out.print("mean rgb    {d:.1} {d:.1} {d:.1}\n", .{ st.mean[0], st.mean[1], st.mean[2] });
    try out.print("lit         {d:.1}% of pixels brighter than {d}/255\n", .{ st.lit_fraction * 100, image.Stats.dark_threshold });
    try out.print("distinct    {d} colours (4 bits/channel)\n", .{st.distinct});
    try out.print("brightest   {d} {d} {d}\n", .{ st.brightest[0], st.brightest[1], st.brightest[2] });
    return true;
}

fn imgDiff(gpa: std.mem.Allocator, io: Io, out: *Io.Writer, rest: []const [*:0]const u8) !bool {
    if (rest.len < 2) {
        try out.writeAll("ermod img diff: two files needed\n");
        return false;
    }
    var threshold: u8 = 12;
    if (optValue(rest, "--threshold")) |t| {
        threshold = std.fmt.parseInt(u8, t, 10) catch {
            try out.print("img diff: --threshold wants 0..255, got {s}\n", .{t});
            return false;
        };
    }
    var region: ?image.Rect = null;
    if (optValue(rest, "--rect")) |r| {
        region = image.Rect.parse(r) orelse {
            try out.print("img diff: --rect wants x,y,w,h, got {s}\n", .{r});
            return false;
        };
    }
    var a = (try loadPng(gpa, io, out, arg(rest[0]))) orelse return false;
    defer a.deinit(gpa);
    var b = (try loadPng(gpa, io, out, arg(rest[1]))) orelse return false;
    defer b.deinit(gpa);
    if (region) |r| {
        // Compare the region only; the bbox below is then region-relative.
        const ca = try image.crop(gpa, a, r);
        a.deinit(gpa);
        a = ca;
        const cb = try image.crop(gpa, b, r);
        b.deinit(gpa);
        b = cb;
    }
    const d = image.diff(a, b, threshold) catch {
        try out.print("img diff: sizes differ ({d}x{d} vs {d}x{d})\n", .{ a.width, a.height, b.width, b.height });
        return false;
    };
    try out.print("{s} vs {s}: {d}x{d}{s}, threshold {d}\n", .{ arg(rest[0]), arg(rest[1]), a.width, a.height, if (region != null) " (region)" else "", threshold });
    try out.print("changed     {d} of {d} pixels ({d:.2}%)\n", .{ d.changed, d.total, d.fraction() * 100 });
    try out.print("bbox        x={d} y={d} w={d} h={d}\n", .{ d.bbox.x, d.bbox.y, d.bbox.w, d.bbox.h });
    return d.changed > 0;
}
