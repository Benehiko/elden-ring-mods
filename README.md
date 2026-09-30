# elden-ring-mods

Mods for Elden Ring on Linux and macOS, written in Lua, that run in the live
game.

This repository is what a mod author writes *against*: the SDK stubs, eleven
worked examples, the scripting reference, and the param field definitions.
It builds nothing. The engine that runs mods is a separate, closed-source
project, published on the [Releases](../../releases) page.

**The game install is only ever read.** Nothing here writes to it, ever.

**Easy Anti-Cheat never runs, and no modded session reaches FromSoftware's
servers.** [Before you start](docs/install.md#before-you-start) has the
rules, including the one launch that does risk a ban.

---

## Quickstart

1. **Download** the engine from the
   **[latest release](../../releases/latest)**:
   `ermod-engine-<version>-linux-x86_64.tar.gz` (Linux, Steam + Proton) or
   `ermod-engine-<version>-macos-aarch64.tar.gz` (Apple Silicon, CrossOver,
   Whisky or protium), plus `SHA256SUMS` and `SHA256SUMS.sigstore.json`.
2. **Verify** it, as the release notes show (`cosign verify-blob`, then
   `sha256sum -c`).
3. **Unpack and run** it; nothing is installed system-wide:

   ```sh
   tar -xzf ermod-engine-<version>-linux-x86_64.tar.gz
   cd ermod-engine-<version>-linux-x86_64
   ./ermod-engine --dry-run   # finds your game and Proton/Wine, launches nothing
   ./ermod-engine             # play, with the mods in ~/.local/share/ermod/mods
   ```

4. **Co-op**, everyone on the same release and game build:
   `./ermod-engine coop host` on one machine,
   `./ermod-engine coop join <host-id>@<host-address>` on the others
   (`./ermod-engine coop id` prints both).

On macOS, clear the download's quarantine before step 3
([how](docs/install.md#on-macos-clear-the-quarantine)). The full setup guide is
**[docs/install.md](docs/install.md)** (also `INSTALL.md` in every archive).

## I just want to play with mods

Download the engine from [Releases](../../releases), for Linux x86-64 or
macOS on Apple Silicon, point it at a directory of `.lua` mods, and play. No
toolchain, no build, no ModEngine.

**→ [docs/install.md](docs/install.md)** is the setup page.

**→ [docs/coop.md](docs/coop.md)** is how to play co-op with friends.

The release includes `ermod-engine` and the two Windows binaries it injects.
Those are built from a **closed-source** repository, and the mod front end,
the Lua sandbox and the `sdk.*` bindings, is part of them. What this
repository publishes is the surface those bindings present.
`stubs/ermod.lua` is generated from the engine's binding tables, so it lists
every `sdk.*` function a mod can call, exhaustively. See
[The published surface](#the-published-surface).

### In the game

| Key | What it does |
| --- | --- |
| `` ` `` (backtick) | Opens and closes the ermod menu: every mod with its state and cost, a switch per mod, profiles, and co-op. |
| `Insert` | Gives mouse and keyboard to mod windows (an overlay, a settings panel), and hands them back to the game. |

While the menu is open, or `Insert` has given the overlay focus, the mouse
belongs to the menu: the pointer moves freely and the camera stays still.
The game ignores the keyboard and mouse until you close the menu or press
`Insert` again. A gamepad keeps working.

The menu also works from the keyboard alone. `Tab` or the arrow keys move
between entries, and `Space` or `Enter` presses the highlighted one.

Both keys can be changed with `ermod-engine settings`, or in `engine.cfg`
(`menu_key`, `focus_key`); [install.md](docs/install.md#settings-enginecfg)
lists every setting.

**Co-op.** Players in a session must run the same mods that change the game
(a game rule, or a param such as a class's starting level). Mods that only
draw, monitor or log may differ. If the host runs one you do not, you are
held at the door: the menu lists the host's mods, downloaded for you, each
with an **Enable** button. Enable them, switch off any game-changing mod the
host does not run, and you join the session by yourself. Nothing is written
to your mods directory until you press **Enable**. Once in, a mod that would
change the game differently from the host's cannot be loaded until you
leave. [docs/coop.md](docs/coop.md) covers starting a session.

## I want to write a mod

Mods are **Lua files**. One file per mod, sandboxed, hot-reloaded in the
running game. This one raises the Vagabond to level 60, a cut-down
[`examples/level60.lua`](examples/level60.lua):

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

Drop the file in your mods directory and it loads on the next frame.

`permissions` is the whole of what the mod can reach: an undeclared module
is absent from `sdk` entirely, so it cannot be reached rather than merely
refused. Field names are the paramdef's own (`soulLv`, `baseVit`, …), and
`.param` on a file name is optional.

The same file also runs offline: `ermod-engine mod bake` writes it into a
`regulation.bin`, so a mod can ship as a file rather than as a script. Only
launch mods run offline, and two mods writing one field is an error there;
the scripting guide has the rules.

**→ [docs/scripting.md](docs/scripting.md)** is the guide: the manifest,
both `run_at` kinds, every SDK module, the sandbox and its budgets, and the
author loop in-game as well as offline.

**→ [`examples/`](examples/)** is eleven worked examples, one file each, one
of them a negative case: from the smallest mod that does anything to a HUD,
an in-game settings screen and `level60.lua`, the reference gameplay mod.
Start with [`hello_launch.lua`](examples/hello_launch.lua); the
[index](examples/README.md) gives the reading order.

## Author tooling

The commands that check a mod are part of the engine, because they run the
game's own front end on the host: the same loader, sandbox, manifest rules,
instruction budget and SDK modules. So "passes `mod check`" means "would load
in-game", and `mod perf`'s numbers come from the real dispatcher rather than an
estimate.

```sh
ermod-engine mod check my_mod.lua other_mod.lua   # syntax, manifest, permissions, entry point
ermod-engine mod perf  my_mod.lua                 # synthetic session; cost per event
ermod-engine mod bake <regulation.bin> <out.bin> <mod>...
```

`mod check` prints one line per mod and exits 1 if any would fail to load, so it
drops straight into a pre-commit hook or CI. `ermod-engine --help` lists
every command.

## Editor completion

```json
{ "workspace.library": ["path/to/elden-ring-mods/stubs"] }
```

That is the whole setup: clone this repository, point a Lua language server at
`stubs/`, and every `sdk.*` call completes with its types and documentation.

## The published surface

This repository holds five things and builds none of them.

| | |
| --- | --- |
| [`stubs/ermod.lua`](stubs/ermod.lua) | LuaLS type annotations for the whole SDK, generated from the engine's binding tables. Point a language server here for completion. Nothing to build. |
| [`examples/`](examples/) | Eleven worked mods, one file each, one of them a negative case. Also the engine's own test corpus, so an example that stops working fails a build there before it is republished here. |
| [`paramdefs/`](paramdefs/) | Paramdex PARAMDEF XML: the field layout of the game's param rows, which is where names like `soulLv` and `baseVit` come from. |
| [`tools/gen_paramdef.py`](tools/gen_paramdef.py) | The generator that turns `paramdefs/` into the engine's field tables. The engine's `make paramdefs` runs it. |
| [`docs/`](docs/) | The scripting reference, the install page, and the design notes. |

The stubs are the honest description of what a mod can do. They are generated
from the binding tables themselves, so a binding that exists and is missing
from the stubs is a bug the generator catches. That makes them a *complete
enumeration* of the surface. What they are not is a bound you can verify by
reading: the implementations live in the closed engine. The sandbox's
behaviour is still yours to test from outside, and is documented in
[docs/scripting.md](docs/scripting.md): `base`, `table`, `string` and `math`
are the only libraries opened, `load`/`dofile`/`require` are stripped, and
every call into Lua runs under an instruction budget.

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

This repository has nothing to build. The stubs are generated by the engine
and committed here; the engine's field tables are generated from
`paramdefs/` and committed there:

```sh
make -C ../elden-ring-mods-engine stubs       # regenerate stubs/ermod.lua
make -C ../elden-ring-mods-engine paramdefs   # regenerate the engine's field tables
make check-stubs                              # are the committed stubs current?
```

The examples are also the engine's test corpus, and the engine checks that
its copy is byte-identical to this one.

## Licence

[Apache-2.0](LICENSE). Chosen over MIT for the explicit patent grant and the
trademark reservation, both worth having for a project built on
reverse-engineered file formats.

That covers everything in this repository. It does not cover the engine, and
the mod front end is part of the engine: the Lua sandbox, the `sdk.*` binding
implementations and the `Host` interface behind them.
[The published surface](#the-published-surface) says what this repository
publishes instead.

Two further things [NOTICE](NOTICE) spells out:

- **Vendored components** keep their own terms, namely the Paramdex PARAMDEF
  XML in `paramdefs/`.
- **The engine binaries** published on the Releases page are built from a
  separate closed-source repository and are licensed with the release, not
  under Apache-2.0.

ELDEN RING is the property of FromSoftware and Bandai Namco; this project is
unaffiliated, distributes no game data, and never writes to an installation.
