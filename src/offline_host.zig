//! The `Host` a Lua mod runs against offline, inside `ermod apply`.
//!
//! The live runtime implements `Host.param_table` by walking the game's
//! `SoloParamRepository`; here it is an unpacked `regulation.bin`. Both hand
//! back the same `paramview.Table` over the same on-disk PARAM layout, so
//! `sdk.params.row(...).soulLv = 60` writes the same bytes at the same offset
//! in both — the one code path behind "author live, ship offline".
//!
//! Everything else on the vtable is unavailable, and says so: there is no
//! frame to draw an overlay on, no session to measure, no game to persist a
//! store for. A mod that needs those is an event mod, and `apply` refuses
//! event mods before it gets here.
//!
//! The write ledger is shared with the Zig `spec` pipeline and read back by
//! `apply` after every mod has run. Its policy differs from the live one: in
//! the game a later write wins and the conflict is a warning (a hot-reloaded
//! mod rewrites its own fields by design), while offline a cross-mod write to
//! one field refuses to pack. The file a player installs must not depend on
//! the order two mods happened to be listed in.

const std = @import("std");
const bnd4 = @import("bnd4.zig");
const ermod_lua = @import("ermod_lua");
const paramview = ermod_lua.paramview;
const param_writes = ermod_lua.param_writes;
const host_mod = ermod_lua.host;
const perf = ermod_lua.perf;
const ui_backend = ermod_lua.ui_backend;
const screen = ermod_lua.screen;

/// The first cross-mod conflict seen, kept whole (both names, the field) so
/// `apply` can report it after the run rather than mid-write.
pub const Conflict = struct {
    /// Copies, not borrows: the mods that wrote are destroyed before the
    /// report is printed.
    winner: [param_writes.name_cap]u8 = undefined,
    winner_len: u8 = 0,
    previous: [param_writes.name_cap]u8 = undefined,
    previous_len: u8 = 0,
    def_name: [64]u8 = undefined,
    def_name_len: u8 = 0,
    field: [64]u8 = undefined,
    field_len: u8 = 0,
    row: u32 = 0,

    pub fn winnerName(self: *const Conflict) []const u8 {
        return self.winner[0..self.winner_len];
    }
    pub fn previousName(self: *const Conflict) []const u8 {
        return self.previous[0..self.previous_len];
    }
    pub fn defName(self: *const Conflict) []const u8 {
        return self.def_name[0..self.def_name_len];
    }
    pub fn fieldName(self: *const Conflict) []const u8 {
        return self.field[0..self.field_len];
    }

    fn copyInto(dst: []u8, len: *u8, src: []const u8) void {
        const n: u8 = @intCast(@min(src.len, dst.len));
        @memcpy(dst[0..n], src[0..n]);
        len.* = n;
    }
};

