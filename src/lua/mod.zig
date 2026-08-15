//! The Lua subsystem: sandboxed VMs, mod manifests, and the loader that
//! turns a script on disk into a validated, loaded mod.

const std = @import("std");

pub const c = @import("c.zig").c;
pub const vm = @import("vm.zig");
pub const manifest = @import("manifest.zig");
pub const loader = @import("loader.zig");

pub const Vm = vm.Vm;
pub const Manifest = manifest.Manifest;
pub const Permission = manifest.Permission;
pub const RunAt = manifest.RunAt;

test {
    std.testing.refAllDecls(@This());
    _ = vm;
    _ = manifest;
    _ = loader;
}
