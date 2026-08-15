const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // `spec` holds just the declarative patch types. Keeping it a leaf module
    // lets the mod specs (which live outside src/) and the tool share types
    // without a circular module dependency.
    const spec = b.createModule(.{
        .root_source_file = b.path("src/spec.zig"),
        .target = target,
        .optimize = optimize,
    });

    const mods = b.createModule(.{
        .root_source_file = b.path("mods/mods.zig"),
        .target = target,
        .optimize = optimize,
    });
    mods.addImport("spec", spec);

    // `ermod-lua`: the shared mod front end — Lua VM and sandbox, manifest,
    // loader, every SDK binding, and the `Host` interface those bindings
    // call back into. `ermod` here supplies the offline host (an unpacked
    // regulation.bin); the engine repo consumes this same module as a
    // package and supplies the live one. See `ermodLua` below for why the
    // module is built per-consumer rather than shared.
    const ermod_lua = ermodLua(b, target, optimize);

    const root = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    root.addImport("spec", spec);
    root.addImport("mods", mods);
    root.addImport("ermod_lua", ermod_lua);

    const exe = b.addExecutable(.{
        .name = "ermod",
        .root_module = root,
    });
    exe.root_module.linkSystemLibrary("zstd", .{});
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run ermod");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run unit tests");

    const tests = b.addTest(.{ .root_module = exe.root_module });
    tests.root_module.linkSystemLibrary("zstd", .{});
    test_step.dependOn(&b.addRunArtifact(tests).step);

    const mod_tests = b.addTest(.{ .root_module = mods });
    test_step.dependOn(&b.addRunArtifact(mod_tests).step);

    // The package tests itself here, so a change to the shared front end is
    // caught in this repo rather than only when the engine next builds.
    const lua_tests = b.addTest(.{ .root_module = ermodLua(b, target, optimize) });
    test_step.dependOn(&b.addRunArtifact(lua_tests).step);
}

/// Build the `ermod-lua` module for one target/optimize pair.
///
/// A module carries its target, and the two consumers do not share one: the
/// engine's runtime is `x86_64-windows-gnu` (it is injected into a PE
/// process) while `ermod` and the tests are host-native. So this is a
/// function the engine's `build.zig` calls too, through the package's
/// `build.zig`, rather than a single module created once.
pub fn ermodLua(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = b.path("src/ermod_lua.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    addLua(b, mod);
    return mod;
}

/// Compile the vendored Lua 5.4 sources into `module`.
///
/// Lua is embedded rather than linked from the system so neither consumer
/// has a runtime dependency and cross-compilation keeps working. LUA_USE_*
/// is deliberately left unset: those enable dlopen/popen support, which the
/// sandbox forbids anyway.
fn addLua(b: *std.Build, module: *std.Build.Module) void {
    module.addIncludePath(b.path("vendor/lua"));
    module.addCSourceFiles(.{
        .root = b.path("vendor/lua"),
        .files = &lua_sources,
        .flags = &.{ "-std=c99", "-fno-sanitize=undefined" },
    });
}

/// Every Lua translation unit except the standalone `lua.c` / `luac.c`
/// mains, which are not vendored.
const lua_sources = [_][]const u8{
    "lapi.c",     "lcode.c",    "lctype.c",   "ldebug.c",  "ldo.c",
    "ldump.c",    "lfunc.c",    "lgc.c",      "llex.c",    "lmem.c",
    "lobject.c",  "lopcodes.c", "lparser.c",  "lstate.c",  "lstring.c",
    "ltable.c",   "ltm.c",      "lundump.c",  "lvm.c",     "lzio.c",
    "lauxlib.c",  "lbaselib.c", "lcorolib.c", "ldblib.c",  "liolib.c",
    "lmathlib.c", "loadlib.c",  "loslib.c",   "lstrlib.c", "ltablib.c",
    "lutf8lib.c", "linit.c",
};
