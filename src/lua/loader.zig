//! Loading a mod script into its own sandboxed VM.
//!
//! One VM per mod: a mod's globals and state are its own, and the engine can
//! kill or reload one mod without touching the others. Loading is where all
//! validation happens — syntax, manifest shape, permissions, entry point —
//! so a mod that loads is a mod the engine is willing to run.

const std = @import("std");
const vm_mod = @import("vm.zig");
const manifest_mod = @import("manifest.zig");

pub const Error = manifest_mod.Error;

/// A loaded mod: its VM, its validated manifest, and the mod table left on
/// the VM's stack ready for dispatch.
pub const LoadedMod = struct {
    vm: vm_mod.Vm,
    manifest: manifest_mod.Manifest,

    pub fn deinit(self: *LoadedMod) void {
        self.vm.deinit();
        self.* = undefined;
    }
};

/// Load `source` as a mod. `chunk_name` appears in error messages; prefix it
/// with '=' to have Lua print it verbatim (e.g. "=hello_launch.lua").
pub fn loadSource(source: []const u8, chunk_name: [:0]const u8) Error!LoadedMod {
    var vm = try vm_mod.Vm.init();
    errdefer vm.deinit();

    try vm.loadModule(source, chunk_name);
    const m = try manifest_mod.parse(&vm);

    return .{ .vm = vm, .manifest = m };
}

const testing = std.testing;

// Fixtures under test/mods exercise one SDK slice each; see their README.
// Embedding them keeps the test hermetic (no cwd assumptions) while still
// testing the real files a runtime change would break.
const fixtures = struct {
    const hello_launch = @embedFile("fixtures/hello_launch.lua");
    const rune_counter = @embedFile("fixtures/rune_counter.lua");
    const double_runes = @embedFile("fixtures/double_runes.lua");
    const overlay = @embedFile("fixtures/overlay.lua");
    const perf_monitor = @embedFile("fixtures/perf_monitor.lua");
    const settings = @embedFile("fixtures/settings.lua");
    const bad_sandbox = @embedFile("fixtures/bad_sandbox.lua");
};

test "hello_launch fixture loads as a launch mod" {
    var m = try loadSource(fixtures.hello_launch, "=hello_launch.lua");
    defer m.deinit();

    try testing.expectEqualStrings("hello-launch", m.manifest.name);
    try testing.expectEqual(manifest_mod.RunAt.launch, m.manifest.run_at);
    try testing.expect(m.manifest.allows(.log));
}

test "rune_counter fixture loads as an event mod" {
    var m = try loadSource(fixtures.rune_counter, "=rune_counter.lua");
    defer m.deinit();

    try testing.expectEqualStrings("rune-counter", m.manifest.name);
    try testing.expectEqual(manifest_mod.RunAt.events, m.manifest.run_at);
    try testing.expect(m.manifest.allows(.hooks));
}

test "double_runes fixture declares the params permission" {
    var m = try loadSource(fixtures.double_runes, "=double_runes.lua");
    defer m.deinit();

    try testing.expect(m.manifest.allows(.params));
    try testing.expect(!m.manifest.allows(.ui));
}

test "overlay fixture declares ui and hooks only" {
    var m = try loadSource(fixtures.overlay, "=overlay.lua");
    defer m.deinit();

    try testing.expect(m.manifest.allows(.ui));
    try testing.expect(m.manifest.allows(.hooks));
    try testing.expect(!m.manifest.allows(.perf));
    try testing.expect(!m.manifest.allows(.store));
}

test "perf_monitor fixture declares ui and perf" {
    var m = try loadSource(fixtures.perf_monitor, "=perf_monitor.lua");
    defer m.deinit();

    try testing.expect(m.manifest.allows(.ui));
    try testing.expect(m.manifest.allows(.perf));
    try testing.expect(!m.manifest.allows(.store));
}

test "settings fixture declares store and survives load" {
    var m = try loadSource(fixtures.settings, "=settings.lua");
    defer m.deinit();

    try testing.expect(m.manifest.allows(.store));
    try testing.expectEqual(manifest_mod.RunAt.events, m.manifest.run_at);
}

test "bad_sandbox fixture loads but cannot reach os or io" {
    // The manifest itself is well-formed, so loading succeeds; the sandbox
    // bites when the entry point runs and finds os/io are nil. Dispatch
    // isn't implemented yet, so assert the denial directly in this VM.
    var m = try loadSource(fixtures.bad_sandbox, "=bad_sandbox.lua");
    defer m.deinit();

    try testing.expect(m.manifest.permissions.count() == 0);
    try testing.expect(m.vm.globalIsNil("os"));
    try testing.expect(m.vm.globalIsNil("io"));
    try testing.expectError(error.RuntimeError, m.vm.eval("return os.execute('echo hi')"));
}

test "each mod gets an isolated VM" {
    var a = try loadSource(fixtures.hello_launch, "=a.lua");
    defer a.deinit();
    var b = try loadSource(fixtures.hello_launch, "=b.lua");
    defer b.deinit();

    try a.vm.eval("leaked = 'from a'");
    try testing.expect(b.vm.globalIsNil("leaked"));
}
