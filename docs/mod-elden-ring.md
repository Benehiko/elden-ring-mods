# How to mod Elden Ring with Lua, live in the game

<!-- description: Mod Elden Ring on Linux and macOS with live Lua scripts. Switch mods on and off from an in-game menu, edit a file and it reloads in a second. No ModEngine, no toolchain, your game install and saves untouched. -->

To mod Elden Ring with ermod-engine, you drop a Lua file into a folder while
the game runs. Switch each mod on or off from an in-game menu, edit a file
and it reloads within a second. There is no ModEngine, no toolchain to
install and no restart, and your game install and your saves are never
written to.

ermod-engine runs on **Linux (x86-64)** and **macOS (Apple Silicon)**. It
has no Windows build. Platform setup is on
[Elden Ring on Linux](elden-ring-linux.md) and
[Elden Ring on macOS](elden-ring-macos.md).

## What you need

- A Steam copy of Elden Ring, launched normally at least once.
- The `ermod-engine` archive for your machine from the
  [latest release](https://github.com/Benehiko/elden-ring-mods/releases/latest).

## Install a mod and play

```sh
tar -xzf ermod-engine-<version>-<platform>.tar.gz
cd ermod-engine-<version>-<platform>
./ermod-engine --dry-run           # finds your game; launches nothing
./ermod-engine install level60.lua # copy a mod in, e.g. from examples/
./ermod-engine                     # play
```

In the game, press **`` ` ``** (backtick) to open the ermod menu and switch
mods on and off. The [install guide](install.md) covers verifying the
download, where mods go and every setting.

## Write your own mod

A mod is one Lua file. This one starts the Vagabond at level 60:

```lua
local mod = { name = "level60", version = "1.0.0", run_at = "launch", permissions = { "params" } }

function mod.on_launch(sdk)
  sdk.params.row(sdk.params.file.CharaInitParam, 3000).soulLv = 60
end

return mod
```

Save it in your mods directory (`./ermod-engine paths` shows where) and it
loads on the next frame. Mods can read and write the game's live parameter
tables, react to bosses and deaths, draw an in-game overlay and keep their
own settings. Each mod runs in a sandbox with only the modules it declares.

- [Writing mods in Lua](scripting.md): every SDK module and the sandbox.
- [Worked examples](../examples/README.md): rune multipliers, boss rematches,
  overlays, Torrent and more.
- [Shipping a mod as a regulation.bin](deploy.md): a modded `regulation.bin`
  loaded without ModEngine.

## Is it safe?

Easy Anti-Cheat never runs and modded sessions never reach FromSoftware's
servers. The one launch that risks a ban is the normal Steam launch with a
modified `regulation.bin` in place;
[Before you start](install.md#before-you-start) has the rules.

## Mods in co-op

Play your mods with friends: when you join a host whose mods you lack, the
menu offers them, already downloaded. See
[Elden Ring co-op with mods](elden-ring-coop.md).
