# elden-ring-mods

**Mod Elden Ring in Lua, live in the running game, and play it in co-op with
your friends, over LAN or a VPN.** On Linux and macOS.

- ⚡ **Mods are a few lines of Lua.** Save the file and it reloads in the game
  within a second. No toolchain, no ModEngine.
- 🤝 **Co-op for up to five players**, peer to peer, at home or over
  [ZeroTier or Tailscale](docs/network.md). Friends missing the host's mods
  get them in one click.
- 🛡️ **Safe by design.** Easy Anti-Cheat never runs, no modded session reaches
  FromSoftware's servers, and your game install is only ever read
  ([the rules](docs/install.md#before-you-start)).
- 🐧 **Linux** (Steam + Proton) and **macOS on Apple Silicon** (CrossOver,
  Whisky or protium, detected for you).

---

## Quick start

### 1. Play with mods

Download `ermod-engine` for your machine from the
**[latest release](../../releases/latest)** (`…-linux-x86_64.tar.gz` or
`…-macos-aarch64.tar.gz`), then:

```sh
tar -xzf ermod-engine-<version>-<platform>.tar.gz
cd ermod-engine-<version>-<platform>
./ermod-engine --dry-run          # finds your game and Proton/Wine; launches nothing
./ermod-engine install level60.lua # copy a mod in, e.g. from this repo's examples/
./ermod-engine                    # play
```

In the game, press **`` ` ``** (backtick) to open the ermod menu and switch
mods on and off.
[Verifying the download](docs/install.md#check-the-download-is-ours),
[macOS's quarantine](docs/install.md#on-macos-clear-the-quarantine) and
everything else are in **[the install guide](docs/install.md)**.

### 2. Play co-op

Everyone runs the same engine release and game build. Then:

```sh
./ermod-engine coop id                             # everyone: prints your join line
./ermod-engine coop host                           # the host, first; press Continue in the game
./ermod-engine coop join <host-id>@<host-address>  # each friend, once the host says "you are hosting"
```

That works as it is on one home network. **Friends elsewhere?** Join one
ZeroTier or Tailscale network first: **[network.md](docs/network.md)**, a few
minutes, once. It also shows which of the addresses `coop id` prints is the
VPN's. The **[co-op guide](docs/coop.md)** covers three or more
players, mods in co-op, and what to do when a join fails.

### 3. Write a mod

Save this as `level60.lua` in your mods directory
(`./ermod-engine paths` shows where) while the game runs:

```lua
local mod = { name = "level60", version = "1.0.0", run_at = "launch", permissions = { "params" } }

function mod.on_launch(sdk)
  sdk.params.row("CharaInitParam", 3000).soulLv = 60   -- the Vagabond starts at level 60
end

return mod
```

It loads on the next frame. Check a mod before you share it:

```sh
./ermod-engine mod verify level60.lua   # would it load in the game?
```

For completion in your editor, point a Lua language server at
[`stubs/`](stubs/): `{ "workspace.library": ["path/to/elden-ring-mods/stubs"] }`.
Then read **[the scripting guide](docs/scripting.md)** and the eleven
**[examples](examples/)**, starting with
[`hello_launch.lua`](examples/hello_launch.lua).

---

## In the game

| Key | What it does |
| --- | --- |
| `` ` `` (backtick) | Opens the ermod menu: every mod with a switch, profiles, and co-op. |
| `Insert` | Gives mouse and keyboard to mod windows, and hands them back to the game. |

The menu works from the keyboard too (`Tab`/arrows, `Space`/`Enter`). Rebind
either key with `./ermod-engine settings`
([every setting](docs/install.md#settings-enginecfg)).

## Supported game versions

| Game build | Engine | |
| --- | --- | --- |
| **2.7.1.0** (latest) | v0.3.0 and later | mods and co-op |
| 2.7.0.0 | v0.2.0 and later | mods and co-op |
| 2.6.2.0 | v0.1.0 and later | mods; co-op without the rule fixes |

`./ermod-engine check-build` tells you which one you have. An unknown build
runs unmodded, with a warning.

## Everything else

| | |
| --- | --- |
| [Install guide](docs/install.md) | Verifying downloads, macOS setup, where mods go, settings, troubleshooting |
| [Profiles and your save](docs/install.md#5-profiles-and-your-own-save) | Modded saves kept apart from your own; `profile` and `character` commands |
| [Co-op guide](docs/coop.md) · [LAN / VPN](docs/network.md) | Sessions, mods in co-op, fixes |
| [Scripting guide](docs/scripting.md) | Every SDK module, the sandbox, `mod perf`, `mod bake` |
| [Command reference](docs/cli.md) | Every command and flag |
| [Architecture](docs/architecture.md) | How it fits together |

This repository is the open half (SDK stubs, examples and docs) under
[Apache-2.0](LICENSE). The engine is closed source; its binaries ship on the
[Releases](../../releases) page under their own licence ([NOTICE](NOTICE)).
ELDEN RING is the property of FromSoftware and Bandai Namco. This project is
unaffiliated, distributes no game data, and never writes to an installation.
