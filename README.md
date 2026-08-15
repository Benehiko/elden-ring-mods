# elden-ring-mods

Zig tooling for building Elden Ring gameplay mods (starting level, starting gear, item
lots) without ever touching the installed game. The tool reads `regulation.bin` from the
Steam install, applies declarative patches, and writes a modified copy into a mod
directory that [Mod Engine 2](https://github.com/soulsmods/ModEngine2) loads at runtime.

**The game install is only ever read.** All output goes to `mod/`; the vanilla install
stays byte-for-byte untouched.

See [docs/architecture.md](docs/architecture.md) for the design,
[docs/deploy.md](docs/deploy.md) for running it through Proton, and
[docs/tasks.md](docs/tasks.md) for status.

This repo also holds **`ermod-lua`**, the mod front end shared with the Lua
mod engine — see [The `ermod-lua` package](#the-ermod-lua-package) below.

## The `ermod-lua` package

`src/ermod_lua.zig` is a Zig package: everything a Lua mod *is*, independent
of where it runs.

| | |
| --- | --- |
| `src/lua/` | the sandboxed Lua 5.4 VM, the instruction budget, manifest parsing, the mod loader |
| `src/sdk/` | every `sdk.*` binding a mod calls — `log`, `params`, `hooks`, `perf`, `store`, `ui`, `screen` — and `host.zig`, the interface they call back into |
| `src/paramview.zig` | one PARAM table as a view over its bytes, live or unpacked |
| `src/param_writes.zig` | the write ledger: who wrote which field, and conflicts between mods |
| `src/perf.zig`, `src/ui_backend.zig`, `src/store_format.zig`, `src/screen.zig`, `src/image.zig` | the pure data and interfaces those bindings are defined over |
| `vendor/lua/` | Lua 5.4.7, compiled by `build.zig` (no system dependency) |
| `test/mods/` | Lua fixtures exercising one SDK slice each; also the engine's |

A mod's whole blast radius is the vtable in `src/sdk/host.zig`. If a
capability is not a function on it, no mod can reach it — and that file is
here, in the open, rather than inside the closed engine. The two consumers
supply the other half:

- **`ermod` (this repo)** implements `Host` over an unpacked
  `regulation.bin`, so `ermod apply` can run a `.lua` mod offline.
- **the engine** implements it over the running game — live param tables,
  the ImGui overlay, frame capture, event hooks — and consumes this package
  through its `build.zig.zon`.

Same bindings, same sandbox, same paramdefs, both ways. That is what makes
"author live, ship offline" one code path rather than two.

## Requirements

- Zig 0.16
- libzstd (system library, for DCX compression)
- Python 3 (only to regenerate paramdef tables; not needed for a normal build)

## Quick start

```sh
make build
make apply       # writes mod/regulation.bin with level60 + class-gear
make selftest    # golden checks against your real install
```

Then point Mod Engine 2 at the `mod/` directory — see [docs/deploy.md](docs/deploy.md).

## Included mods

| Mod | Effect |
| --- | --- |
| `level60` | Every starting class begins at level 60, with a stat spread that keeps its identity (Hero 37 Str, Astrologer 38 Int, and so on). |
| `class-gear` | Each class gains a second weapon, a shield or catalyst, and consumables; the Wretch also gets a full armour set. |

```sh
./zig-out/bin/ermod mods                    # list them
make apply MODS="level60"                   # pick a subset
```

## CLI

```
ermod decrypt <regulation.bin> <out.dcx>          Decrypt only
ermod encrypt <in.dcx> <out.bin>                  Encrypt only
ermod unpack  <regulation.bin> <out.bnd>          Decrypt + decompress to BND4
ermod pack    <in.bnd> <template.bin> <out.bin>   Compress + encrypt back
ermod ls      <regulation.bin>                    List the 194 param files
ermod extract <regulation.bin> <name> <out>       Extract one param
ermod show    <regulation.bin> <row> [field]      Inspect CharaInitParam rows
ermod mods                                        List available mods
ermod verify-ids <regulation.bin>                 Check mod item IDs exist
ermod selftest   <regulation.bin>                 Golden checks against the game
ermod apply   <regulation.bin> <out.bin> <mod>... Apply mods
```

`ermod show` is handy for exploring: row IDs 3000–3009 are the ten starting classes.

```sh
GAME="$HOME/.local/share/Steam/steamapps/common/ELDEN RING/Game"
./zig-out/bin/ermod show "$GAME/regulation.bin" 3000 base   # Vagabond's base stats
```

## Writing a mod

Mods are Zig files in `mods/` that export a `spec`, so stat tables are computed at
comptime and checked by unit tests:

```zig
const modspec = @import("spec");

pub const spec = modspec.Spec{
    .name = "example",
    .description = "What this mod does.",
    .patches = &.{
        .{ .param_file = "CharaInitParam.param", .row = 3000, .field = "soulLv", .value = .{ .int = 60 } },
    },
};
```

Register it in `mods/mods.zig` and in `available_mods` in `src/main.zig`. Mods compose;
two patches writing the same param/row/field are rejected rather than silently
last-wins. Field names come from the paramdefs — `ermod show` prints the ones a row
actually uses.

## How regulation.bin is structured

```
regulation.bin
└── AES-256-CBC (community-known key, IV = first 16 bytes)
    └── DCX container (big-endian header, ZSTD since game patch 1.12)
        └── BND4 archive (~54 MB, 194 entries)
            └── *.param files (CharaInitParam, ItemLotParam, ...)
```

## Development

```sh
make test        # unit tests (no game data needed)
make selftest    # golden checks against the real install
make paramdefs   # regenerate field tables from vendored Paramdex XML
make hooks       # activate the pre-commit hook (fmt check + build)
```

Bypass the hook with `git commit --no-verify` if needed.

## Safety

Modded play must stay offline; Mod Engine 2 disables Easy Anti-Cheat for you. Loading a
modified `regulation.bin` while connected to FromSoftware's servers risks a ban. This
repo contains only tooling and mod definitions — no game data.
