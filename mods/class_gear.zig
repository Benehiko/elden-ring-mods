//! Mod: every starting class begins with a fuller kit.
//!
//! This is route 1 from docs/architecture.md — the gear is granted through
//! `CharaInitParam`'s equipment and item slots rather than by spawning a chest
//! in the world, which would need map and event-script edits.
//!
//! Every ID below was verified to exist in the shipped `EquipParamWeapon`,
//! `EquipParamProtector` and `EquipParamGoods` tables (see the `verify-ids`
//! test in src/main.zig, which re-checks them against the game's own params).
//!
//! Weapons are always **base** IDs (upgrade level 0). Upgraded weapons are not
//! separate rows in `EquipParamWeapon` — reinforcement is applied through
//! `ReinforceParamWeapon` at runtime — so writing e.g. `2000006` here would
//! reference a nonexistent row and the weapon would fail to equip.

const std = @import("std");
const modspec = @import("spec");

const file = "CharaInitParam.param";

/// A second weapon and a shield or catalyst for each class, plus a pool of
/// consumables. Vanilla main-hand/armour choices are left alone so each class
/// still looks and plays like itself.
const Kit = struct {
    row: u32,
    name: []const u8,
    /// Off-hand slot 2: an extra weapon (`-1` leaves the slot empty).
    subwep_right: i64 = -1,
    /// Off-hand slot 2 on the left: usually a shield or second catalyst.
    subwep_left: i64 = -1,
    /// Armour pieces, only set for classes that start (partly) unarmoured.
    helm: ?i64 = null,
    armor: ?i64 = null,
    gaunt: ?i64 = null,
    leg: ?i64 = null,
};

// Weapons (base IDs, upgrade 0).
const lordsworn_straight_sword = 2000000;
const longsword = 2010000;
const uchigatana = 9000000;
const nagakiba = 9010000;
const estoc = 6020000;
const claymore = 11000000;
const bastard_sword = 11010000;
const battle_axe = 14000000;
const greataxe = 15000000;
const halberd = 16000000;
const scimitar = 4000000;
const shamshir = 4010000;
const dagger = 1000000;
const club = 10000000;
const twinblade = 7140000;
const meteorite_staff = 33170000;
const finger_seal = 34000000;
const brass_shield = 31230000;
const buckler = 30080000;
const beast_crest_heater_shield = 31330000;

// Armour (Vagabond's set — heavy but available to every class).
const vagabond_helm = 660000;
const vagabond_armor = 660100;
const vagabond_gaunt = 660200;
const vagabond_leg = 660300;

// Goods.
const flask_of_crimson_tears = 101;
const flask_of_cerulean_tears = 102;
const throwing_knife = 110;
const bewitching_branch = 115;

pub const kits = [_]Kit{
    .{ .row = 3000, .name = "Vagabond", .subwep_right = longsword, .subwep_left = brass_shield },
    .{ .row = 3001, .name = "Warrior", .subwep_right = uchigatana, .subwep_left = buckler },
    .{ .row = 3002, .name = "Hero", .subwep_right = greataxe, .subwep_left = beast_crest_heater_shield },
    .{ .row = 3003, .name = "Bandit", .subwep_right = scimitar, .subwep_left = buckler },
    .{ .row = 3004, .name = "Astrologer", .subwep_right = estoc, .subwep_left = meteorite_staff },
    .{ .row = 3005, .name = "Prophet", .subwep_right = halberd, .subwep_left = finger_seal, .gaunt = vagabond_gaunt },
    .{ .row = 3006, .name = "Confessor", .subwep_right = lordsworn_straight_sword, .subwep_left = brass_shield },
    .{ .row = 3007, .name = "Samurai", .subwep_right = nagakiba, .subwep_left = brass_shield },
    .{ .row = 3008, .name = "Prisoner", .subwep_right = twinblade, .subwep_left = buckler, .gaunt = vagabond_gaunt },
    // The Wretch starts naked with only a club; give it a full kit so level 60
    // is survivable, while keeping the "no frills" flavour.
    .{
        .row = 3009,
        .name = "Wretch",
        .subwep_right = club,
        .subwep_left = buckler,
        .helm = vagabond_helm,
        .armor = vagabond_armor,
        .gaunt = vagabond_gaunt,
        .leg = vagabond_leg,
    },
};

