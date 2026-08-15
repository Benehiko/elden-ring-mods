//! `ermod-lua` — the mod front end, shared by the offline packer in this
//! repo and the injected runtime in the engine repo.
//!
//! Everything a mod *is* lives here: the Lua VM and its sandbox, the
//! manifest, the loader, every SDK binding a mod calls, and the `Host`
//! interface those bindings call back into. Everything a mod *touches in a
//! running game* — the `SoloParamRepository` walk, the ImGui overlay, the
//! frame-capture path, the hooks — is a `Host` implementation, and lives in
//! whichever binary supplies it: `ermod apply` here, the runtime there.
//!
//! That split is the trust boundary made readable. The full blast radius of
//! the sandbox is `sdk/host.zig`'s vtable: if a capability is not a function
//! on it, no mod can reach it, and this repo is public.
//!
//! The dependency can only point one way — the engine repo is private, so
//! the shared half lives in the open one and the engine consumes it as a Zig
//! package.

pub const c = @import("lua/c.zig").c;
pub const vm = @import("lua/vm.zig");
pub const manifest = @import("lua/manifest.zig");
pub const loader = @import("lua/loader.zig");
pub const lua = @import("lua/mod.zig");

pub const sdk = @import("sdk/mod.zig");
pub const host = @import("sdk/host.zig");

pub const paramview = @import("paramview.zig");
pub const param_defs = @import("params/defs.zig");
pub const paramdef = @import("paramdef.zig");
pub const param_writes = @import("param_writes.zig");

pub const perf = @import("perf.zig");
pub const ui_backend = @import("ui_backend.zig");
pub const store_format = @import("store_format.zig");
pub const screen = @import("screen.zig");
pub const image = @import("image.zig");

test {
    // Pull every module of the package into the test binary. Zig only runs
    // tests in files reachable from the root, and the root is a namespace of
    // re-exports, so each one is named here explicitly.
    _ = vm;
    _ = manifest;
    _ = loader;
    _ = sdk;
    _ = host;
    _ = paramview;
    _ = param_defs;
    _ = paramdef;
    _ = param_writes;
    _ = perf;
    _ = ui_backend;
    _ = store_format;
    _ = screen;
    _ = image;
}
