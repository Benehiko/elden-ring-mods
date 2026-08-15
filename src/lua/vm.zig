//! A sandboxed Lua VM: one instance per mod.
//!
//! Per-mod isolation is deliberate — one mod's globals, state and crashes
//! must not reach another, and the engine must be able to kill or reload a
//! single mod without disturbing the rest.
//!
//! The sandbox is opt-out by construction: only `base`, `table`, `string`
//! and `math` are opened, and the dangerous parts of `base` (`dofile`,
//! `load`, `loadstring`, `require`, `collectgarbage`) are removed
//! afterwards. `io`, `os`, `package` and `debug` are never opened at all,
//! so a mod cannot reach the filesystem, spawn processes, or load native
//! code. Filesystem needs go through vetted SDK modules instead.
//!
//! Every call into Lua runs under an instruction budget (`lua_sethook`), so
//! a runaway or merely slow handler is interrupted and reported rather than
//! stalling the game's frame.

const std = @import("std");
const c = @import("c.zig").c;

pub const Error = error{
    OutOfMemory,
    /// The script failed to compile.
    SyntaxError,
    /// The script raised an error while running.
    RuntimeError,
    /// The script exceeded its instruction budget.
    BudgetExceeded,
    /// The script did not return a mod table.
    NotAModTable,
    /// A required manifest field was missing or the wrong type.
    BadManifest,
};

/// Default instruction budget for one call into Lua. Generous enough for
/// real work, small enough that an infinite loop is caught in milliseconds.
pub const default_budget: u32 = 10_000_000;

/// Global names removed from `base` after opening it. Each one is either a
/// way to execute code the sandbox has not vetted, or a handle on engine
/// internals a mod has no business touching.
const stripped_globals = [_][:0]const u8{
    "dofile",
    "load",
    "loadfile",
    "loadstring",
    "require",
    "collectgarbage",
    "rawset",
    "rawget",
    "rawequal",
    "rawlen",
    "getmetatable",
    "setmetatable",
    "print", // mods log through the SDK's `log` module instead
};

pub const Vm = struct {
    state: *c.lua_State,
    /// Set by the instruction hook when the budget runs out, so the error
    /// can be reported as BudgetExceeded rather than a generic runtime error.
    budget_exceeded: bool = false,

    pub fn init() Error!Vm {
        const state = c.luaL_newstate() orelse return error.OutOfMemory;
        errdefer c.lua_close(state);

        // Open only the safe libraries. luaL_openlibs would pull in io, os,
        // package and debug, which is exactly what the sandbox forbids.
        openLib(state, c.LUA_GNAME, c.luaopen_base);
        openLib(state, c.LUA_TABLIBNAME, c.luaopen_table);
        openLib(state, c.LUA_STRLIBNAME, c.luaopen_string);
        openLib(state, c.LUA_MATHLIBNAME, c.luaopen_math);

        for (stripped_globals) |name| {
            c.lua_pushnil(state);
            _ = c.lua_setglobal(state, name.ptr);
        }

        return .{ .state = state };
    }

    pub fn deinit(self: *Vm) void {
        c.lua_close(self.state);
        self.* = undefined;
    }

    fn openLib(state: *c.lua_State, name: [*:0]const u8, func: c.lua_CFunction) void {
        c.luaL_requiref(state, name, func, 1);
        c.lua_settop(state, -2); // pop the module table requiref left behind
    }

    /// Install the instruction-count hook for the next call into Lua.
    fn armBudget(self: *Vm, budget: u32) void {
        self.budget_exceeded = false;
        // The hook needs to find this Vm; stash the pointer in the registry
        // rather than a global so mods cannot reach or overwrite it.
        c.lua_pushlightuserdata(self.state, self);
        c.lua_setfield(self.state, c.LUA_REGISTRYINDEX, vm_registry_key);
        c.lua_sethook(self.state, budgetHook, c.LUA_MASKCOUNT, @intCast(budget));
    }

    fn disarmBudget(self: *Vm) void {
        c.lua_sethook(self.state, null, 0, 0);
    }

    const vm_registry_key = "ermod_vm";

    fn budgetHook(state: ?*c.lua_State, _: ?*c.lua_Debug) callconv(.c) void {
        const s = state orelse return;
        _ = c.lua_getfield(s, c.LUA_REGISTRYINDEX, vm_registry_key);
        const ptr = c.lua_touserdata(s, -1);
        c.lua_settop(s, -2);
        if (ptr) |p| {
            const vm: *Vm = @ptrCast(@alignCast(p));
            vm.budget_exceeded = true;
        }
        _ = c.luaL_error(s, "instruction budget exceeded");
    }

    /// Load `source` as a chunk named `chunk_name` and run it, expecting it
    /// to return a mod table. The table is left on the stack.
    pub fn loadModule(self: *Vm, source: []const u8, chunk_name: [:0]const u8) Error!void {
        // luaL_loadbuffer is a macro whose NULL argument translates as
        // ?*anyopaque, so call the underlying function with a typed null.
        if (c.luaL_loadbufferx(
            self.state,
            source.ptr,
            source.len,
            chunk_name.ptr,
            null,
        ) != c.LUA_OK) {
            return error.SyntaxError;
        }

        self.armBudget(default_budget);
        defer self.disarmBudget();

        if (c.lua_pcallk(self.state, 0, 1, 0, 0, null) != c.LUA_OK) {
            return if (self.budget_exceeded) error.BudgetExceeded else error.RuntimeError;
        }
        if (c.lua_type(self.state, -1) != c.LUA_TTABLE) return error.NotAModTable;
    }

    /// Call the function on top of the stack with `nargs` arguments below
    /// it, discarding results. Runs under the instruction budget, so a slow
    /// or runaway handler is interrupted rather than stalling the caller.
    pub fn call(self: *Vm, nargs: c_int) Error!void {
        self.armBudget(default_budget);
        defer self.disarmBudget();

        if (c.lua_pcallk(self.state, nargs, 0, 0, 0, null) != c.LUA_OK) {
            return if (self.budget_exceeded) error.BudgetExceeded else error.RuntimeError;
        }
    }

    /// Push field `key` of the table at `index`; true if it is a function.
    pub fn pushFunctionField(self: *Vm, index: c_int, key: [:0]const u8) bool {
        if (c.lua_getfield(self.state, index, key.ptr) == c.LUA_TFUNCTION) return true;
        c.lua_settop(self.state, -2);
        return false;
    }

    /// Current stack depth. Used to assert dispatch leaves no residue.
    pub fn stackDepth(self: *Vm) c_int {
        return c.lua_gettop(self.state);
    }

    /// The error message left on the stack by a failed load or call.
    /// Only valid until the next stack operation.
    pub fn lastError(self: *Vm) []const u8 {
        var len: usize = 0;
        const ptr = c.lua_tolstring(self.state, -1, &len) orelse return "(no error message)";
        return ptr[0..len];
    }

    /// Read a required string field from the table on top of the stack.
    /// The returned slice borrows Lua-owned memory: copy it if it must
    /// outlive the table.
    pub fn tableString(self: *Vm, key: [:0]const u8) Error![]const u8 {
        if (c.lua_getfield(self.state, -1, key.ptr) != c.LUA_TSTRING) {
            c.lua_settop(self.state, -2);
            return error.BadManifest;
        }
        defer c.lua_settop(self.state, -2);
        var len: usize = 0;
        const ptr = c.lua_tolstring(self.state, -1, &len) orelse return error.BadManifest;
        return ptr[0..len];
    }

    /// True if the table on top of the stack has a function field `key`.
    pub fn hasFunction(self: *Vm, key: [:0]const u8) bool {
        const is_fn = c.lua_getfield(self.state, -1, key.ptr) == c.LUA_TFUNCTION;
        c.lua_settop(self.state, -2);
        return is_fn;
    }

    /// True if the global `name` is nil — i.e. the sandbox removed it, or it
    /// was never opened. Used by the sandbox tests.
    pub fn globalIsNil(self: *Vm, name: [:0]const u8) bool {
        const is_nil = c.lua_getglobal(self.state, name.ptr) == c.LUA_TNIL;
        c.lua_settop(self.state, -2);
        return is_nil;
    }

    /// Run a bare chunk for its side effects. Test helper.
    pub fn eval(self: *Vm, source: [:0]const u8) Error!void {
        if (c.luaL_loadbufferx(self.state, source.ptr, source.len, "=eval", null) != c.LUA_OK) {
            return error.SyntaxError;
        }
        self.armBudget(default_budget);
        defer self.disarmBudget();
        if (c.lua_pcallk(self.state, 0, 0, 0, 0, null) != c.LUA_OK) {
            return if (self.budget_exceeded) error.BudgetExceeded else error.RuntimeError;
        }
    }
};

