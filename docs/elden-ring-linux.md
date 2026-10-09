# Play Elden Ring on Linux with mods and co-op

<!-- description: Play Elden Ring on Linux with mods and private co-op. A native Linux launcher that finds your Steam game and Proton, loads live Lua mods and runs peer-to-peer co-op over LAN or VPN. -->

Elden Ring runs on Linux through Steam's Proton. ermod-engine is a native
Linux launcher that finds your Steam install and the Proton it uses, then
starts the game with **live Lua mods** and **private co-op** with your
friends over LAN or a VPN. It never writes to your game install or your
saves.

## What you need

- **Linux x86-64.**
- **Elden Ring from Steam, with Proton** (Proton Experimental is the usual
  choice). The engine reads Steam's own setting for the game and uses the
  Proton it names.
- **The game launched normally once**, so Steam creates its Proton prefix.
- **Steam running** when you play.

## Get started

Download `ermod-engine-<version>-linux-x86_64.tar.gz` from the
[latest release](https://github.com/Benehiko/elden-ring-mods/releases/latest),
then:

```sh
tar -xzf ermod-engine-<version>-linux-x86_64.tar.gz
cd ermod-engine-<version>-linux-x86_64
./ermod-engine --dry-run   # finds your game and Proton; launches nothing
./ermod-engine             # play
```

The [install guide](install.md) covers checking the download is ours,
where mods go, profiles and settings, and what to do when something does not
work.

## Mods

Press **`` ` ``** (backtick) in the game to switch mods on and off. Add one
with `./ermod-engine install <mod>.lua`, or write your own:
[How to mod Elden Ring](mod-elden-ring.md).

## Co-op with friends

Up to five players, peer to peer, with no matchmaking and no FromSoftware
servers. Friends can be on Linux or macOS. See
[Elden Ring co-op with mods](elden-ring-coop.md).

## Anti-cheat

The engine launches `eldenring.exe` directly under Proton, never the Easy
Anti-Cheat wrapper, and refuses to run while Easy Anti-Cheat is live.
Modded sessions never reach FromSoftware's servers.
[Before you start](install.md#before-you-start) has the rules.
