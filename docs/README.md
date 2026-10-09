# Guides

Everything here is also on the website, rendered from these same files.

## Start here

| Guide                                                 | What it covers                                                      |
| ----------------------------------------------------- | ------------------------------------------------------------------- |
| [How to mod Elden Ring](mod-elden-ring.md)            | Live Lua mods: install one, write one, switch them in the game      |
| [Elden Ring on Linux](elden-ring-linux.md)            | Mods and co-op under Proton                                         |
| [Elden Ring on macOS](elden-ring-macos.md)            | Mods and co-op on Apple Silicon, in CrossOver, Whisky or protium    |
| [Elden Ring co-op with friends](elden-ring-coop.md)   | Peer-to-peer co-op over LAN or VPN, mods included                   |

## Playing

| Guide                                                             | What it covers                                                             |
| ----------------------------------------------------------------- | -------------------------------------------------------------------------- |
| [Installing the engine](install.md)                               | Verifying downloads, macOS setup, where mods go, settings, troubleshooting |
| [Profiles and your save](install.md#5-profiles-and-your-own-save) | Modded saves kept apart from your own; `profile` and `character` commands  |
| [Playing co-op](coop.md)                                          | Sessions, mods in co-op, fixes                                             |
| [Connecting for co-op: LAN or VPN](network.md)                    | ZeroTier, Tailscale and the firewall                                       |
| [Finding stutters](performance.md)                                | Tracing what makes frames slow, and reading the report                     |

## Writing mods

| Guide                                           | What it covers                                           |
| ----------------------------------------------- | -------------------------------------------------------- |
| [Writing mods in Lua](scripting.md)             | Every SDK module, the sandbox, `mod perf`, `mod bake`    |
| [Shipping a mod as a regulation.bin](deploy.md) | Baking a modded `regulation.bin` and loading it          |
| [Starting classes](classes.md)                  | The ten starting classes' stats and gear, for class mods |
| [Command reference](cli.md)                     | Every command and flag                                   |
| [Architecture](architecture.md)                 | How it fits together                                     |

The worked examples are in [`examples/`](../examples/README.md).

## Releases

[Changelog](changelog.md): what changed in each engine release, newest first.