test "vm opens and closes" {
    var vm = try Vm.init();
    defer vm.deinit();
}

test "safe libraries are available" {
    var vm = try Vm.init();
    defer vm.deinit();
    try vm.eval("assert(string.format('%d', 1) == '1')");
    try vm.eval("assert(math.floor(1.5) == 1)");
    try vm.eval("assert(#table.concat({'a','b'}) == 2)");
}

test "sandbox denies io, os, package and debug" {
    var vm = try Vm.init();
    defer vm.deinit();
    for ([_][:0]const u8{ "io", "os", "package", "debug" }) |name| {
        try std.testing.expect(vm.globalIsNil(name));
    }
}

test "sandbox strips code-loading globals" {
    var vm = try Vm.init();
    defer vm.deinit();
    for ([_][:0]const u8{ "load", "loadfile", "dofile", "require" }) |name| {
        try std.testing.expect(vm.globalIsNil(name));
    }
}

test "runaway loop hits the instruction budget" {
    var vm = try Vm.init();
    defer vm.deinit();
    try std.testing.expectError(error.BudgetExceeded, vm.eval("while true do end"));
}

test "loadModule rejects a script that returns no table" {
    var vm = try Vm.init();
    defer vm.deinit();
    try std.testing.expectError(error.NotAModTable, vm.loadModule("return 42", "=t"));
}

test "loadModule reports syntax errors" {
    var vm = try Vm.init();
    defer vm.deinit();
    try std.testing.expectError(error.SyntaxError, vm.loadModule("this is not lua", "=t"));
}

test "unopened libraries are unreachable, not merely hidden" {
    var vm = try Vm.init();
    defer vm.deinit();
    // liolib/loslib/loadlib are compiled into the binary but never opened,
    // so there must be no path back to them from inside a mod.
    try std.testing.expect(vm.globalIsNil("coroutine"));
    try std.testing.expectError(error.RuntimeError, vm.eval("return package.loadlib"));
    try std.testing.expectError(error.RuntimeError, vm.eval("return require('io')"));
}

test "string metatable cannot be used to reach stripped globals" {
    var vm = try Vm.init();
    defer vm.deinit();
    // getmetatable is stripped, and debug is never opened, so the classic
    // sandbox escape through ('').__index is closed.
    try std.testing.expectError(error.RuntimeError, vm.eval("return getmetatable('').__index"));
    try std.testing.expectError(error.RuntimeError, vm.eval("return debug.getregistry()"));
}
