//! Mod manifests: the declaration table a mod script returns.
//!
//! Every mod names itself, says when it runs, and declares which SDK
//! modules it may touch. The permission list is the user-visible contract —
//! a data-only mod physically cannot draw UI or read files — so it is
//! parsed strictly: an unknown permission name is an error rather than
//! something silently ignored, because silently ignoring it would grant
//! less than the author intended and fail confusingly later.

const std = @import("std");
const c = @import("c.zig").c;
const vm_mod = @import("vm.zig");
const Vm = vm_mod.Vm;

pub const Error = vm_mod.Error || error{
    UnknownPermission,
    UnknownRunAt,
    /// The entry point implied by `run_at` is missing.
    MissingEntryPoint,
};

/// When the engine runs a mod.
pub const RunAt = enum {
    /// Once at game launch — data edits, one-shot setup. Entry: on_launch.
    launch,
    /// Registers handlers that fire on engine events. Entry: setup.
    events,

    pub fn entryPoint(self: RunAt) [:0]const u8 {
        return switch (self) {
            .launch => "on_launch",
            .events => "setup",
        };
    }
};

/// SDK modules a mod can be granted. Mirrors the table in the plan.
pub const Permission = enum {
    params,
    hooks,
    ui,
    perf,
    store,
    log,
    screen,
};

pub const PermissionSet = std.EnumSet(Permission);

pub const Manifest = struct {
    /// Borrowed from the Lua state; copy if it must outlive the VM.
    name: []const u8,
    version: []const u8,
    run_at: RunAt,
    permissions: PermissionSet,

    pub fn allows(self: Manifest, p: Permission) bool {
        return self.permissions.contains(p);
    }
};

/// Parse the manifest from the mod table on top of `vm`'s stack. The table
/// is left on the stack.
pub fn parse(vm: *Vm) Error!Manifest {
    const name = try vm.tableString("name");
    const version = try vm.tableString("version");

    const run_at_str = try vm.tableString("run_at");
    const run_at = std.meta.stringToEnum(RunAt, run_at_str) orelse return error.UnknownRunAt;

    const permissions = try parsePermissions(vm);

    // A mod that declares when it runs but has no entry point to run is a
    // packaging mistake; catching it at load time beats a silent no-op.
    if (!vm.hasFunction(run_at.entryPoint())) return error.MissingEntryPoint;

    return .{
        .name = name,
        .version = version,
        .run_at = run_at,
        .permissions = permissions,
    };
}

fn parsePermissions(vm: *Vm) Error!PermissionSet {
    var set = PermissionSet.initEmpty();

    if (c.lua_getfield(vm.state, -1, "permissions") != c.LUA_TTABLE) {
        c.lua_settop(vm.state, -2);
        return error.BadManifest;
    }
    defer c.lua_settop(vm.state, -2);

    const len = c.lua_rawlen(vm.state, -1);
    var i: c.lua_Integer = 1;
    while (i <= len) : (i += 1) {
        if (c.lua_geti(vm.state, -1, i) != c.LUA_TSTRING) {
            c.lua_settop(vm.state, -2);
            return error.BadManifest;
        }
        var str_len: usize = 0;
        const ptr = c.lua_tolstring(vm.state, -1, &str_len) orelse {
            c.lua_settop(vm.state, -2);
            return error.BadManifest;
        };
        const p = std.meta.stringToEnum(Permission, ptr[0..str_len]);
        c.lua_settop(vm.state, -2);
        set.insert(p orelse return error.UnknownPermission);
    }

    return set;
}

const testing = std.testing;

fn parseSource(vm: *Vm, source: []const u8) Error!Manifest {
    try vm.loadModule(source, "=test");
    return parse(vm);
}

test "parses a launch mod manifest" {
    var vm = try Vm.init();
    defer vm.deinit();

    const m = try parseSource(&vm,
        \\local mod = {
        \\  name = "hello", version = "1.0.0",
        \\  run_at = "launch", permissions = { "log" },
        \\}
        \\function mod.on_launch() end
        \\return mod
    );

    try testing.expectEqualStrings("hello", m.name);
    try testing.expectEqualStrings("1.0.0", m.version);
    try testing.expectEqual(RunAt.launch, m.run_at);
    try testing.expect(m.allows(.log));
    try testing.expect(!m.allows(.params));
}

test "parses an event mod manifest" {
    var vm = try Vm.init();
    defer vm.deinit();

    const m = try parseSource(&vm,
        \\local mod = {
        \\  name = "counter", version = "0.1.0",
        \\  run_at = "events", permissions = { "hooks", "log" },
        \\}
        \\function mod.setup() end
        \\return mod
    );

    try testing.expectEqual(RunAt.events, m.run_at);
    try testing.expect(m.allows(.hooks));
    try testing.expect(m.allows(.log));
    try testing.expect(!m.allows(.ui));
}

test "rejects an unknown permission" {
    var vm = try Vm.init();
    defer vm.deinit();

    try testing.expectError(error.UnknownPermission, parseSource(&vm,
        \\local mod = {
        \\  name = "x", version = "1", run_at = "launch",
        \\  permissions = { "filesystem" },
        \\}
        \\function mod.on_launch() end
        \\return mod
    ));
}

test "rejects an unknown run_at" {
    var vm = try Vm.init();
    defer vm.deinit();

    try testing.expectError(error.UnknownRunAt, parseSource(&vm,
        \\local mod = {
        \\  name = "x", version = "1", run_at = "whenever",
        \\  permissions = {},
        \\}
        \\return mod
    ));
}

test "rejects a missing entry point" {
    var vm = try Vm.init();
    defer vm.deinit();

    try testing.expectError(error.MissingEntryPoint, parseSource(&vm,
        \\return { name = "x", version = "1", run_at = "launch", permissions = {} }
    ));
}

test "rejects a missing manifest field" {
    var vm = try Vm.init();
    defer vm.deinit();

    try testing.expectError(error.BadManifest, parseSource(&vm,
        \\return { name = "x", run_at = "launch", permissions = {} }
    ));
}
