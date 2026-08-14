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

    const root = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    root.addImport("spec", spec);
    root.addImport("mods", mods);

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
}
