//! Declarative mod description types.
//!
//! Deliberately dependency-free: mod specs in `mods/` and the engine in
//! `src/modspec.zig` both import this, so it must not pull in either.

pub const Value = union(enum) {
    int: i64,
    float: f64,
};

pub const Patch = struct {
    /// Param file basename, e.g. "CharaInitParam.param".
    param_file: []const u8,
    row: u32,
    field: []const u8,
    value: Value,
};

pub const Spec = struct {
    name: []const u8,
    description: []const u8 = "",
    patches: []const Patch,
};
