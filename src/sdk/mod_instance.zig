//! A loaded, runnable mod: VM, manifest, SDK context and dispatch.
//!
//! This is where the pieces meet — the sandboxed VM from `lua/`, the
//! permission-gated SDK table, and the engine's event loop. Dispatch is
//! deliberately failure-tolerant: a handler error is reported and swallowed;
//! it never propagates into the game's frame.
//!
//! Misbehaviour is bounded, not just tolerated. A handler that exhausts its
//! instruction budget has already stalled a frame, so the mod is disabled on
//! the spot. A handler that errors is given `max_strikes` chances (a bug in
//! a hot handler otherwise spams the log sixty times a second and keeps
//! paying its dispatch cost); on the last strike the mod is disabled. A
//! disabled mod stays loaded — its VM is closed with the rest at shutdown —
//! but receives no further events; the engine logs exactly one line saying
//! why, and continues with the other mods.

const std = @import("std");
const c = @import("../lua/c.zig").c;
const vm_mod = @import("../lua/vm.zig");
const manifest_mod = @import("../lua/manifest.zig");
const loader = @import("../lua/loader.zig");
const host_mod = @import("host.zig");
const sdk = @import("sdk.zig");
const hooks = @import("hooks.zig");
const perf = @import("../perf.zig");

pub const Error = loader.Error || std.mem.Allocator.Error;

pub const ModInstance = struct {
    gpa: std.mem.Allocator,
    vm: vm_mod.Vm,
    /// Owned copy: the manifest's slices borrow Lua memory, but the SDK
    /// context outlives any particular stack frame.
    name: []const u8,
    run_at: manifest_mod.RunAt,
    permissions: manifest_mod.PermissionSet,
    ctx: sdk.Context,
    /// Registry ref to the mod table, so dispatch can find it again after
    /// the load-time stack is gone.
    mod_ref: c_int,
    /// Handler errors so far. Reaching `max_strikes` disables the mod.
    strikes: u32 = 0,
    /// Set once the mod is killed; `fire` is a no-op from then on.
    disabled: bool = false,
    /// This mod's slot in the engine's cost accounting, when the host keeps
    /// stats and a slot was free. Every handler call is timed into it.
    cost: ?*perf.ModCost = null,

    /// Runtime errors a mod may raise from its handlers before it is
    /// disabled. A budget overrun disables it immediately regardless.
    pub const max_strikes: u32 = 3;

    pub fn deinit(self: *ModInstance) void {
        if (self.cost) |cost| {
            if (self.ctx.host.perfStats()) |stats| stats.unregister(cost);
        }
        c.luaL_unref(self.vm.state, c.LUA_REGISTRYINDEX, self.mod_ref);
        self.ctx.deinit();
        self.vm.deinit();
        self.gpa.free(self.name);
        self.* = undefined;
    }

    /// Run the entry point implied by `run_at`, passing the SDK table.
    pub fn start(self: *ModInstance) Error!void {
        _ = c.lua_rawgeti(self.vm.state, c.LUA_REGISTRYINDEX, self.mod_ref);
        defer c.lua_settop(self.vm.state, -2);

        if (!self.vm.pushFunctionField(-1, self.run_at.entryPoint())) {
            // The loader already rejected a missing entry point, so this
            // means the mod table was mutated after load.
            return error.MissingEntryPoint;
        }
        sdk.push(self.vm.state, &self.ctx, self.permissions);
        self.vm.call(1) catch |err| {
            // The message is the author's only clue (a params typo, a bad
            // value); log it under the mod's name before it is dropped.
            self.ctx.host.log(self.name, .err, self.vm.lastError());
            return err;
        };
    }

    /// Fire `event` at every handler this mod registered for it.
    ///
    /// `payload` populates the event table handlers receive. Errors are
    /// reported through the host and swallowed: one bad handler must not
    /// stop the others, nor reach the game. Each error counts against the
    /// mod (see the module doc); once disabled, this returns immediately.
    pub fn fire(self: *ModInstance, event: hooks.Event, payload: Payload) void {
        if (self.disabled) return;
        for (self.ctx.hooks.subscriptions.items) |sub| {
            if (sub.event != event) continue;

            hooks.pushHandler(self.vm.state, sub.ref);
            payload.push(self.vm.state);

            const t0: u64 = if (self.cost != null) self.ctx.host.perfStats().?.clock() else 0;
            defer if (self.cost) |cost| cost.record(self.ctx.host.perfStats().?.clock() -| t0);

            self.vm.call(1) catch |err| {
                const msg = self.vm.lastError();
                self.ctx.host.log(self.name, .err, msg);
                c.lua_settop(self.vm.state, -2); // drop the error object
                self.strike(err);
                if (self.disabled) return;
            };
        }
    }

    /// Whether the mod still receives events.
    pub fn isActive(self: *const ModInstance) bool {
        return !self.disabled;
    }

    /// Record one handler failure and apply the kill policy.
    fn strike(self: *ModInstance, err: vm_mod.Error) void {
        self.strikes += 1;
        const reason: ?[]const u8 = switch (err) {
            error.BudgetExceeded => "handler exceeded its instruction budget",
            else => if (self.strikes >= max_strikes) "too many handler errors" else null,
        };
        const why = reason orelse return;
        self.disabled = true;
        var buf: [256]u8 = undefined;
        const line = std.fmt.bufPrint(
            &buf,
            "mod disabled: {s} ({d} error(s)); it will receive no further events",
            .{ why, self.strikes },
        ) catch "mod disabled";
        self.ctx.host.log(self.name, .warn, line);
    }

    /// Fields an event table carries. Kept as an explicit union rather than
    /// a generic marshaller so every field a mod can see is visible here.
    pub const Payload = union(enum) {
        none,
        rune_gain: struct { amount: i64 },

        fn push(self: Payload, state: *c.lua_State) void {
            switch (self) {
                .none => c.lua_createtable(state, 0, 0),
                .rune_gain => |p| {
                    c.lua_createtable(state, 0, 1);
                    c.lua_pushinteger(state, p.amount);
                    c.lua_setfield(state, -2, "amount");
                },
            }
        }
    };
};

