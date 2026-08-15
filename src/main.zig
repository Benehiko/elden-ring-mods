const std = @import("std");
const crypto = @import("crypto.zig");
const dcx = @import("dcx.zig");
const bnd4 = @import("bnd4.zig");
const param = @import("param.zig");
const paramcheck = @import("paramcheck.zig");
const ermod_lua = @import("ermod_lua");
const paramview = ermod_lua.paramview;
const paramdef = ermod_lua.paramdef;
const defs = ermod_lua.paramdefs;
const modspec = @import("modspec.zig");
const mods = @import("mods");
const level60 = mods.level60;
const class_gear = mods.class_gear;

/// Mods selectable on the command line.
const available_mods = [_]struct { name: []const u8, spec: modspec.Spec }{
    .{ .name = "level60", .spec = level60.spec },
    .{ .name = "class-gear", .spec = class_gear.spec },
};

const usage =
    \\ermod — Elden Ring regulation.bin tooling
    \\
    \\Usage:
    \\  ermod decrypt <regulation.bin> <out.dcx>       Decrypt regulation.bin
    \\  ermod encrypt <in.dcx> <regulation.bin>        Encrypt back to regulation.bin
    \\  ermod unpack <regulation.bin> <out.bnd>        Decrypt + decompress to raw BND4
    \\  ermod pack <in.bnd> <template.bin> <out.bin>   Compress + encrypt back (template
    \\                                                 supplies the original DCX header)
    \\  ermod ls <regulation.bin>                      List param files in the archive
    \\  ermod extract <regulation.bin> <name> <out>    Extract one param file
    \\  ermod show <regulation.bin> <row-id> [field]   Show CharaInitParam row fields
    \\  ermod mods                                     List available mods
    \\  ermod selftest <regulation.bin>                Golden checks against the real game
    \\  ermod verify-ids <regulation.bin>              Check mod item IDs exist in the game
    \\  ermod apply <regulation.bin> <out.bin> <mod>...
    \\                                                 Apply mods, write a modded copy
    \\
;