/// Consumables granted to every class, in `item_NN` slots.
const shared_items = [_]struct { id: i64, count: i64 }{
    .{ .id = throwing_knife, .count = 10 },
    .{ .id = bewitching_branch, .count = 3 },
};

/// Weapon and armour IDs referenced above, for the ID-existence test.
pub const referenced_weapons = blk: {
    var out: [kits.len * 2]i64 = undefined;
    var n = 0;
    for (kits) |k| {
        if (k.subwep_right != -1) {
            out[n] = k.subwep_right;
            n += 1;
        }
        if (k.subwep_left != -1) {
            out[n] = k.subwep_left;
            n += 1;
        }
    }
    break :blk out[0..n].*;
};

pub const referenced_protectors = [_]i64{
    vagabond_helm, vagabond_armor, vagabond_gaunt, vagabond_leg,
};

pub const referenced_goods = [_]i64{
    flask_of_crimson_tears, flask_of_cerulean_tears, throwing_knife, bewitching_branch,
};

const patch_count = blk: {
    var n = 0;
    for (kits) |k| {
        if (k.subwep_right != -1) n += 1;
        if (k.subwep_left != -1) n += 1;
        if (k.helm != null) n += 1;
        if (k.armor != null) n += 1;
        if (k.gaunt != null) n += 1;
        if (k.leg != null) n += 1;
        n += shared_items.len * 2; // id + count per item
    }
    break :blk n;
};

const patches = blk: {
    var out: [patch_count]modspec.Patch = undefined;
    var n = 0;

    for (kits) |k| {
        if (k.subwep_right != -1) {
            out[n] = .{ .param_file = file, .row = k.row, .field = "equip_Subwep_Right", .value = .{ .int = k.subwep_right } };
            n += 1;
        }
        if (k.subwep_left != -1) {
            out[n] = .{ .param_file = file, .row = k.row, .field = "equip_Subwep_Left", .value = .{ .int = k.subwep_left } };
            n += 1;
        }
        if (k.helm) |v| {
            out[n] = .{ .param_file = file, .row = k.row, .field = "equip_Helm", .value = .{ .int = v } };
            n += 1;
        }
        if (k.armor) |v| {
            out[n] = .{ .param_file = file, .row = k.row, .field = "equip_Armer", .value = .{ .int = v } };
            n += 1;
        }
        if (k.gaunt) |v| {
            out[n] = .{ .param_file = file, .row = k.row, .field = "equip_Gaunt", .value = .{ .int = v } };
            n += 1;
        }
        if (k.leg) |v| {
            out[n] = .{ .param_file = file, .row = k.row, .field = "equip_Leg", .value = .{ .int = v } };
            n += 1;
        }

        // Consumables occupy item_04 onward; the lower slots hold each class's
        // vanilla starting items (e.g. the Confessor's Assassin's Approach).
        for (shared_items, 0..) |item, i| {
            const slot = 4 + i;
            out[n] = .{
                .param_file = file,
                .row = k.row,
                .field = std.fmt.comptimePrint("item_{d:0>2}", .{slot}),
                .value = .{ .int = item.id },
            };
            n += 1;
            out[n] = .{
                .param_file = file,
                .row = k.row,
                .field = std.fmt.comptimePrint("itemNum_{d:0>2}", .{slot}),
                .value = .{ .int = item.count },
            };
            n += 1;
        }
    }

    break :blk out;
};

pub const spec = modspec.Spec{
    .name = "class-gear",
    .description = "Extra weapon, shield/catalyst and consumables for every starting class.",
    .patches = &patches,
};

test "kits cover all ten classes exactly once" {
    var seen = [_]bool{false} ** 10;
    for (kits) |k| {
        const idx = k.row - 3000;
        try std.testing.expect(idx < seen.len);
        try std.testing.expect(!seen[idx]);
        seen[idx] = true;
    }
    for (seen) |s| try std.testing.expect(s);
}

test "weapon ids are base ids, not upgraded ones" {
    // Upgrade level is the low four digits; reinforced rows do not exist.
    for (referenced_weapons) |id| {
        try std.testing.expectEqual(@as(i64, 0), @mod(id, 10000));
    }
}
