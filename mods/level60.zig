//! Mod: every starting class begins at level 60.
//!
//! Elden Ring derives the displayed level from the stat total: the eight base
//! stats sum to `soulLv + 79`. Setting `soulLv` alone desynchronises the
//! character sheet from the rune cost curve, so each class gets an explicit
//! stat spread summing to 139 (= 60 + 79) that keeps its vanilla identity:
//! points are added on top of the vanilla spread, weighted toward the stats the
//! class already leads in.
//!
//! Vanilla spreads (levels 9, 8, 7, 5, 6, 7, 10, 9, 9, 1 respectively) are in
//! docs/classes.md.

const modspec = @import("spec");

pub const target_level = 60;

/// Stat total the game expects for a given level.
pub const stat_total_for_level = target_level + 79;

const Class = struct {
    row: u32,
    name: []const u8,
    vit: i64,
    wil: i64,
    end: i64,
    str: i64,
    dex: i64,
    mag: i64,
    fai: i64,
    luc: i64,

    fn total(self: Class) i64 {
        return self.vit + self.wil + self.end + self.str + self.dex + self.mag + self.fai + self.luc;
    }
};

/// Level-60 spreads. Each sums to 139; melee classes invest in Vigor/Endurance
/// and their damage stat, casters in Mind and their casting stat.
pub const classes = [_]Class{
    .{ .row = 3000, .name = "Vagabond", .vit = 30, .wil = 13, .end = 22, .str = 29, .dex = 20, .mag = 9, .fai = 9, .luc = 7 },
    .{ .row = 3001, .name = "Warrior", .vit = 23, .wil = 16, .end = 23, .str = 14, .dex = 36, .mag = 10, .fai = 8, .luc = 9 },
    .{ .row = 3002, .name = "Hero", .vit = 30, .wil = 9, .end = 24, .str = 37, .dex = 13, .mag = 7, .fai = 8, .luc = 11 },
    .{ .row = 3003, .name = "Bandit", .vit = 23, .wil = 15, .end = 19, .str = 13, .dex = 30, .mag = 9, .fai = 8, .luc = 22 },
    .{ .row = 3004, .name = "Astrologer", .vit = 20, .wil = 26, .end = 16, .str = 8, .dex = 15, .mag = 38, .fai = 7, .luc = 9 },
    .{ .row = 3005, .name = "Prophet", .vit = 21, .wil = 24, .end = 15, .str = 14, .dex = 10, .mag = 7, .fai = 38, .luc = 10 },
    .{ .row = 3006, .name = "Confessor", .vit = 21, .wil = 20, .end = 16, .str = 18, .dex = 18, .mag = 9, .fai = 28, .luc = 9 },
    .{ .row = 3007, .name = "Samurai", .vit = 24, .wil = 14, .end = 25, .str = 20, .dex = 31, .mag = 9, .fai = 8, .luc = 8 },
    .{ .row = 3008, .name = "Prisoner", .vit = 22, .wil = 18, .end = 17, .str = 14, .dex = 25, .mag = 28, .fai = 6, .luc = 9 },
    .{ .row = 3009, .name = "Wretch", .vit = 22, .wil = 18, .end = 18, .str = 18, .dex = 18, .mag = 18, .fai = 14, .luc = 13 },
};

const file = "CharaInitParam.param";

fn patchesFor(comptime c: Class) [9]modspec.Patch {
    return .{
        .{ .param_file = file, .row = c.row, .field = "soulLv", .value = .{ .int = target_level } },
        .{ .param_file = file, .row = c.row, .field = "baseVit", .value = .{ .int = c.vit } },
        .{ .param_file = file, .row = c.row, .field = "baseWil", .value = .{ .int = c.wil } },
        .{ .param_file = file, .row = c.row, .field = "baseEnd", .value = .{ .int = c.end } },
        .{ .param_file = file, .row = c.row, .field = "baseStr", .value = .{ .int = c.str } },
        .{ .param_file = file, .row = c.row, .field = "baseDex", .value = .{ .int = c.dex } },
        .{ .param_file = file, .row = c.row, .field = "baseMag", .value = .{ .int = c.mag } },
        .{ .param_file = file, .row = c.row, .field = "baseFai", .value = .{ .int = c.fai } },
        .{ .param_file = file, .row = c.row, .field = "baseLuc", .value = .{ .int = c.luc } },
    };
}

pub const spec = modspec.Spec{
    .name = "level60",
    .description = "All starting classes begin at level 60 with class-appropriate stats.",
    .patches = &patches,
};

const patches = blk: {
    var out: [classes.len * 9]modspec.Patch = undefined;
    for (classes, 0..) |c, i| {
        const p = patchesFor(c);
        for (p, 0..) |patch, j| out[i * 9 + j] = patch;
    }
    break :blk out;
};

const std = @import("std");

test "every spread matches the target level" {
    for (classes) |c| {
        std.testing.expectEqual(@as(i64, stat_total_for_level), c.total()) catch |err| {
            std.debug.print("class {s} sums to {d}, expected {d}\n", .{
                c.name, c.total(), stat_total_for_level,
            });
            return err;
        };
    }
}

test "stats stay within the game's legal range" {
    for (classes) |c| {
        const stats = [_]i64{ c.vit, c.wil, c.end, c.str, c.dex, c.mag, c.fai, c.luc };
        for (stats) |s| {
            try std.testing.expect(s >= 1);
            try std.testing.expect(s <= 99);
        }
    }
}
