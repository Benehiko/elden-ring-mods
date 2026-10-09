# Elden Ring co-op with friends, mods included, over LAN or VPN

<!-- description: Play Elden Ring co-op with friends on Linux and macOS, with mods. Up to five players, peer to peer over LAN, ZeroTier or Tailscale. No matchmaking, no FromSoftware servers, and the host's mods offered to every joiner. -->

ermod-engine has its own Elden Ring co-op: you and your friends share one
world, **peer to peer**, on your home network or over a VPN such as ZeroTier
or Tailscale. There is no matchmaking and no FromSoftware server, so only
machines you can reach can join you. Mods come along: join a host whose mods
you lack and the in-game menu offers them, already downloaded.

It runs on **Linux** and **macOS (Apple Silicon)**, and players on both can
play together. It is a separate project from Seamless Co-op and has no
Windows build.

## What you need

- **Every player:** ermod-engine installed
  ([Linux](elden-ring-linux.md), [macOS](elden-ring-macos.md)), the same
  engine release, and game build 2.7.0.0 or 2.7.1.0
  (`./ermod-engine check-build`).
- **A different Steam account per player.** Two machines on one account can
  still play: see [the co-op guide](coop.md#same-steam-id-on-two-machines).
- **Machines that reach each other** on UDP port 7777: one home network, or
  a shared ZeroTier or Tailscale network
  ([LAN or VPN setup](network.md)).

## Start a session

```sh
./ermod-engine coop id                             # everyone: prints your join line
./ermod-engine coop host                           # the host, first; press Continue in the game
./ermod-engine coop join <host-id>@<host-address>  # each friend, once the host says "you are hosting"
```

The [co-op guide](coop.md) walks through it step by step, with three or more
players and fixes for a join that fails.

## What works, and what does not yet

Co-op is new; sessions of up to three players have been tested.

- **Works:** every player sees the others and the host's enemies, fog-wall
  bosses, resting at graces, deaths and respawns, and spectating a boss
  fight after you die.
- **Not yet:** world progress such as a boss kill is not saved to a joiner's
  world, and Torrent cannot be ridden in a session.

[What co-op is here](coop.md#what-co-op-is-here) has the full list.

## Mods in co-op

Mods that change the game must match: the host's are offered to each joiner,
and nothing is written to your mods directory until you press **Enable**.
Mods that only draw or log can differ.
[Mods in co-op](coop.md#mods-in-co-op) explains it, and
[`sdk.coop`](scripting.md#coop) lets a mod decide who gets what.

## Anti-cheat

Easy Anti-Cheat never runs and co-op never touches FromSoftware's servers.
[Before you start](install.md#before-you-start) has the rules.
