//! The SDK: the surface a mod sees, and the dispatch that drives it.

const std = @import("std");

pub const host = @import("host.zig");
pub const sdk = @import("sdk.zig");
pub const log = @import("log.zig");
pub const hooks = @import("hooks.zig");
pub const params = @import("params.zig");
pub const perf = @import("perf.zig");
pub const store = @import("store.zig");
pub const ui = @import("ui.zig");
pub const screen = @import("screen.zig");
pub const stubs = @import("stubs.zig");
pub const mod_instance = @import("mod_instance.zig");

pub const Host = host.Host;
pub const CallbackHost = host.CallbackHost;
pub const CaptureHost = host.CaptureHost;
pub const Context = sdk.Context;
pub const Event = hooks.Event;
pub const ModInstance = mod_instance.ModInstance;
pub const load = mod_instance.load;
pub const destroy = mod_instance.destroy;

test {
    _ = host;
    _ = sdk;
    _ = log;
    _ = hooks;
    _ = params;
    _ = perf;
    _ = store;
    _ = ui;
    _ = screen;
    _ = stubs;
    _ = mod_instance;
}
