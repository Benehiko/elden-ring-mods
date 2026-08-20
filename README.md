# elden-ring-mods

Mods for Elden Ring on Linux, written in Lua, that run in the live game.

This repository is what a mod author writes *against*: the SDK stubs, ten
worked examples, the scripting reference, and the param field definitions.
It builds nothing — the engine that runs mods is a separate, closed-source
project, published on the [Releases](../../releases) page.

**The game install is only ever read.** Nothing here writes to it, ever.

---

## I just want to play with mods

Download the engine from [Releases](../../releases), point it at a directory
of `.lua` mods, and play. No toolchain, no build, no ModEngine.

**→ [docs/install.md](docs/install.md)** is the setup page.

The release includes `ermod-engine` and the two Windows binaries it injects.
Those are built from a **closed-source** repository, and the mod front end —
the Lua sandbox and the `sdk.*` bindings — is part of them. What this
repository publishes is the surface those bindings present:
`stubs/ermod.lua` is generated from the engine's binding tables, so it lists
every `sdk.*` function a mod can call, exhaustively. See
[The published surface](#the-published-surface).

## I want to write a mod

Mods are **Lua files**. One file per mod, sandboxed, hot-reloaded in the
running game.

```lua
local mod = {
  name = "my-mod",
  version = "1.0.0",
  run_at = "launch",
  permissions = { "params", "log" },
}

function mod.on_launch(sdk)
  local row = sdk.params.row("CharaInitParam", 3000)
  row.soulLv = 60
  sdk.log.info("vagabond starts at level 60")
end

return mod
```

A mod declares the SDK modules it needs and receives exactly those — an
undeclared module is absent from `sdk` entirely, so it cannot be reached
rather than merely refused.

**→ [docs/scripting.md](docs/scripting.md)** is the guide, and
`stubs/ermod.lua` gives editor completion by cloning this repo — nothing to
build.

Drop the file in your mods directory and it loads on the next frame.

**→ [`examples/`](examples/)** is ten worked examples, one file each, from the
smallest mod that does anything to a HUD, an in-game settings screen and
`level60.lua` — the reference gameplay mod. Start with
[`hello_launch.lua`](examples/hello_launch.lua); the
[index](examples/README.md) gives the reading order.

## The published surface

This repository holds four things, and nothing that compiles.

| | |
| --- | --- |
| [`stubs/ermod.lua`](stubs/ermod.lua) | LuaLS type annotations for the whole SDK, generated from the engine's binding tables. Point a language server here for completion — nothing to build. |
| [`examples/`](examples/) | Ten worked mods, one file each, one per SDK slice. Also the engine's own test corpus, so an example that stops working fails a build there before it is republished here. |
| [`paramdefs/`](paramdefs/) | Paramdex PARAMDEF XML: the field layout of the game's param rows, which is where names like `soulLv` and `baseVit` come from. The engine generates its field tables from these. |
| [`docs/`](docs/) | The scripting reference, the install page, and the design notes. |

The stubs are the honest description of what a mod can do. They are generated
from the binding tables themselves, so a binding that exists and is missing
from the stubs is a bug the generator catches — which makes them a *complete
enumeration* of the surface. What they are not is a bound you can verify by
reading: the implementations live in the closed engine. The sandbox's
behaviour is still yours to test from outside, and is documented in
[docs/scripting.md](docs/scripting.md): `base`, `table`, `string` and `math`
are the only libraries opened, `load`/`dofile`/`require` are stripped, and
every call into Lua runs under an instruction budget.

## Writing a mod in Lua

A mod is a table with a manifest and an entry point. Drop the file in your
mods directory and it loads on the next frame. This one raises the Vagabond
to level 60 — a cut-down [`examples/level60.lua`](examples/level60.lua):

```lua
local mod = {
  name = "level60",
  version = "1.0.0",
  run_at = "launch",
  permissions = { "params", "log" },
}

function mod.on_launch(sdk)
  local row = sdk.params.row("CharaInitParam", 3000)   -- nil if no such row
  sdk.log.info("Vagabond was level " .. row.soulLv)
  row.soulLv = 60
end

return mod
```

`permissions` is the whole of what the mod can reach: a module not listed is
not present in the `sdk` table it receives. Field names are the paramdef's own
(`soulLv`, `baseVit`, …), and `.param` on a file name is optional.

The same file runs unchanged either way: live in the game, or applied
offline into a `regulation.bin` with `ermod-engine dev apply`, so a mod can
ship as a file rather than as a script. Offline, though:

- **Only `run_at = "launch"` mods are accepted.** There are no events to fire
  offline, so an event mod is refused rather than silently doing nothing.
- **`params` and `log` are the modules that work.** `ui`, `perf`, `store` and
  `screen` need a running game and report themselves unavailable.
- **Two mods writing one field is an error**, not last-wins: `dev apply` names
  both mods and the field, refuses to pack, and writes no output file. In-game
  the same overlap is a warning, because a hot-reloaded mod rewrites its own
  fields by design.
- **The sandbox and instruction budget are the game's.** `os` and `io` are nil,
  and a mod that cannot finish `on_launch` under budget is cut off here rather
  than in your session.

`dev apply` is deterministic: the same input and mods produce a byte-identical
`regulation.bin` (zero IV, as the game's own file has), so two outputs can be
compared directly.

[docs/scripting.md](docs/scripting.md) is the full reference: the manifest,
both `run_at` kinds, every SDK module, the sandbox and its budgets, and the
author loop in-game as well as offline.

## Author tooling

The commands that check a mod are part of the engine, under its development
tier, because they run the game's own front end on the host — the same loader,
sandbox, manifest rules, instruction budget and SDK modules. So "passes
`check`" means "would load in-game", and `perf`'s numbers come from the real
dispatcher rather than an estimate.

```sh
ermod-engine dev check my_mod.lua other_mod.lua   # syntax, manifest, permissions, entry point
ermod-engine dev perf  my_mod.lua                 # synthetic session; cost per event
ermod-engine dev stubs out.lua                    # regenerate these stubs
ermod-engine dev apply <regulation.bin> <out.bin> <mod>...
```

`check` prints one line per mod and exits 1 if any would fail to load, so it
drops straight into a pre-commit hook or CI. `ermod-engine dev --help` lists
the rest.

## Editor completion

```json
{ "workspace.library": ["path/to/elden-ring-mods/stubs"] }
```

That is the whole setup: clone this repository, point a Lua language server at
`stubs/`, and every `sdk.*` call completes with its types and documentation.

## How regulation.bin is structured

```
regulation.bin
└── AES-256-CBC (community-known key, IV = first 16 bytes)
    └── DCX container (big-endian header, ZSTD since game patch 1.12)
        └── BND4 archive (~54 MB, 194 entries)
            └── *.param files (CharaInitParam, ItemLotParam, ...)
```

The engine reads and writes this chain; `paramdefs/` is what turns the bytes
of a row into named fields.

## Development

This repository has nothing to build. Both generated artefacts come from the
engine and are committed here:

```sh
make -C ../elden-ring-mods-engine stubs       # regenerate stubs/ermod.lua
make -C ../elden-ring-mods-engine paramdefs   # regenerate the engine's field tables
make check-stubs                              # are the committed stubs current?
```

The examples are also the engine's test corpus, and `ermod-engine dev check
--examples` asserts that both copies are byte-identical.

## Safety

Modded play must stay offline; the engine launches the game with Easy Anti-Cheat
absent, running `eldenring.exe` directly rather than the protected launcher. Loading a
modified `regulation.bin` while connected to FromSoftware's servers risks a ban. This
repository contains no game data and no executable code.

## Licence

[Apache-2.0](LICENSE). Chosen over MIT for the explicit patent grant and the
trademark reservation — both worth having for a project built on
reverse-engineered file formats.

That covers everything in this repository. It does not cover the mod front
end: the Lua sandbox, the `sdk.*` binding implementations and the `Host`
interface behind them are part of the closed-source engine. This repository
publishes the *surface* instead — `stubs/ermod.lua`, generated from the
engine's own binding tables, is a complete enumeration of what a mod can
call. That is an exhaustive list, not a readable bound: you can see every
function, but not the implementation behind it. The sandbox's behaviour
stays documented and independently testable — `base`, `table`, `string` and
`math` only, code-loading globals stripped, an instruction budget per call.

Two further things [NOTICE](NOTICE) spells out:

- **Vendored components** keep their own terms — the Paramdex PARAMDEF XML
  in `paramdefs/`.
- **The engine binaries** published on the Releases page are built from a
  separate closed-source repository and are licensed with the release, not
  under Apache-2.0.

ELDEN RING is the property of FromSoftware and Bandai Namco; this project is
unaffiliated, distributes no game data, and never writes to an installation.
