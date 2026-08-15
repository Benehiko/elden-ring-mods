//! Recording which mod last wrote each param field, so cross-mod conflicts
//! are reported instead of silently last-wins.
//!
//! The `params` module reports every successful field write to the host as
//! `(mod, table, row, field)`; the host keeps one of these ledgers and asks
//! it, per write, whether a *different* mod owned that field before. The
//! answer is logged (once per change of owner) — the write itself still
//! lands, because last-wins is the rule offline too and a fence would make
//! load order silently decide the game instead of loudly. A mod rewriting
//! its own field (a hot-reloaded launch mod re-running `on_launch`) is not
//! a conflict.
//!
//! Fixed capacity, no allocation: names are copied into bounded slots so a
//! reloaded mod's freed name cannot dangle here. Pure, host-tested.

const std = @import("std");

/// One field write, as the `params` module reports it.
pub const Write = struct {
    /// Identity of the live table (its header address); distinguishes files
    /// that share a paramdef (`ItemLotParam_map` vs `_enemy`).
    table: usize,
    /// The paramdef's file name, for the message.
    def_name: []const u8,
    row: u32,
    field: []const u8,
};

pub const max_entries = 4096;
pub const name_cap = 48;

/// A conflict: `previous` owned the field before this write.
pub const Conflict = struct {
    previous: []const u8,
};

const Entry = struct {
    used: bool = false,
    table: usize = 0,
    row: u32 = 0,
    field_hash: u64 = 0,
    owner: [name_cap]u8 = undefined,
    owner_len: u8 = 0,

    fn ownerName(self: *const Entry) []const u8 {
        return self.owner[0..self.owner_len];
    }
};

pub const Ledger = struct {
    entries: [max_entries]Entry = [_]Entry{.{}} ** max_entries,
    count: usize = 0,
    /// Writes dropped because the ledger was full (reported once by the
    /// host, so a silent gap is at least visible).
    dropped: usize = 0,
    /// The previous owner of the last conflict, copied out so the returned
    /// slice does not alias the slot being reassigned.
    scratch: [name_cap]u8 = undefined,
    scratch_len: u8 = 0,

    /// Record that `mod` wrote `w`. Returns the previous owner if it was a
    /// different mod. The returned slice points into the ledger and is
    /// valid until the next `record` on the same field.
    pub fn record(self: *Ledger, mod: []const u8, w: Write) ?Conflict {
        const fh = std.hash.Wyhash.hash(0, w.field);
        for (self.entries[0..self.count]) |*e| {
            if (e.table == w.table and e.row == w.row and e.field_hash == fh) {
                if (std.mem.eql(u8, e.ownerName(), mod)) return null;
                // Report against a copy of the old owner: setting the new
                // owner overwrites the slot the returned slice would alias.
                var prev: [name_cap]u8 = undefined;
                const n = e.owner_len;
                @memcpy(prev[0..n], e.owner[0..n]);
                setOwner(e, mod);
                self.scratch = prev;
                self.scratch_len = n;
                return .{ .previous = self.scratch[0..self.scratch_len] };
            }
        }
        if (self.count == max_entries) {
            self.dropped += 1;
            return null;
        }
        const e = &self.entries[self.count];
        self.count += 1;
        e.* = .{ .used = true, .table = w.table, .row = w.row, .field_hash = fh };
        setOwner(e, mod);
        return null;
    }

    fn setOwner(e: *Entry, mod: []const u8) void {
        const n: u8 = @intCast(@min(mod.len, name_cap));
        @memcpy(e.owner[0..n], mod[0..n]);
        e.owner_len = n;
    }
};

/// The one-line report for a conflict, formatted into `buf`.
pub fn formatConflict(buf: []u8, mod: []const u8, w: Write, conflict: Conflict) []const u8 {
    return std.fmt.bufPrint(buf, "params conflict — {s} wrote {s}[{d}].{s}, previously written by {s}", .{
        mod, w.def_name, w.row, w.field, conflict.previous,
    }) catch "params conflict";
}

const testing = std.testing;

test "a second mod writing the same field is a conflict; the same mod is not" {
    var l = Ledger{};
    const w: Write = .{ .table = 0x1000, .def_name = "CharaInitParam", .row = 3000, .field = "soulLv" };
    try testing.expect(l.record("a", w) == null);
    try testing.expect(l.record("a", w) == null);
    const c = l.record("b", w) orelse return error.ExpectedConflict;
    try testing.expectEqualStrings("a", c.previous);
    // Owner is now b; b again is silent, a again conflicts the other way.
    try testing.expect(l.record("b", w) == null);
    try testing.expectEqualStrings("b", (l.record("a", w) orelse return error.ExpectedConflict).previous);
}

test "different rows, fields and tables are independent" {
    var l = Ledger{};
    const base: Write = .{ .table = 1, .def_name = "X", .row = 1, .field = "f" };
    try testing.expect(l.record("a", base) == null);
    var other = base;
    other.row = 2;
    try testing.expect(l.record("b", other) == null);
    other = base;
    other.field = "g";
    try testing.expect(l.record("b", other) == null);
    other = base;
    other.table = 2;
    try testing.expect(l.record("b", other) == null);
    try testing.expect(l.record("b", base) != null);
}

test "the message names both mods and the field" {
    var buf: [256]u8 = undefined;
    const msg = formatConflict(&buf, "level-60", .{ .table = 0, .def_name = "CharaInitParam", .row = 3000, .field = "soulLv" }, .{ .previous = "class-tweaks" });
    try testing.expectEqualStrings("params conflict — level-60 wrote CharaInitParam[3000].soulLv, previously written by class-tweaks", msg);
}

test "a full ledger drops and counts rather than failing" {
    var l = Ledger{};
    var i: usize = 0;
    while (i < max_entries + 5) : (i += 1) {
        _ = l.record("a", .{ .table = 1, .def_name = "X", .row = @intCast(i), .field = "f" });
    }
    try testing.expectEqual(@as(usize, max_entries), l.count);
    try testing.expectEqual(@as(usize, 5), l.dropped);
}