/// Load `source` and prepare it to run against `host`.
pub fn load(
    gpa: std.mem.Allocator,
    source: []const u8,
    chunk_name: [:0]const u8,
    host: host_mod.Host,
) Error!*ModInstance {
    var loaded = try loader.loadSource(source, chunk_name);
    errdefer loaded.deinit();

    const name = try gpa.dupe(u8, loaded.manifest.name);
    errdefer gpa.free(name);

    // The mod table is on top of the VM stack; stash it in the registry so
    // dispatch can retrieve it later.
    const mod_ref = c.luaL_ref(loaded.vm.state, c.LUA_REGISTRYINDEX);

    // Heap-allocated because the SDK context is referenced by pointer from
    // every bound Lua function; it must not move.
    const self = try gpa.create(ModInstance);
    self.* = .{
        .gpa = gpa,
        .vm = loaded.vm,
        .name = name,
        .run_at = loaded.manifest.run_at,
        .permissions = loaded.manifest.permissions,
        .ctx = sdk.Context.init(gpa, name, host),
        .mod_ref = mod_ref,
    };
    // Cost accounting is keyed by the owned name copy, which lives as long
    // as the instance does.
    if (host.perfStats()) |stats| self.cost = stats.register(self.name);
    return self;
}

pub fn destroy(self: *ModInstance) void {
    const gpa = self.gpa;
    self.deinit();
    gpa.destroy(self);
}

const testing = std.testing;
const fixtures = struct {
    const hello_launch = @embedFile("../lua/fixtures/hello_launch.lua");
    const rune_counter = @embedFile("../lua/fixtures/rune_counter.lua");
    const bad_sandbox = @embedFile("../lua/fixtures/bad_sandbox.lua");
};

test "hello_launch runs its entry point and logs through the SDK" {
    var capture = host_mod.CaptureHost.init(testing.allocator);
    defer capture.deinit();

    const m = try load(testing.allocator, fixtures.hello_launch, "=hello_launch.lua", capture.host());
    defer destroy(m);

    try m.start();

    try testing.expect(capture.contains("hello from a launch mod"));
    try testing.expectEqualStrings("hello-launch", capture.lines.items[0].mod_name);
}

test "rune_counter subscribes and accumulates across events" {
    var capture = host_mod.CaptureHost.init(testing.allocator);
    defer capture.deinit();

    const m = try load(testing.allocator, fixtures.rune_counter, "=rune_counter.lua", capture.host());
    defer destroy(m);

    try m.start();
    try testing.expectEqual(@as(usize, 1), m.ctx.hooks.count(.on_rune_gain));

    m.fire(.on_rune_gain, .{ .rune_gain = .{ .amount = 100 } });
    m.fire(.on_rune_gain, .{ .rune_gain = .{ .amount = 50 } });

    // State persists in the handler's upvalue between firings.
    try testing.expect(capture.contains("gained 100 runes (session total 100)"));
    try testing.expect(capture.contains("gained 50 runes (session total 150)"));
}