pub const OfflineHost = struct {
    archive: *bnd4.Archive,
    /// Where mod log lines go; `apply` passes stdout.
    out: *std.Io.Writer,
    /// Shared with the Zig `spec` pipeline, so a Zig patch and a Lua write on
    /// one field collide as surely as two Lua mods do.
    ledger: param_writes.Ledger = .{},
    /// Field writes that landed, across all mods (reported by `apply`).
    writes: usize = 0,
    /// Set on the first cross-mod conflict; `apply` refuses to pack if so.
    conflict: ?Conflict = null,
    conflicts: usize = 0,
    pub fn init(archive: *bnd4.Archive, out: *std.Io.Writer) OfflineHost {
        return .{ .archive = archive, .out = out };
    }

    pub fn host(self: *OfflineHost) host_mod.Host {
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

    /// Record a write made outside the SDK (the Zig `spec` pipeline), so one
    /// ledger covers both kinds of mod.
    pub fn recordWrite(self: *OfflineHost, mod_name: []const u8, write: param_writes.Write) void {
        paramWrittenImpl(self, mod_name, write);
    }

    /// The live table's identity for a param file, so a Zig patch and a Lua
    /// write on the same file produce the same ledger key. Null if the
    /// archive has no such entry.
    ///
    /// The identity is the entry's buffer address, matching what the SDK
    /// records for a Lua write. `modspec.apply` replaces an entry's buffer
    /// (`setData`) when it writes a param back, so this must be read *after*
    /// the Zig pipeline has settled — which is why `apply` runs the specs
    /// first and the Lua mods second.
    pub fn tableIdentity(self: *OfflineHost, param_file: []const u8) ?usize {
        const f = self.archive.find(param_file) orelse return null;
        return @intFromPtr(f.data.ptr);
    }

    fn paramTableImpl(ptr: *anyopaque, file: []const u8) ?paramview.Table {
        const self: *OfflineHost = @ptrCast(@alignCast(ptr));
        // The SDK strips a trailing ".param"; BND4 entries carry it.
        var buf: [128]u8 = undefined;
        const name = std.fmt.bufPrint(&buf, "{s}.param", .{file}) catch return null;
        const f = self.archive.find(name) orelse return null;
        if (f.data.len < paramview.header_size) return null;
        return paramview.Table.at(f.data.ptr);
    }

    fn logImpl(ptr: *anyopaque, mod_name: []const u8, level: host_mod.Level, msg: []const u8) void {
        const self: *OfflineHost = @ptrCast(@alignCast(ptr));
        const tag = switch (level) {
            .info => "info",
            .warn => "warn",
            .err => "err",
        };
        // Best-effort, as in the runtime's host: a mod must not fail because
        // its log line could not be written.
        self.out.print("mod[{s}] {s}: {s}\n", .{ mod_name, tag, msg }) catch {};
    }

    fn paramWrittenImpl(ptr: *anyopaque, mod_name: []const u8, write: param_writes.Write) void {
        const self: *OfflineHost = @ptrCast(@alignCast(ptr));
        self.writes += 1;
        const c = self.ledger.record(mod_name, write) orelse return;
        self.conflicts += 1;
        // Only the first is kept: it is the one the message names, and every
        // later one is likely the same two mods overlapping again.
        if (self.conflict != null) return;
        var rec: Conflict = .{ .row = write.row };
        Conflict.copyInto(&rec.winner, &rec.winner_len, mod_name);
        Conflict.copyInto(&rec.previous, &rec.previous_len, c.previous);
        Conflict.copyInto(&rec.def_name, &rec.def_name_len, write.def_name);
        Conflict.copyInto(&rec.field, &rec.field_len, write.field);
        self.conflict = rec;
    }

    // Offline has no game: everything below is honestly unavailable. `params`
    // is the whole surface a launch mod needs, and `apply` refuses event mods
    // (the only kind that would reach `ui`, `perf` or `screen`) up front.

    fn perfImpl(ptr: *anyopaque) ?*perf.Stats {
        _ = ptr;
        return null;
    }

    fn uiImpl(ptr: *anyopaque) ?ui_backend.Backend {
        _ = ptr;
        return null;
    }

    fn storeLoadImpl(ptr: *anyopaque, mod_name: []const u8, buf: []u8) ?[]const u8 {
        _ = .{ ptr, mod_name, buf };
        return null;
    }

    fn storeSaveImpl(ptr: *anyopaque, mod_name: []const u8, bytes: []const u8) bool {
        _ = .{ ptr, mod_name, bytes };
        return false;
    }

    fn screenCaptureImpl(ptr: *anyopaque, mod_name: []const u8, request: screen.Request) bool {
        _ = .{ ptr, mod_name, request };
        return false;
    }
};

/// The one-line refusal for a conflict, formatted into `buf`.
pub fn formatConflict(buf: []u8, c: *const Conflict) []const u8 {
    return std.fmt.bufPrint(buf, "conflict — {s} wrote {s}[{d}].{s}, already written by {s}", .{
        c.winnerName(), c.defName(), c.row, c.fieldName(), c.previousName(),
    }) catch "conflict";
}

// ── tests ───────────────────────────────────────────────────────────────

const testing = std.testing;
const sdk = ermod_lua.sdk;

/// A one-entry archive holding a synthetic CharaInitParam, so the host can be
/// exercised without game data. Rows 3000/3001 at the real 320-byte stride.
const Fixture = struct {
    const ids = [_]u32{ 3000, 3001 };
    const row_size = 320;
    const rows_off = paramview.header_size + ids.len * paramview.row_descriptor_size;
    const strings_off = rows_off + ids.len * row_size;

    fn archive(gpa: std.mem.Allocator) !bnd4.Archive {
        const img = try gpa.alloc(u8, strings_off + 32);
        paramview.synthParam(img, "CHARACTER_INIT_PARAM", &ids, row_size);
        const files = try gpa.alloc(bnd4.File, 1);
        files[0] = .{
            .name = try gpa.dupe(u8, "CharaInitParam.param"),
            .id = 0,
            .flags = 0,
            .data = img,
        };
        const owned = try gpa.alloc(bool, 1);
        owned[0] = true;
        return .{
            .allocator = gpa,
            .prefix = try gpa.dupe(u8, ""),
            .files = files,
            .owned_data = owned,
            .data_start = 0,
        };
    }

    fn soulLv(a: *const bnd4.Archive, index: usize) i16 {
        const data = a.files[0].data;
        return std.mem.readInt(i16, data[rows_off + index * row_size + 192 ..][0..2], .little);
    }
};

const Sink = struct {
    buf: [4096]u8 = undefined,
    writer: std.Io.Writer = undefined,

    fn init(self: *Sink) *std.Io.Writer {
        self.writer = .fixed(&self.buf);
        return &self.writer;
    }

    fn text(self: *const Sink) []const u8 {
        return self.writer.buffered();
    }
};

fn runLua(h: *OfflineHost, src: []const u8) !void {
    const m = try sdk.load(testing.allocator, src, "=t.lua", h.host());
    defer sdk.destroy(m);
    try m.start();
}

test "a launch mod's field write lands in the archive's own bytes" {
    var a = try Fixture.archive(testing.allocator);
    defer a.deinit();
    var sink: Sink = .{};
    var h = OfflineHost.init(&a, sink.init());

    try runLua(&h,
        \\local mod = { name = "level60", version = "1", run_at = "launch", permissions = { "params", "log" } }
        \\function mod.on_launch(sdk)
        \\  local r = sdk.params.row("CharaInitParam", 3000)
        \\  sdk.log.info("before " .. r.soulLv)
        \\  r.soulLv = 60
        \\end
        \\return mod
    );

    // The write is in the archive entry itself, which is what `bnd4.write`
    // will serialise — no copy-back step in between.
    try testing.expectEqual(@as(i16, 60), Fixture.soulLv(&a, 0));
    try testing.expectEqual(@as(usize, 1), h.writes);
    try testing.expect(h.conflict == null);
    try testing.expect(std.mem.indexOf(u8, sink.text(), "mod[level60] info: before 0\n") != null);
}

test "the .param suffix is optional and an unknown file is unavailable, not a crash" {
    var a = try Fixture.archive(testing.allocator);
    defer a.deinit();
    var sink: Sink = .{};
    var h = OfflineHost.init(&a, sink.init());

    try runLua(&h,
        \\local mod = { name = "suffix", version = "1", run_at = "launch", permissions = { "params" } }
        \\function mod.on_launch(sdk)
        \\  assert(sdk.params.row("CharaInitParam.param", 3001) ~= nil)
        \\  local ok = pcall(function() sdk.params.row("EquipParamGoods", 1) end)
        \\  assert(not ok, "a param the archive lacks must error")
        \\end
        \\return mod
    );
}

test "two mods writing one field is recorded as a conflict, with both names" {
    var a = try Fixture.archive(testing.allocator);
    defer a.deinit();
    var sink: Sink = .{};
    var h = OfflineHost.init(&a, sink.init());

    try runLua(&h,
        \\local mod = { name = "class-tweaks", version = "1", run_at = "launch", permissions = { "params" } }
        \\function mod.on_launch(sdk) sdk.params.row("CharaInitParam", 3000).soulLv = 12 end
        \\return mod
    );
    try testing.expect(h.conflict == null);

    try runLua(&h,
        \\local mod = { name = "level60", version = "1", run_at = "launch", permissions = { "params" } }
        \\function mod.on_launch(sdk)
        \\  sdk.params.row("CharaInitParam", 3000).soulLv = 60
        \\  sdk.params.row("CharaInitParam", 3001).soulLv = 60
        \\end
        \\return mod
    );

    const c = h.conflict orelse return error.ExpectedConflict;
    try testing.expectEqual(@as(usize, 1), h.conflicts);
    var buf: [256]u8 = undefined;
    try testing.expectEqualStrings(
        "conflict — level60 wrote CharaInitParam[3000].soulLv, already written by class-tweaks",
        formatConflict(&buf, &c),
    );
    // The write itself still landed; `apply` refuses to pack, so what is in
    // the buffer never reaches a file.
    try testing.expectEqual(@as(i16, 60), Fixture.soulLv(&a, 0));
    // Row 3001 had no previous owner.
    try testing.expectEqual(@as(i16, 60), Fixture.soulLv(&a, 1));
}

test "one mod rewriting its own field is not a conflict" {
    var a = try Fixture.archive(testing.allocator);
    defer a.deinit();
    var sink: Sink = .{};
    var h = OfflineHost.init(&a, sink.init());

    const src =
        \\local mod = { name = "same", version = "1", run_at = "launch", permissions = { "params" } }
        \\function mod.on_launch(sdk)
        \\  sdk.params.row("CharaInitParam", 3000).soulLv = 30
        \\  sdk.params.row("CharaInitParam", 3000).soulLv = 60
        \\end
        \\return mod
    ;
    try runLua(&h, src);
    try runLua(&h, src);
    try testing.expect(h.conflict == null);
    try testing.expectEqual(@as(usize, 4), h.writes);
}

test "a Zig spec write and a Lua write on one field collide through the same ledger" {
    var a = try Fixture.archive(testing.allocator);
    defer a.deinit();
    var sink: Sink = .{};
    var h = OfflineHost.init(&a, sink.init());

    const table = h.tableIdentity("CharaInitParam.param") orelse return error.NoTable;
    h.recordWrite("level60", .{
        .table = table,
        .def_name = "CharaInitParam",
        .row = 3000,
        .field = "soulLv",
    });
    try testing.expect(h.conflict == null);

    try runLua(&h,
        \\local mod = { name = "class-tweaks", version = "1", run_at = "launch", permissions = { "params" } }
        \\function mod.on_launch(sdk) sdk.params.row("CharaInitParam", 3000).soulLv = 12 end
        \\return mod
    );

    const c = h.conflict orelse return error.ExpectedConflict;
    try testing.expectEqualStrings("class-tweaks", c.winnerName());
    try testing.expectEqualStrings("level60", c.previousName());
}

test "store, ui, perf and screen are unavailable offline" {
    var a = try Fixture.archive(testing.allocator);
    defer a.deinit();
    var sink: Sink = .{};
    var h = OfflineHost.init(&a, sink.init());
    const hh = h.host();

    var buf: [16]u8 = undefined;
    try testing.expect(hh.storeLoad("m", &buf) == null);
    try testing.expect(!hh.storeSave("m", "x"));
    try testing.expect(hh.uiBackend() == null);
    try testing.expect(hh.perfStats() == null);
    try testing.expect(!hh.screenCapture("m", .{}));
}