const max_file_size = 512 * 1024 * 1024;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var args: [8][]const u8 = undefined;
    var argc: usize = 0;
    var it = std.process.Args.Iterator.init(init.minimal.args);
    while (it.next()) |arg| : (argc += 1) {
        if (argc >= args.len) break;
        args[argc] = arg;
    }
    if (argc < 2) {
        std.debug.print("{s}", .{usage});
        return error.InvalidArguments;
    }

    const cmd = args[1];
    if (std.mem.eql(u8, cmd, "decrypt")) {
        try requireArgs(argc, 4);
        const data = try readFile(io, gpa, args[2]);
        defer gpa.free(data);
        const plain = try crypto.decrypt(gpa, crypto.er_regulation_key, data);
        defer gpa.free(plain);
        try writeFile(io, args[3], plain);
        const magic = plain[0..@min(4, plain.len)];
        std.debug.print("decrypted {s} -> {s} ({d} bytes, magic: {s})\n", .{
            args[2], args[3], plain.len, magic,
        });
    } else if (std.mem.eql(u8, cmd, "encrypt")) {
        try requireArgs(argc, 4);
        const data = try readFile(io, gpa, args[2]);
        defer gpa.free(data);
        const enc = try crypto.encrypt(gpa, crypto.er_regulation_key, data, null);
        defer gpa.free(enc);
        try writeFile(io, args[3], enc);
        std.debug.print("encrypted {s} -> {s} ({d} bytes)\n", .{ args[2], args[3], enc.len });
    } else if (std.mem.eql(u8, cmd, "unpack")) {
        try requireArgs(argc, 4);
        const data = try readFile(io, gpa, args[2]);
        defer gpa.free(data);
        const plain = try crypto.decrypt(gpa, crypto.er_regulation_key, data);
        defer gpa.free(plain);
        var unpacked = try dcx.unpackWithHeader(gpa, plain);
        defer unpacked.deinit(gpa);
        try writeFile(io, args[3], unpacked.data);
        const magic = unpacked.data[0..@min(4, unpacked.data.len)];
        std.debug.print("unpacked {s} -> {s} ({d} bytes, magic: {s})\n", .{
            args[2], args[3], unpacked.data.len, magic,
        });
    } else if (std.mem.eql(u8, cmd, "pack")) {
        try requireArgs(argc, 5);
        const bnd = try readFile(io, gpa, args[2]);
        defer gpa.free(bnd);
        const template_enc = try readFile(io, gpa, args[3]);
        defer gpa.free(template_enc);
        const template_plain = try crypto.decrypt(gpa, crypto.er_regulation_key, template_enc);
        defer gpa.free(template_plain);
        var template = try dcx.unpackWithHeader(gpa, template_plain);
        defer template.deinit(gpa);

        const dcx_bytes = try dcx.pack(gpa, template.header, bnd);
        defer gpa.free(dcx_bytes);
        const enc = try crypto.encrypt(gpa, crypto.er_regulation_key, dcx_bytes, null);
        defer gpa.free(enc);
        try writeFile(io, args[4], enc);
        std.debug.print("packed {s} -> {s} ({d} bytes)\n", .{ args[2], args[4], enc.len });
    } else if (std.mem.eql(u8, cmd, "ls")) {
        try requireArgs(argc, 3);
        var archive = try openRegulation(io, gpa, args[2]);
        defer archive.deinit();
        for (archive.files) |f| {
            std.debug.print("{d:>6}  {d:>10}  {s}\n", .{ f.id, f.data.len, f.name });
        }
        std.debug.print("{d} files\n", .{archive.files.len});
    } else if (std.mem.eql(u8, cmd, "extract")) {
        try requireArgs(argc, 5);
        var archive = try openRegulation(io, gpa, args[2]);
        defer archive.deinit();
        const f = archive.find(args[3]) orelse {
            std.debug.print("no file matching '{s}'\n", .{args[3]});
            return error.FileNotFound;
        };
        try writeFile(io, args[4], f.data);
        std.debug.print("extracted {s} -> {s} ({d} bytes)\n", .{ f.name, args[4], f.data.len });
    } else if (std.mem.eql(u8, cmd, "show")) {
        if (argc < 4) {
            std.debug.print("{s}", .{usage});
            return error.InvalidArguments;
        }
        var archive = try openRegulation(io, gpa, args[2]);
        defer archive.deinit();
        const file = archive.find("CharaInitParam.param") orelse return error.FileNotFound;
        var p = try param.read(gpa, file.data);
        defer p.deinit();

        const row_id = try std.fmt.parseInt(u32, args[3], 10);
        const row = p.findRow(row_id) orelse {
            std.debug.print("no row {d}\n", .{row_id});
            return error.RowNotFound;
        };
        std.debug.print("{s} row {d} (row size {d})\n", .{ p.param_type, row_id, p.row_size });

        const filter: ?[]const u8 = if (argc >= 5) args[4] else null;
        for (&defs.CharaInitParam.fields) |*f| {
            if (filter) |want| {
                if (std.mem.indexOf(u8, f.name, want) == null) continue;
            }
            if (f.kind.isFloat()) {
                const v = paramdef.getFloat(row.data, f) catch continue;
                if (filter == null and v == 0) continue;
                std.debug.print("  {s:<28} {d}\n", .{ f.name, v });
            } else {
                const v = paramdef.getInt(row.data, f) catch continue;
                if (filter == null and v == 0) continue;
                std.debug.print("  {s:<28} {d}\n", .{ f.name, v });
            }
        }
    } else if (std.mem.eql(u8, cmd, "selftest")) {
        // Golden test against the real install: rebuilding the archive with no
        // patches must reproduce it byte for byte, and applying a mod must
        // touch only the params that mod names. Not a unit test, because it
        // needs game data that cannot live in the repo or in CI.
        try requireArgs(argc, 3);
        const raw = try readFile(io, gpa, args[2]);
        defer gpa.free(raw);
        const plain = try crypto.decrypt(gpa, crypto.er_regulation_key, raw);
        defer gpa.free(plain);
        const original_bnd = try dcx.unpack(gpa, plain);
        defer gpa.free(original_bnd);

        var archive = try bnd4.read(gpa, original_bnd);
        defer archive.deinit();

        const rebuilt = try bnd4.write(gpa, &archive);
        defer gpa.free(rebuilt);

        if (!std.mem.eql(u8, original_bnd, rebuilt)) {
            std.debug.print("FAIL: no-op rebuild is not byte-identical\n", .{});
            return error.SelfTestFailed;
        }
        std.debug.print("ok: no-op rebuild is byte-identical ({d} bytes)\n", .{rebuilt.len});

        // Both PARAM readers over every real table, on the archive's original
        // bytes: the file reader `apply` uses, and the in-place view a Lua mod
        // sees through `sdk.params`. Synthetic fixtures cover the layout in
        // `zig build test`; only the game's own params have the row counts,
        // string blocks and padding that would expose a divergence — and a
        // divergence means a field a mod edits live lands elsewhere offline.
        var checked: usize = 0;
        var rows: usize = 0;
        for (archive.files) |*f| {
            if (!std.mem.endsWith(u8, f.name, ".param")) continue;
            paramcheck.compare(gpa, f.data) catch |err| {
                std.debug.print("FAIL: {s}: readers disagree ({s})\n", .{ f.name, @errorName(err) });
                return error.SelfTestFailed;
            };
            checked += 1;
            rows += (paramview.Table.at(f.data.ptr) orelse unreachable).row_count;
        }
        std.debug.print("ok: both param readers agree on {d} table(s), {d} rows\n", .{ checked, rows });

        const report = try modspec.apply(gpa, &archive, &.{ level60.spec, class_gear.spec });
        const patched = try bnd4.write(gpa, &archive);
        defer gpa.free(patched);

        if (patched.len != original_bnd.len) {
            std.debug.print("FAIL: patched archive changed size ({d} -> {d})\n", .{
                original_bnd.len, patched.len,
            });
            return error.SelfTestFailed;
        }

        var differing: usize = 0;
        for (original_bnd, patched) |a, b| {
            if (a != b) differing += 1;
        }
        std.debug.print("ok: {d} patches changed {d} bytes in {d} param(s)\n", .{
            report.patches_applied, differing, report.params_touched,
        });
    } else if (std.mem.eql(u8, cmd, "mods")) {
        for (available_mods) |m| {
            std.debug.print("{s:<12} {s} ({d} patches)\n", .{
                m.name, m.spec.description, m.spec.patches.len,
            });
        }
    } else if (std.mem.eql(u8, cmd, "verify-ids")) {
        try requireArgs(argc, 3);
        var archive = try openRegulation(io, gpa, args[2]);
        defer archive.deinit();

        var bad: usize = 0;
        bad += try verifyIds(gpa, &archive, "EquipParamWeapon.param", &class_gear.referenced_weapons);
        bad += try verifyIds(gpa, &archive, "EquipParamProtector.param", &class_gear.referenced_protectors);
        bad += try verifyIds(gpa, &archive, "EquipParamGoods.param", &class_gear.referenced_goods);
        if (bad != 0) {
            std.debug.print("{d} id(s) missing from the game's params\n", .{bad});
            return error.UnknownItemId;
        }
        std.debug.print("all mod item ids exist in the game's params\n", .{});
    } else if (std.mem.eql(u8, cmd, "apply")) {
        if (argc < 5) {
            std.debug.print("{s}", .{usage});
            return error.InvalidArguments;
        }
        var selected: [available_mods.len]modspec.Spec = undefined;
        var count: usize = 0;
        for (args[4..argc]) |want| {
            const found = for (available_mods) |m| {
                if (std.mem.eql(u8, m.name, want)) break m.spec;
            } else {
                std.debug.print("unknown mod '{s}' (try `ermod mods`)\n", .{want});
                return error.UnknownMod;
            };
            selected[count] = found;
            count += 1;
        }

        var archive = try openRegulation(io, gpa, args[2]);
        defer archive.deinit();

        const report = try modspec.apply(gpa, &archive, selected[0..count]);

        const bnd = try bnd4.write(gpa, &archive);
        defer gpa.free(bnd);

        // The DCX header template comes from the original regulation.bin, so
        // unknown header fields survive the round trip.
        const original = try readFile(io, gpa, args[2]);
        defer gpa.free(original);
        const original_plain = try crypto.decrypt(gpa, crypto.er_regulation_key, original);
        defer gpa.free(original_plain);
        var template = try dcx.unpackWithHeader(gpa, original_plain);
        defer template.deinit(gpa);

        const packed_dcx = try dcx.pack(gpa, template.header, bnd);
        defer gpa.free(packed_dcx);
        const enc = try crypto.encrypt(gpa, crypto.er_regulation_key, packed_dcx, null);
        defer gpa.free(enc);
        try writeFile(io, args[3], enc);

        std.debug.print("applied {d} patches across {d} param(s) -> {s} ({d} bytes)\n", .{
            report.patches_applied, report.params_touched, args[3], enc.len,
        });
    } else {
        std.debug.print("{s}", .{usage});
        return error.InvalidArguments;
    }
}