test "an event a mod did not subscribe to fires nothing" {
    var capture = host_mod.CaptureHost.init(testing.allocator);
    defer capture.deinit();

    const m = try load(testing.allocator, fixtures.rune_counter, "=rune_counter.lua", capture.host());
    defer destroy(m);

    try m.start();
    m.fire(.on_death, .none);

    try testing.expectEqual(@as(usize, 0), capture.lines.items.len);
}

test "dispatch leaves no stack residue" {
    var capture = host_mod.CaptureHost.init(testing.allocator);
    defer capture.deinit();

    const m = try load(testing.allocator, fixtures.rune_counter, "=rune_counter.lua", capture.host());
    defer destroy(m);

    try m.start();
    const before = m.vm.stackDepth();
    m.fire(.on_rune_gain, .{ .rune_gain = .{ .amount = 1 } });
    try testing.expectEqual(before, m.vm.stackDepth());
}

test "bad_sandbox fails at its entry point instead of escaping" {
    var capture = host_mod.CaptureHost.init(testing.allocator);
    defer capture.deinit();

    const m = try load(testing.allocator, fixtures.bad_sandbox, "=bad_sandbox.lua", capture.host());
    defer destroy(m);

    // It declares no permissions, so it gets an empty SDK table and dies on
    // the first os.execute — the sandbox denying, not the engine crashing.
    try testing.expectError(error.RuntimeError, m.start());
}

test "a mod cannot reach an SDK module it did not declare" {
    var capture = host_mod.CaptureHost.init(testing.allocator);
    defer capture.deinit();

    // Declares log but not hooks: sdk.hooks must be nil.
    const src =
        \\local mod = {
        \\  name = "narrow", version = "1.0.0",
        \\  run_at = "launch", permissions = { "log" },
        \\}
        \\function mod.on_launch(sdk)
        \\  assert(sdk.log ~= nil, "log should be granted")
        \\  assert(sdk.hooks == nil, "hooks must not be granted")
        \\  sdk.log.info("permission gating holds")
        \\end
        \\return mod
    ;
    const m = try load(testing.allocator, src, "=narrow.lua", capture.host());
    defer destroy(m);

    try m.start();
    try testing.expect(capture.contains("permission gating holds"));
}

test "an unknown event name is rejected at subscribe time" {
    var capture = host_mod.CaptureHost.init(testing.allocator);
    defer capture.deinit();

    const src =
        \\local mod = {
        \\  name = "typo", version = "1.0.0",
        \\  run_at = "events", permissions = { "hooks" },
        \\}
        \\function mod.setup(sdk)
        \\  sdk.hooks.on("on_rune_gian", function() end)
        \\end
        \\return mod
    ;
    const m = try load(testing.allocator, src, "=typo.lua", capture.host());
    defer destroy(m);

    try testing.expectError(error.RuntimeError, m.start());
}

test "a handler that errors is reported and does not stop the others" {
    var capture = host_mod.CaptureHost.init(testing.allocator);
    defer capture.deinit();

    const src =
        \\local mod = {
        \\  name = "mixed", version = "1.0.0",
        \\  run_at = "events", permissions = { "hooks", "log" },
        \\}
        \\function mod.setup(sdk)
        \\  sdk.hooks.on("on_death", function() error("boom") end)
        \\  sdk.hooks.on("on_death", function() sdk.log.info("second handler ran") end)
        \\end
        \\return mod
    ;
    const m = try load(testing.allocator, src, "=mixed.lua", capture.host());
    defer destroy(m);

    try m.start();
    m.fire(.on_death, .none);

    try testing.expect(capture.contains("boom"));
    try testing.expect(capture.contains("second handler ran"));
}

test "a runaway handler disables the mod on the spot" {
    var capture = host_mod.CaptureHost.init(testing.allocator);
    defer capture.deinit();

    const src =
        \\local mod = {
        \\  name = "spin", version = "1.0.0",
        \\  run_at = "events", permissions = { "hooks", "log" },
        \\}
        \\function mod.setup(sdk)
        \\  sdk.hooks.on("on_present", function() while true do end end)
        \\  sdk.hooks.on("on_present", function() sdk.log.info("later handler ran") end)
        \\end
        \\return mod
    ;
    const m = try load(testing.allocator, src, "=spin.lua", capture.host());
    defer destroy(m);

    try m.start();
    m.fire(.on_present, .none);
    try testing.expect(!m.isActive());
    try testing.expect(capture.contains("mod disabled: handler exceeded its instruction budget"));
    // Disabling stops the rest of this dispatch too, not only later ones.
    try testing.expect(!capture.contains("later handler ran"));

    // Further events are ignored: no new log lines.
    const n = capture.lines.items.len;
    m.fire(.on_present, .none);
    try testing.expectEqual(n, capture.lines.items.len);
}

