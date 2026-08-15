# Vendored Lua

Lua 5.4.7, unmodified sources from the upstream release tarball.

- Upstream: <https://www.lua.org/ftp/lua-5.4.7.tar.gz>
- SHA-256: `9fbf5e28ef86c69858f6d3d34eccc32e911c1a28b4120ff3e84aaa70cfbf1e30`
- License: MIT, see `LICENSE`

Only `src/*.c` and `src/*.h` are vendored. The standalone interpreter
(`lua.c`) and compiler (`luac.c`) mains are deliberately omitted — the
engine embeds the library, it does not ship an interpreter.

`build.zig` compiles these directly, so Lua is not a system dependency and
cross-compilation to `x86_64-windows-gnu` keeps working.

## Updating

Replace `*.c`/`*.h` from a new tarball, update the version and hash above,
and run `zig build test`. Do not patch the sources in place: local changes
would be silently lost on the next update. If a change is genuinely needed,
apply it in `src/runtime/lua/` around the C API instead.
