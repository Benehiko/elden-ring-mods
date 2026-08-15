//! Raw Lua 5.4 C API.
//!
//! Kept in its own module so everything else imports a single `c` namespace
//! and the vendored headers are included exactly once.

pub const c = @cImport({
    @cInclude("lua.h");
    @cInclude("lauxlib.h");
    @cInclude("lualib.h");
});
