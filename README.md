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

4. **Co-op**, everyone on the same engine release (v0.3.1 with v0.3.1) and
   game build:
   `./ermod-engine coop host` on one machine,
   `./ermod-engine coop join <host-id>@<host-address>` on the others
   (`./ermod-engine coop id` prints both).

On macOS, clear the download's quarantine before step 3
([how](docs/install.md#on-macos-clear-the-quarantine)). The full setup guide is
**[docs/install.md](docs/install.md)** (also `INSTALL.md` in every archive).

> [!NOTE]
> **macOS users: your Wine setup is detected automatically.** If you play
> through [CrossOver](https://www.codeweavers.com/crossover),
> [Whisky](https://github.com/Whisky-App/Whisky) or
> [protium](https://github.com/Benehiko/protium), `ermod-engine` finds the
> bottle that holds Elden Ring and the Wine to run it with. There's nothing to
> configure. Protium is found when the `protium` program is on your `PATH` or
> at `~/.local/bin/protium`. To pick one when you have several, use
> `--backend crossover|whisky|protium` or `macos_backend` in `engine.cfg`. Any
> other Wine works when you name it
> ([how](docs/install.md#macos)).

### Supported game versions

Each engine release supports the Elden Ring builds it has verified addresses
for. A build it does not know runs unmodded, with a warning before launch.

| Game build (`eldenring.exe`) | Steam build ID | [v0.1.0](../../releases/tag/v0.1.0) | [v0.2.0](../../releases/tag/v0.2.0) | [v0.3.0](../../releases/tag/v0.3.0) | [v0.3.1](../../releases/tag/v0.3.1) | [v0.3.2](../../releases/tag/v0.3.2) |
| --- | --- | :---: | :---: | :---: | :---: | :---: |
| **2.7.1.0** (latest patch) | 25080141 | — | — | ✓ mods and co-op | ✓ mods and co-op | ✓ mods and co-op |
| 2.7.0.0 | 23850278 | — | ✓ mods and co-op | ✓ mods and co-op | ✓ mods and co-op | ✓ mods and co-op |
| 2.6.2.0 | 22984413 | ✓ mods | ✓ mods, co-op session¹ | ✓ mods, co-op session¹ | ✓ mods, co-op session¹ | ✓ mods, co-op session¹ |

¹ The session forms, but the co-op rule fixes (death, grace, warp, Torrent) and
character sync are only carried for 2.7.0.0 and later.

Every player in a co-op session needs the same game build and the same engine
release. That includes patch releases: a v0.3.1 player waits for the host to
admit them, which a v0.3.0 host never does, so v0.3.0 and v0.3.1 cannot play
together.

**Which build do I have?** Ask the engine; it reads your installed game:

```sh
./ermod-engine check-build   # "…/eldenring.exe: … file version 2.7.1.0 — a table exists for it"
./ermod-engine --dry-run     # prints the Steam build ID: "game build 25080141"
./ermod-engine --version     # the builds this engine release supports
```

The title screen's **App Ver.** (for example `1.16.2`) is a different
numbering for the same game and is not what the table uses; see
[the engine's version notes](docs/install.md#when-something-does-not-work) if a
launch says your build is not supported. After a game patch, check the
[Releases](../../releases) page for an engine that supports it.

## I just want to play with mods

Download the engine from [Releases](../../releases), for Linux x86-64 or
macOS on Apple Silicon, point it at a directory of `.lua` mods, and play. No
toolchain, no build, no ModEngine.

**→ [docs/install.md](docs/install.md)** is the setup page.

**→ [docs/coop.md](docs/coop.md)** is how to play co-op with friends.

**→ [docs/cli.md](docs/cli.md)** lists every command and flag
([on the website](https://benehiko.github.io/elden-ring-mods/cli.html)).

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
leave.

A player who connects is not in the session until the host admits them: until
then they cannot change anything in the host's world. By default the host lets
in everyone whose mods match. With `coop_join_approval = "ask"` in
`engine.cfg`, the host is asked instead ("co-op: player … wants to join. Open
the ermod menu to allow or refuse.") and answers with **Allow** or **Refuse**
in the ermod menu. [docs/coop.md](docs/coop.md) covers starting a session.

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

This repository holds three things and builds none of them.

| | |
| --- | --- |
| [`stubs/ermod.lua`](stubs/ermod.lua) | LuaLS type annotations for the whole SDK, generated from the engine's binding tables. Point a language server here for completion. Nothing to build. |
| [`examples/`](examples/) | Eleven worked mods, one file each, one of them a negative case. Also the engine's own test corpus, so an example that stops working fails a build there before it is republished here. |
| [`docs/`](docs/) | The scripting reference, the install page, the design notes, and the [command reference](docs/cli.md) (generated from the engine's `--help`). |

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

The engine reads and writes this chain, and names a row's fields from the
community [Paramdex](https://github.com/soulsmods/Paramdex) layouts.

## Development

This repository has nothing to build. The stubs and the command reference are
generated by the engine and committed here:

```sh
make -C ../elden-ring-mods-engine stubs       # regenerate stubs/ermod.lua
make check-stubs                              # are the committed stubs current?
make -C ../elden-ring-mods-engine cli-docs    # regenerate docs/cli.md and docs/cli.html
make check-cli-docs                           # is the committed reference current?
```

See [AGENTS.md](AGENTS.md) for the rules that keep it that way.

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

One further thing [NOTICE](NOTICE) spells out:

- **The engine binaries** published on the Releases page are built from a
  separate closed-source repository and are licensed with the release, not
  under Apache-2.0.

ELDEN RING is the property of FromSoftware and Bandai Namco; this project is
unaffiliated, distributes no game data, and never writes to an installation.