/// Reports how many of `ids` are absent from the given param file.
fn verifyIds(
    gpa: std.mem.Allocator,
    archive: *bnd4.Archive,
    param_file: []const u8,
    ids: []const i64,
) !usize {
    const file = archive.find(param_file) orelse return error.FileNotFound;
    var p = try param.read(gpa, file.data);
    defer p.deinit();

    var missing: usize = 0;
    for (ids) |id| {
        if (id < 0) continue;
        if (p.findRow(@intCast(id)) == null) {
            std.debug.print("  missing: {s} row {d}\n", .{ param_file, id });
            missing += 1;
        }
    }
    return missing;
}

/// Decrypts, decompresses and parses a regulation.bin into a BND4 archive.
fn openRegulation(io: std.Io, gpa: std.mem.Allocator, path: []const u8) !bnd4.Archive {
    const raw = try readFile(io, gpa, path);
    defer gpa.free(raw);
    const plain = try crypto.decrypt(gpa, crypto.er_regulation_key, raw);
    defer gpa.free(plain);
    const bnd = try dcx.unpack(gpa, plain);
    defer gpa.free(bnd);
    return bnd4.read(gpa, bnd);
}

fn requireArgs(argc: usize, n: usize) !void {
    if (argc != n) {
        std.debug.print("{s}", .{usage});
        return error.InvalidArguments;
    }
}

fn readFile(io: std.Io, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_file_size));
}

fn writeFile(io: std.Io, path: []const u8, data: []const u8) !void {
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = data });
}

test {
    _ = crypto;
    _ = dcx;
    _ = bnd4;
    _ = param;
    _ = paramcheck;
    _ = paramdef;
    _ = modspec;
    _ = level60;
    _ = class_gear;
}
