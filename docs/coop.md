# Playing co-op

This page shows you how to play Elden Ring with friends, with mods, through
the engine. You type a few commands in a terminal. Every command appears
below, ready to copy.

1. [What co-op is here](#what-co-op-is-here)
2. [What you need](#what-you-need)
3. [Connecting: LAN or VPN](network.md) (ZeroTier, Tailscale; a separate page)
4. [Two players, step by step](#two-players-step-by-step)
5. [Three or more players](#three-or-more-players)
6. [Mods in co-op](#mods-in-co-op)
7. [Leaving](#leaving)
8. [When something does not work](#when-something-does-not-work)

---

## What co-op is here

Two or more players share one world. The game's traffic travels directly
between your machines, peer to peer. No FromSoftware server takes part, and
Easy Anti-Cheat never runs. [Before you start](install.md#before-you-start)
in the install guide has the safety rules; read them first.

**Co-op is new.** Sessions of up to three players have been tested.

**What works**

- **Players.** Each player's character appears and moves in the others' games.
- **Enemies.** Every player sees and fights the host's enemies, in the same
  places, and the enemies attack every player.
- **Fog-wall bosses.** One boss appears on every screen, and every player
  sees it die. Confirmed on Margit.
- **Sites of grace.** Host and joiners can rest.
- **Deaths.** A player who dies respawns and stays in the session, and the
  others see them again. When the host dies, damaged enemies keep their
  damage and the time of day does not jump.
- **Spectating a boss fight.** A player who dies in a fog-wall boss fight
  watches a survivor instead of respawning. **Page Down** switches between
  survivors. The dead respawn at the grace when the boss dies or everyone is
  down.

**What does not work yet**

- **World progress is not shared.** The game records events such as a boss
  kill as flags, and the engine does not sync flags. A joiner's save does
  not record a boss the host's world killed.
- **Torrent.** Riding does not work in a session: the rider is thrown off at
  once.
- **Giving up while spectating.** A dead player waits for the fight to end.

## What you need

**Every player needs:**

- **The engine installed.** Follow the [install guide](install.md). The
  commands below use `./ermod-engine`, typed in the directory you unpacked
  it into, as the install guide does.
- **Game build 2.7.0.0 or 2.7.1.0.** Co-op works on these builds only. To check yours:

  ```sh
  ./ermod-engine check-build
  ```

- **The same engine release.** `./ermod-engine --version` prints yours.
  Compare the first line with your friends'.
- **A character.** The engine reads your Steam ID from your save, so play
  once through Steam if you never have.

**These must match between players.** The engine checks the game build
(above) and game-changing mods ([Mods in co-op](#mods-in-co-op)). It does
not yet check the rest, so a mismatch shows up as strange behaviour rather
than a refusal:

- **Shadow of the Erdtree:** every player has it installed, or nobody does.
- **A modded `regulation.bin`:** every player loads the same file with
  `--regulation`, or nobody loads one. See [deploy.md](deploy.md#co-op).

**Your machines must reach each other** on UDP port 7777: the same home
network (LAN), or a VPN such as ZeroTier or Tailscale for friends elsewhere.
**[network.md](network.md)** sets this up step by step, firewall included.

**Each player needs a different Steam account.** Two machines signed in to
one account can still play together: give one of them `--as` and a Steam ID
that nobody in the session uses, for example `--as 76561198000000009`.
See [Same Steam ID on two machines](#same-steam-id-on-two-machines).

## Two players, step by step

One player **hosts**; the other **joins**. The host goes first, every time.

### 1. Both players: swap IDs

Both of you run:

```sh
./ermod-engine coop id
```

It prints your Steam ID, your addresses, and the line a friend types to join
you. For example (your numbers will differ):

```
Steam ID   76561198000000001   (from the folder the game keeps your own save in)
Address    192.168.1.10   (enp5s0)
           100.101.102.103   (tailscale0)
Port       7777 (UDP)

A friend joins you with:
  ermod-engine coop join 76561198000000001@192.168.1.10
  ermod-engine coop join 76561198000000001@100.101.102.103
(the address on the network you share with them)
Host first: run `ermod-engine coop host`, load into your world, then they join.
```

The host sends its friend the `coop join` line for the network they share:
the home network's address, or the VPN's address. Each address shows its
interface in brackets; [network.md](network.md#zerotier) shows how to tell
the VPN's apart (a VPN can hand out `192.168.…` addresses too).

### 2. The host starts

```sh
./ermod-engine coop host
```

The game starts. At the title screen, press **Continue** (or load the
character you want). Once your world loads, the command sets up the session.
Wait for `you are hosting`. The terminal shows, abridged:

```
info: coop: your Steam ID is 76561198000000001 (from the folder the game keeps your own save in)
info: coop: [1/4] launch the game
info: coop: [2/4] wait for a loaded world: at the title screen, press Continue
info: coop: the game is at the title screen. Press Continue (or load the character you want to play); the co-op steps follow once you are in the world.
info: coop: the world is loaded
info: coop: [3/4] repoint the game's networking at UDP and fabricate the co-op lobby
info: coop: [4/4] host the session (the game's own CreateSession); joiners announce themselves when they join
info: coop: you are hosting. Your friends can join now, one at a time: ...
info: coop: this command ends when the game does.
```

The host does not type the friend's address. The host's game learns it when
the friend joins.

### 3. The friend joins

Only after the host sees `you are hosting`, the friend types the line the
host sent, with `./` in front:

```sh
./ermod-engine coop join 76561198000000001@192.168.1.10
```

Press **Continue** at the title screen as the host did. The terminal ends
with, abridged:

```
info: coop: [4/4] announce this machine to its peers and join the host's session
info: coop: joined — the host answered and admitted you. Its world loads for you when the game's own join completes.
info: coop: this command ends when the game does.
```

`joined` appears only once the host has admitted you. It may also print `the
host knows you are here. The join waits until your game-changing mods match
the host's`. If your mods already match, the join starts by itself a moment
later. If they differ, see [Mods in co-op](#mods-in-co-op).

If the host has set `coop_join_approval = "ask"` in its `engine.cfg`, the host
sees `co-op: player … wants to join` and chooses **Allow** or **Refuse** in
the ermod menu. Your game does not start joining until the host allows you,
so there is no hurry. If the host refuses, the terminal says `the host (…)
refused this machine`. If nothing is decided within 15 minutes it says `not
joined` and why: the host never answered, your mods still differ, or the
host has not allowed you yet.

Leave the terminal open while you play.

### 4. Meet up

The engine does not move anyone to the host. Each player starts where their
own save left them, and you find each other in the world. Torrent does not
work in a session, so a long way apart means a long walk. The easy way:
before a session, have each player rest at the same site of grace and quit
there. You then start side by side.

## Three or more players

The host still names nobody. Each joiner names the host **and every player
who joined before it**, in any order after the host. Join one at a time.

```sh
# Friend 1 joins the host:
./ermod-engine coop join 76561198000000001@192.168.1.10

# Friend 2 joins the host and names friend 1:
./ermod-engine coop join 76561198000000001@192.168.1.10 76561198000000002@192.168.1.11
```

Friend 1 learns friend 2 when friend 2 joins. A session holds at most five
players: the host and four joiners.

If a player uses a port other than 7777 (`--port`), the others add it to
that player's address: `76561198000000002@192.168.1.11:7790`.

## Mods in co-op

Mods that **change the game** (a game rule, or a param such as a class's
starting level) must match between players. Mods that only draw, monitor or
log may differ.

The host's mods are the session's. A joiner whose game-changing mods differ
from the host's is held at the door. Open the ermod menu with **`` ` ``**
(backtick). It lists the host's mods, downloaded for you, each with an
**Enable** button, and a **Switch off** button for each of yours the host
does not run. Match the host and you join by yourself. Nothing is written to
your mods directory until you press **Enable**.

The README's [In the game](../README.md#in-the-game) section has the menu's
keys.

By default the host admits everyone whose mods match. With
`coop_join_approval = "ask"` in the host's `engine.cfg`, the host chooses
**Allow** or **Refuse** in the ermod menu for each player instead. Once you
are in, a mod that would change the game differently from the host's cannot
be loaded until you leave.

## Leaving

- **Quit the game.** The `coop` command ends when the game does.
- **Or press Leave** in the co-op section of the ermod menu. It ends co-op
  in the running game.
- **Or run `./ermod-engine coop leave`** from another terminal. It does the same.

On leaving, every other player's game removes you and your character at once,
and you keep playing alone in your own world. A player whose game crashes cannot
say goodbye: the others drop that player after 45 seconds of silence.

The game signs in to co-op once per launch, as it loads your world. To play
co-op again, quit the game and run `coop host` or `coop join` again.

## When something does not work

The terminal says what went wrong on a line starting `error: coop:`. The
common cases:

### The joiner started before the host

`coop join` needs a host that is already hosting. A joiner that reaches its
world first gets no session, and cannot get one later. The terminal says
the join is waiting, and it waits forever. **Quit the game** on the joiner,
wait for the host's `you are hosting`, and run `coop join` again.

### Wrong game build

Co-op needs build 2.7.0.0 or 2.7.1.0 on every machine. On another build the ermod
menu's co-op section says `not available for this game build`, and the
`coop` command stops with an error. Run `./ermod-engine check-build`
and update the game through Steam.

If a game patch is newer than your engine, you can try co-op anyway with
`--ignore-build-guard` (engine releases after v0.2.0):

```sh
./ermod-engine coop host --ignore-build-guard
./ermod-engine coop join <host-id>@<host-ip> --ignore-build-guard
```

This runs co-op with addresses that were not checked against your game.
**Expect crashes**, and wrong reads or writes to the characters in your
modded profile; your own save is still never opened. Every player needs the
same game build, the same engine release, and the flag. See
[When something does not work](install.md#when-something-does-not-work).

### Mods do not match

The joiner's terminal says:

```
info: coop: the host knows you are here. The join waits until your game-changing mods match the host's: open the ermod menu (`), enable the host's mods it lists, and the join starts by itself
```

The host's menu says `co-op: 1 peer(s) waiting to match your game-changing
mods`. The joiner enables what the menu lists; see
[Mods in co-op](#mods-in-co-op). A download that reads `download failed
(bytes did not match)` did not arrive intact.

### The friend never shows up

The host's menu still says `1 in the lobby`, and no peer waits on mods. The
host never heard from the friend. Check, in order:

1. The friend typed the host's address on the network they share (`coop id`
   lists them all), and the ID exactly.
2. Both machines are on the same LAN or the same VPN network.
3. No firewall blocks UDP port 7777 on either machine
   ([network.md](network.md#the-firewall)).
4. The host was hosting before the friend loaded its world.

Then quit the game on the joiner and run `coop join` again.

### Same Steam ID on two machines

```
error: coop: two players have the same Steam ID. Two machines on one Steam account must be told apart: run one of them with --as <another SteamID64> (any one nobody here uses).
```

Add `--as` to one machine's command, and give the others that ID in place of
its own:

```sh
./ermod-engine coop join 76561198000000001@192.168.1.10 --as 76561198000000009
```

### The game sits on a loading screen after you join

The terminal says `your game has sat on a loading screen for about 30 s since
the join`. This is a known hang: the game moves to another map, for example
after you warp to the host's grace, and the load stalls. It sometimes clears on
its own after a short wait. If it does not, quit the game, run `coop join`
again, and send `ermod-runtime.log` with your bug report (`./ermod-engine paths`
says where it is).

### Other messages

| Message | What to do |
| --- | --- |
| `the game is already running` | `coop` starts the game itself. Quit the game and run the command again. |
| `cannot tell this machine's Steam ID` | No save of yours exists yet. Play once through Steam, or give an ID with `--as`. |
| `a player is <SteamID64>@<a.b.c.d>…` | The ID or address is mistyped. Copy the line `coop id` printed. |
| `no world within 15 minutes` | The game sat at the title screen. Run the command again and press Continue. |
| `the game is still running, without co-op` | A step failed; the lines above say which. Quit the game and try again. |

### The logs

```sh
./ermod-engine paths
```

prints where the logs are, on the two `log` lines. `ermod-runtime.log`
records what co-op did in the game; on the host, a line with `learned peer`
means a friend's join arrived. Include both logs and
`./ermod-engine --version` in a bug report. The install guide's
[When something does not work](install.md#when-something-does-not-work)
covers problems outside co-op.
