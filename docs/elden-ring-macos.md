# Play Elden Ring on macOS (Apple Silicon) with mods and co-op

<!-- description: Play Elden Ring on a Mac with Apple Silicon, with mods and private co-op. A native macOS launcher that finds your game in CrossOver, Whisky or protium and runs it with live Lua mods and LAN or VPN co-op. -->

Elden Ring is not a macOS game, but it runs on Apple Silicon Macs inside a
Wine bottle: CrossOver, Whisky, protium or another Wine. ermod-engine is a
native arm64 macOS launcher that finds that bottle and starts the game with
**live Lua mods** and **private co-op** with your friends over LAN or a VPN.
It never writes to your game install or your saves.

## What you need

- **A Mac with Apple Silicon.** The macOS build is arm64 only. The game runs
  through Rosetta 2 inside Wine, as it does without the engine.
- **A Wine bottle holding Windows Steam and Elden Ring.** The engine finds
  the bottle and the Wine itself for
  [CrossOver](https://www.codeweavers.com/crossover),
  [Whisky](https://github.com/Whisky-App/Whisky) and
  [protium](https://github.com/Benehiko/protium). Any other Wine (Game
  Porting Toolkit, Homebrew, Heroic) works when you name the bottle and the
  Wine:
  `./ermod-engine --prefix ~/path/to/bottle --wine /path/to/wine`.
- **Windows Steam running and signed in**, inside the bottle.
- **The Steam overlay turned off** for Elden Ring (Properties → uncheck
  "Enable the Steam Overlay while in-game"). With it on, the game
  black-screens and closes under Wine on macOS, with or without the engine.

## Get started

Download `ermod-engine-<version>-macos-aarch64.tar.gz` from the
[latest release](https://github.com/Benehiko/elden-ring-mods/releases/latest),
then:

```sh
tar -xzf ermod-engine-<version>-macos-aarch64.tar.gz
cd ermod-engine-<version>-macos-aarch64
./ermod-engine --dry-run   # finds your bottle and Wine; launches nothing
./ermod-engine             # play
```

Gatekeeper refuses the first run, because the engine is not notarized by
Apple. [Clear the quarantine](install.md#on-macos-clear-the-quarantine)
after you [check the download](install.md#check-the-download-is-ours).

## What differs on macOS

- The settings window is not built yet: `./ermod-engine settings` prints the
  equivalent commands.
- The first-launch question about your characters is asked in the terminal.
- The in-game overlay draws the same way as on Linux, but nobody has seen it
  on a Mac's screen yet.

The [install guide](install.md) has everything else.

## Mods

Add a mod with `./ermod-engine install <mod>.lua`, or write your own:
[How to mod Elden Ring](mod-elden-ring.md).

## Co-op with friends

Up to five players, peer to peer, with no matchmaking and no FromSoftware
servers. Friends can be on macOS or Linux. See
[Elden Ring co-op with mods](elden-ring-coop.md).