test "handler errors strike the mod and the last strike disables it" {
    var capture = host_mod.CaptureHost.init(testing.allocator);
    defer capture.deinit();

    const src =
        \\local mod = {
        \\  name = "flaky", version = "1.0.0",
        \\  run_at = "events", permissions = { "hooks" },
        \\}
        \\function mod.setup(sdk)
        \\  sdk.hooks.on("on_death", function() error("boom") end)
        \\end
        \\return mod
    ;
    const m = try load(testing.allocator, src, "=flaky.lua", capture.host());
    defer destroy(m);

    try m.start();
    var i: u32 = 1;
    while (i < ModInstance.max_strikes) : (i += 1) {
        m.fire(.on_death, .none);
        try testing.expect(m.isActive());
        try testing.expectEqual(i, m.strikes);
    }
    try testing.expect(!capture.contains("mod disabled"));

    m.fire(.on_death, .none);
    try testing.expect(!m.isActive());
    try testing.expect(capture.contains("mod disabled: too many handler errors"));

    // The disable line is logged once; a disabled mod is silent afterwards.
    const n = capture.lines.items.len;
    m.fire(.on_death, .none);
    m.fire(.on_death, .none);
    try testing.expectEqual(n, capture.lines.items.len);
}

test "a healthy handler never accrues strikes" {
    var capture = host_mod.CaptureHost.init(testing.allocator);
    defer capture.deinit();

    const m = try load(testing.allocator, fixtures.rune_counter, "=rune_counter.lua", capture.host());
    defer destroy(m);

    try m.start();
    for (0..ModInstance.max_strikes * 4) |_| m.fire(.on_rune_gain, .{ .rune_gain = .{ .amount = 1 } });
    try testing.expectEqual(@as(u32, 0), m.strikes);
    try testing.expect(m.isActive());
}

test "a runaway handler is cut off by the budget, not left spinning" {
    var capture = host_mod.CaptureHost.init(testing.allocator);
    defer capture.deinit();

    const src =
        \\local mod = {
        \\  name = "spin", version = "1.0.0",
        \\  run_at = "events", permissions = { "hooks" },
        \\}
        \\function mod.setup(sdk)
        \\  sdk.hooks.on("on_present", function() while true do end end)
        \\end
        \\return mod
    ;
    const m = try load(testing.allocator, src, "=spin.lua", capture.host());
    defer destroy(m);

    try m.start();
    m.fire(.on_present, .none); // must return rather than hang
    try testing.expect(capture.contains("budget"));
}

test "each mod's SDK context is its own" {
    var capture = host_mod.CaptureHost.init(testing.allocator);
    defer capture.deinit();

    const a = try load(testing.allocator, fixtures.rune_counter, "=a.lua", capture.host());
    defer destroy(a);
    const b = try load(testing.allocator, fixtures.rune_counter, "=b.lua", capture.host());
    defer destroy(b);

    try a.start();
    try b.start();

    // Firing at one must not run the other's handler.
    a.fire(.on_rune_gain, .{ .rune_gain = .{ .amount = 7 } });
    try testing.expectEqual(@as(usize, 1), capture.lines.items.len);
    try testing.expect(capture.contains("session total 7"));
}

test "unloading a mod releases its handler refs" {
    var capture = host_mod.CaptureHost.init(testing.allocator);
    defer capture.deinit();

    // Load, subscribe and destroy repeatedly: a leaked luaL_ref or a
    // leaked allocation would show up as a testing.allocator failure or
    // unbounded registry growth.
    for (0..50) |_| {
        const m = try load(testing.allocator, fixtures.rune_counter, "=r.lua", capture.host());
        try m.start();
        m.fire(.on_rune_gain, .{ .rune_gain = .{ .amount = 1 } });
        destroy(m);
    }
}

test "a mod with no permissions gets an empty sdk table" {
    var capture = host_mod.CaptureHost.init(testing.allocator);
    defer capture.deinit();

    const src =
        \\local mod = {
        \\  name = "none", version = "1.0.0",
        \\  run_at = "launch", permissions = {},
        \\}
        \\function mod.on_launch(sdk)
        \\  assert(next(sdk) == nil, "sdk table should be empty")
        \\end
        \\return mod
    ;
    const m = try load(testing.allocator, src, "=none.lua", capture.host());
    defer destroy(m);
    try m.start();
}
