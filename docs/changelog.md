# Changelog

What the engine does, in the words of someone using it rather than building
it. Engine releases are published on the open repo's Releases page; the
supported game build is part of every entry, because it decides whether the
engine does anything at all.

## v0.8.0 (2026-10-10)

Game build **2.7.1.0**, as in v0.7.0. Every player in a co-op session needs the
same game build and this engine version.

### Windows: an experimental native launcher

A new download, `ermod-engine-<version>-windows-x86_64.zip`, runs the game on
Windows without Wine. Its `ermod-engine.exe` finds Elden Ring through Steam,
refuses while Easy Anti-Cheat runs, checks each mod in
`%LOCALAPPDATA%\ermod\mods`, and starts the game with the runtime and the
mods that passed, keeping its logs, profiles and mod records in
`%LOCALAPPDATA%\ermod`.

```text
ermod-engine            launch the game with the runtime and your mods
ermod-engine --dry-run  find the game and say what a launch would do
ermod-engine mod verify check the mods without launching
```

It is **experimental**. It has run the game, with mods, only inside a Proton
prefix, not yet on a Windows PC. Profiles, co-op and the settings window are
Linux and macOS only for now, and its profile starts empty, with no copy of
your characters. A mod added or edited while the game runs waits until you
run `mod verify`. Its check of each mod is less sealed off than on Linux and
macOS: it cannot start programs or write to your files, but can still read
files and reach the network. `ermod-engine.exe` is not code-signed, so
Windows SmartScreen warns the first time you run it.

### Faster frames: render the world smaller

The game can draw the 3D scene at a fraction of the screen size and scale it
up, but on PC it never does. Set `render_scale` in `engine.cfg` to a number
from 0.5 to 1.0 and the engine turns it on:

```text
render_scale = 0.6
```

The picture is softer the lower you go. On an M4 Mac at
2560x1440 with every setting on LOW, 0.6 cut the GPU's work per frame from
28.8 ms to 20.6 ms, and 0.5 to 18.7 ms. It works on game build 2.7.1.0; on
another build the log says so and the game renders at full size.

### Mods: read the game's load balancer and graphics presets

`sdk.params.file` now names `GraphicsConfig`, `LoadBalancerParam` and
`LoadBalancerNewDrawDistScaleParam_win64`: the values behind each quality
preset, and the console-style load balancer's effect cuts, dynamic resolution
and draw-distance scaling. On PC the game does not act on the load balancer
tables, so changing them does not change the frame rate.

### macOS: see how hard the GPU works

Under D3DMetal the frame trace could not see the GPU, so a GPU-bound frame
looked like the game's CPU work. On macOS the engine now reads Metal's own
per-frame figures.

- The ermod menu shows a line under the frame rate:
  `metal: GPU <ms> ms of a <ms> ms frame (<share>%), GPU busy <util>%`.
- `ermod-engine trace start --mac-gpu` also samples the GPU driver beside the
  trace, and `trace report` adds a `mac gpu` section: utilisation, GPU memory,
  Metal's GPU time per frame, and whether the game is GPU-bound.
- Metal writes these figures only while its HUD is on, so Apple's Metal HUD
  now shows in the corner of the game on every macOS launch. Launch with
  `--no-metal-stats` to turn it and the menu line off.

### Co-op: no invisible wall at cave entrances

Walking from the open world into a cave or catacomb during co-op could stop
the host or a joiner at the entrance, as if a wall stood there. It happened
whenever that player had loaded in, rested or travelled somewhere outside the
dungeon and then walked to it. The dungeon is now open to everyone in the
session, however they got there.

### `--debug`: help track down a co-op crash

A host could crash mid-session (exit code `0xC0000005`) inside the game's
own memory handling, after something wrote into memory the game had already
let go of. What does that write is not known yet.

Launch with `ermod-engine --debug` (it works with `coop host` and
`coop join` too) and the engine watches for that damage. When it finds it,
it writes what it found to `ermod-runtime.log` (lines starting
`heap guard`) and steps around it, so the game usually keeps running,
though it can still crash later. Those lines are what's needed to find the
cause: send them with a bug report.

It costs the game about 3% more CPU, so it is off unless you ask for it.

### Co-op: Torrent comes back after you are knocked off it

In co-op, a ride that ended without a dismount (knocked off Torrent, for
example) left Torrent standing there. The whistle then did nothing for a
while, so calling Torrent again could take a whistle or two. Torrent is now
dismissed when such a ride ends, as it is after a dismount, so the next
whistle works.

### Co-op: no crash when mounting Torrent

The game could crash for a player mounting Torrent in co-op, after an
earlier ride in the same session. The engine was reading the earlier ride's
Torrent, which the game had already removed.

### Co-op: reviving Torrent with a flask works

When Torrent died under you in co-op, a Flask of Crimson Tears often could
not bring it back:

- A joiner was never offered the revive. The host's game sent the joiner's
  Torrent's health back from its own copy, so the joiner's game thought the
  dead Torrent was alive: no flask prompt, and the whistle could not call it.
  Each player's game now keeps its own Torrent's health.
- A revive that did work mounted the rider and then threw them straight off.
  The ride now holds.
- Reviving within a few seconds of the death left Torrent stuck, and every
  whistle after it did nothing. An early revive now works like a late one.

### Co-op: Torrent stays under its rider for everyone

A teammate's Torrent could be missing from your world, with the teammate
riding nothing, or put far away from them. It happened when the host had
been on Torrent since it loaded, and in parts of the open world where the
game's large and small map tiles overlap. A joiner could also stop seeing the host's Torrent after
it had died. Every player now sees each Torrent under its rider.

### Characters: `horse=off` loads a character on foot

A character saved while riding loads on Torrent. `dev save set … horse=off`
puts Torrent away in the save, so the character loads on foot; Torrent's
health is kept. A joiner that loaded into a session on horseback could end up
stuck in the ground or dead, so the rig (`dev rig`, `dev coop rig`) now sets
`horse=off` for every joiner, on a player's profile too. `coop join` does not
do this yet: a joiner should get off Torrent before quitting the game.

### Rig: `--debug` on every machine, and killing Torrent on purpose

`dev rig up --debug` and `dev rig cycle` launch every machine with `--debug`,
so the heap guard runs everywhere (`dev rig cycle --no-debug` leaves it off).
`dev state horse_hp=0` kills your Torrent the way the game does, to test a
revive; `0` is the only value it takes.

### Overlay: Ctrl+Tab between windows, and mod buttons that press keys work

With the engine menu open (backtick) or the overlay holding the input
(Insert), **Ctrl+Tab** now moves between the menu and a mod's window. The
menu used to take the keyboard straight back, and it stayed drawn on top,
covering a mod window placed under it. Clicking a window works as before.

A mod button that makes the game press a key now works while the overlay holds the input. The overlay still
keeps your own keys and mouse from the game, but no longer swallows the
engine's own press, so the button no longer reports "pressed" with nothing
happening.

The engine's presses still reach the game only while its window is the
active one, like your own keys.

### Mods: `sdk.player` — Torrent from a mod

A mod with the new `player` permission can see how the ride stands, and
mount, dismount, revive and kill Torrent, solo only:

- `sdk.player.ride_state()`: `on_foot`, `mounting`, `riding` or
  `dismounting`; `sdk.player.mounted()`; `sdk.player.in_world()`, which is
  false while a map loads, a grace warp included.
- `sdk.player.mount()` calls Torrent and gets on.
- `sdk.player.dismount()` gets off.
- `sdk.player.revive()` brings a dead Torrent back beside the player, without
  a flask; it does not mount.
- `sdk.player.kill_steed()` kills Torrent; a rider falls off.
- `sdk.player.steed_hp()` and `sdk.player.steed_dead()` read Torrent's
  health, or nil when no Torrent is loaded.

`ride_state()`, `steed_hp()` and `steed_dead()` read nil outside a world and
while a map loads.

Mounting and dismounting use the whistle as the player does, inside the
game: the engine selects it, presses use on the game's own input, and puts
the selected item back. Nothing reaches the desktop, and the Spectral Steed
Whistle need not sit in a quick slot, but the player must hold it to mount
or revive.

Each call returns true, or false and a reason: `no_world`, `no_steed`,
`no_whistle`, `wrong_state` (Torrent already dead or alive, or the wrong
ride state), `refused` (the game said no, as on a grace), `busy` (a mount or
dismount is still being pressed), `in_session` (in a co-op session, for now)
or `unavailable`. `examples/torrent.lua` puts the ride state and a button for
each call in a window, and revives and remounts a fallen Torrent.

### Characters: a made character can call Torrent

A character made with `character new` has never met Melina, so it has no
Spectral Steed Whistle and can't call Torrent: the use-item key uses a flask
instead. Add `whistle=on` (to `character new` or `dev save set`) and the
character holds the whistle in its first free quick item slot, selected if
no quick item was, so the use-item key calls Torrent. It is refused if the
character already has one or has no free quick item slot. Only the item is
given; nothing of the story that comes with it in the game.

A made character also loaded with the game's hints on screen and the game
paused, so nothing it was told to do happened until someone closed them.
`character new` now marks those hints as already read, as a played character
has them.

`dev save set tutorial=<id>` marks any hint read, and `dev save show
--flags` and `--inventory` print a slot's event flags, items, quick items
and the hints it has read, to compare two saves.

### Settings window: saving the Engine tab keeps your other settings

Saving the Engine tab used to write only the settings it shows, which reset
`coop_join_approval` to `auto` and turned the frame trace off. It now keeps
every setting in `engine.cfg`.

### Profiles: a new profile is ready for a new character

`ermod-engine profile new <name>` now gives the profile an empty save, so
`ermod-engine character new --profile <name> --class <class>` can make a
character in it straight away. Before, a new profile had no save, and the
only ways to get one were launching the game once or `profile port`, which
copies in every character from your own save. Your own save is only read.
`profile port <name> --force` still copies your characters in if you want
them.

### Profiles: `profile list` shows the game's backup save

Before each save, the game keeps a copy of the previous one as
`ER0000.sl2.bak`. A character you delete from a profile stays in that copy
until the game next saves, and nothing said so. `profile list` now shows
when each profile's backup was written, and names any character that is
only in the backup.

### Times are shown in your timezone

Dates and times the launcher shows are now on your own clock: the backup
times in `profile list`, the date in a `profile backup` file name, "ported
from your vanilla save" in `profile list` and the settings window, and the
`diagnostics` archive name. They were in UTC, so a backup made just after
midnight could be dated the day before. Each time names its zone (`CEST`,
`EDT`); where no timezone can be found, times are in UTC and say so.

### Co-op: a player who leaves can join the same host again

A player who left a session (with `coop leave`, by quitting, or because the
game crashed) and joined the same host again loaded in but was never
connected. Neither player saw the other, until the host restarted its game.
Joining again now connects as the first join did. The host needs this
version.

### Co-op: rejoining loads you where the host is now

A player who left and joined again could load where they had left instead of
beside the host, if the host had just travelled. The host's game gave out
the grace it was leaving while it loaded the new one. Now a host that is
loading says so, and the joiner's `coop join` waits for it to arrive
(up to two minutes) and loads there. The host needs this version. A joiner on
an older version loads where its save stands while the host is loading.

### Co-op: a joiner's fast travel loads as fast as the host's

When a player who joined travelled to a grace, their loading screen lasted
about 20 seconds where the host's took 5. The joiner's game was waiting out
a 15-second change of light, caused by its clock catching up with the
host's time during the load. That change now finishes straight away, behind
the loading screen, and a joiner's load takes about as long as the host's.

### Co-op: you are told when a teammate dies out of sight

When a player dies far from you (80 m or more, or somewhere not loaded in
your world), you see "`<name>` has died" on screen. A death near you, or in
the boss fight you are both in, shows nothing: you saw it. Before, a
death could be missed, and a player who only travelled or loaded could be
reported as dead. Every player needs this version.

### Co-op: you see where a teammate travels

When a teammate travels to a grace, every player sees "`<name>` travelled to
`<grace>`" on screen. Every player needs this version: the traveller's game
is the one that says where it went.

### Co-op: the game's own notices, with your teammates' Steam names

A teammate joining, leaving or dying now shows in the game's own on-screen
messages, such as "`<name>` has joined your world", instead of the engine's
small overlay, and a grace a teammate lights shows the game's LOST GRACE
DISCOVERED banner in your world. Each player is named by their Steam name. A
teammate on an older version, or whose name has not arrived about 10 seconds
after joining, shows as "Player NNNN". If the engine does not recognise the
game's code for these messages, it uses its own overlay as before.

### Co-op: one player's story moments stay theirs

When one player rested or met Melina at a grace, the other player was pulled
into it: they watched the cutscene wherever they were, could not skip it, and
were warped to the grace. Now the host's story cutscenes play only for the
host, and another player's rest only respawns the enemies in your world.

### Co-op: enemies are there wherever the host goes

Once the host walked away from the area where the session started, the
enemies ahead of it never appeared. The engine was claiming the host's enemies for the wrong slots outside the
first map tile. Every tile's enemies are now claimed.

### Co-op: a joiner's runes are dropped where it died

A joiner that died dropped nothing: the game treated it as a summoned
visitor, and visitors lose no runes. Every player's death now leaves its
runes on the ground in its own world, to be picked up as in a solo game.

### Co-op: a grace one player lights is lit for everyone

A grace the joiner found was not lit, not even in the joiner's own world, and
a grace the host found never reached the joiner. Now whoever lights a grace
lights it for every player in the session.

### `ermod-engine dev save show` shows the dropped runes

Each character now has a `blood-stain` line: whether a drop is waiting to be
picked up, and its map and position.

### Co-op: a joiner keeps all its flasks after dying

A joiner that died came back with about half its flasks (a Wretch's three
Crimson and one Cerulean became one and none): the game reloaded it with a
summoned visitor's flask allowance. Each player now keeps its own full
flasks across a death.

### Co-op: the host no longer crashes when a joiner leaves

When a joiner left the session, the host's game could crash soon after: the
engine kept looking at the joiner's character after the game had removed it.
It now lets go of that character as the joiner leaves. The host needs this
version.

### New example: your stats on screen

`examples/stats_overlay.lua` shows every value `sdk.watch` can read in a
small HUD: level, runes, deaths, HP, the eight attributes and, in co-op, the
distance to the nearest teammate. A value that just changed shows by how
much, in green or red, for a few seconds. It only reads and draws, so it is
safe to run in any co-op session.

### `ermod-engine diagnostics`: your logs, ready for a bug report

`ermod-engine diagnostics` packs the engine's logs into one `.tar.gz` in the
current directory (or wherever `--out` says) to attach to a GitHub issue.
Your account name in any path, every Steam ID and every IP address are
replaced with placeholders first — the same value gets the same number in
every file, so a co-op session can still be followed. Your own logs are not
touched, and it works without the game being found.

### `dev rig seed` writes only into a `rig-` profile

Seeding joiners (`dev rig seed`, or `dev rig up` with `seed_joiners = true`)
copied the host's save over whatever profile the joiner's machine played on,
even a player's own. It now refuses, before stopping the game or copying
anything, unless that profile is named `rig-…`. On a machine someone also
plays on, give the rig its own profile
(`ermod-engine profile new rig-seed && ermod-engine profile use rig-seed`), or
set `seed_joiners = false`.

The rig's launch (`dev coop rig`) on a player's profile no longer touches the
character either: it does not change which character Continue loads, does
not restamp the save's account, and refuses a `grace` other than `""`. It
still writes where the player joins (`map=`/`pos=`), as `coop join` does.

## v0.7.0 (2026-10-06)

Game build **2.7.1.0**, as in v0.6.0. Every player in a co-op session needs the
same game build and this engine version.

### Co-op: both players wake in the Stranded Graveyard with their flasks

After the Grafted Scion, the joiner now sees the Stranded Graveyard's
arrival cinematic too, and starts with the Flasks of Crimson and Cerulean
Tears like the host. Before, only the host got either. A character that
already missed its flasks this way gets them the next time the game starts.

### Co-op: no more standing at 1 HP against the Grafted Scion

When one player falls to the Scion, the other no longer sits at 1 HP,
unable to die, for half a minute after their own lethal hit. The fallen
player spectates, and the last one down dies as from any boss.

### Mods: a boss's state is always known, and a revive is only a revive

`sdk.bosses.state(id)` no longer answers nil for a boss that is not nearby.
It always says whether the boss is `loaded`, whether it is `alive`, and
whether the game counts it as `defeated` (read from the game itself), with
its health and position while it is loaded. `sdk.bosses.revive(id)` makes a
boss unbeaten, evergaol bosses included, and the boss is back the next time
its area loads; when that happens is the mod's choice. See
[`bosses` in the scripting guide](scripting.md#bosses).

### Co-op: a joiner no longer hangs loading in at the host's spot

A joiner loads in where the host stands. In some open-world spots the
host's game gave that place in a form a save cannot hold, and the joiner
then sat on the loading screen for good. The host no longer gives a place
from such a spot, and the joiner loads where its own save stands instead.

### Co-op: enemies near a joiner fight, even far from the host

When a joiner went somewhere the host was not, such as Gatefront while the
host stayed in Stormveil, some enemies around the joiner were run by
neither game. They stood still, and when the joiner hit them they froze at
no health without dying, so they paid no runes. Now the joiner's own game
runs every enemy around it that the host's game is not running, and hands
them back when the host comes near or the joiner leaves. A kill there
counts and pays runes to every player, as anywhere else.

### Co-op: everyone keeps the host's time of day

A joiner who joined, or fast-travelled somewhere far, used to see the
morning for up to a minute before the game caught up with the host's time.
The host now shares its time every couple of seconds, so a joiner arrives in
the same hour as the host.

### Co-op: no white walls at the edge of a multiplayer area

In a co-op session the game used to raise white walls where its multiplayer
area ends, such as at a catacomb's entrance or at the exit of Margit's arena
into Stormveil, for the host and the joiner alike. Those walls are gone:
players in a session can go wherever they could go solo. Solo play is
unchanged.

## v0.6.0 (2026-10-06)

Game build **2.7.1.0**, as in v0.5.0. Every player in a co-op session needs the
same game build and this engine version.

### Co-op: every player gets the runes

A joiner used to get nothing for most enemies and only a quarter of a boss's
runes. Now every player in a session gets the full runes of every enemy any
player kills, and of every boss, however far apart they stand. Each
character's own rune bonuses, such as a rune talisman, still apply on top.
Solo play is unchanged. Every player in the session needs this version.

### `sdk.coop`: decide who gets what

A new SDK module, `sdk.coop` (permission `coop`), for mods that decide
things per player: `coop.active()`, `coop.is_host()`, `coop.get_distance()`
(metres to the nearest other player, and their Steam ID),
`coop.get_distance(id)` (metres to one player, by Steam ID),
`coop.distances()` and `coop.players()` (each other player's Steam ID,
distance and position, nearest first). Its
`coop.set_rune_rates({ enemy = 0.25, boss = 0.5 })` sets the share of runes
the player on that machine takes; the full amount is the default.
`sdk.watch.stat.coop_distance` reports the distance as a watchable value.
See [`coop` in the scripting guide](scripting.md#coop) and
`examples/coop_runes.lua`.

### `on_death` tells a mod the character's death count

`sdk.hooks.on(sdk.hooks.event.on_death, function(ev) ... end)` now gets
`ev.deaths`: how many times the character has died, this death included.
It is the game's own lifetime counter, saved with the character, and the
same number `sdk.watch.get(sdk.watch.stat.deaths)` has always read. A mod no
longer has to count deaths itself to show a total. `examples/death_ping.lua`
and `examples/overlay.lua` show it beside their own count since loading.

### Mods can run boss fights

`sdk.bosses` can now set up and run a fight, not only revive a boss:

- `bosses.warp(id)` travels to the boss's grace (`boss.grace`) and puts the
  player beside the boss once it has loaded.
- `bosses.wake(id)` makes the boss fight, and `bosses.kill(id)` kills it
  through the game's own death routine, so the game records the defeat.
- `bosses.reset(id)` clears the defeat flag, and for an evergaol its own
  state too. It takes effect at the next map load.
- `hooks.event.on_boss_defeated` gives `{ id, flag, kind }` when the game
  records a defeat. It does not fire for the defeat flags a map load sets
  again.
- New fields: `boss.kind` (`evergaol`, `minor_erdtree`, `field` or
  `arena`), `boss.phases` (how many kills the game needs before it records
  the defeat), `boss.evergaol` (the evergaol's name) and `boss.spawns`
  (where the boss stood before, at the start of, and through its fight).

Evergaols can be opened from a mod. For the ten base-game evergaols,
`boss.can_open` is true, and `bosses.warp(id, { open = true })` stands the
player on the pad, answers "Enter evergaol?" and steps towards the boss.
`bosses.open(id)` does the same when the player is already near it.
`hooks.event.on_evergaol_entered` fires when the gaol takes the player in,
whether the player or the SDK opened it. Shadow of the Erdtree's 40 bosses
now have phases and coordinates recorded too. The boss at row 1039510800
is now correctly named a Night's Cavalry (`nights_cavalry_1039510800`), and
161 of the 210 boss names are measured in the game.

A woken boss fights for real: `bosses.wake` does not protect the player. See
[`bosses` in the scripting guide](scripting.md#bosses).

### Fixed: a stutter in mods that watch every boss

Each `sdk.bosses` lookup re-read the whole boss table. A mod that checked
every boss once a second (`examples/boss_watch.lua`) spent about 16 ms in a
single frame and made the game stutter. Lookups now take about 0.03 ms.

### Fixed: `check-build` passes on game build 2.7.1.0

`ermod-engine check-build` reported a failure on 2.7.1.0, and every log
carried a matching warning, although the build is supported. Both are gone.

## v0.5.0 (2026-10-05)

Game build **2.7.1.0**, as in v0.4.0. Every player in a co-op session needs the
same game build and this engine version.

### Frame trace: find what makes frames slow

The engine can now record every frame's timing while you play, split into
the game's CPU work, the time spent waiting in Present (GPU, vsync or
driver), and the engine's own work, and flag the stutters.

- Turn it on at launch in `engine.cfg` with `frame_trace_cpu = "off" |
  "light" | "normal" | "detailed"` or `frame_trace_gpu = true | false`
  (both off by default; the Engine tab keeps them when it saves a rebind),
  or at any time with `ermod-engine trace start [--cpu LEVEL] [--gpu]` and
  `ermod-engine trace stop`.
- `ermod-engine trace report [<file>]` prints frame-time percentiles, the
  stutters, which side each one was on, and the worst ones.
- `--cpu` samples the game's busiest threads and the report names the game
  functions and DLLs that run during stutters, with call paths through the
  game's own code. `--gpu` times each of the game's GPU submissions.
- When tracing is off, the tracer itself costs the game one memory read
  per frame. Separately, the always-on stutter counter behind
  `sdk.perf.spikes()` runs every frame whether or not you trace. It was
  measured at about 0.5 µs a frame (median), and at most 6 µs, which is
  under 0.04 % of a 60 fps frame.
- Mods can count stutters too: `sdk.perf.spikes()` returns how many frames
  the trace's spike rule has flagged, the last one's length and its frame
  number, and the bundled performance monitor shows them.

The sample rates behind `light`, `normal` and `detailed` (50, 100 and
250 Hz) are placeholders. The first attempt to measure their cost to frame
times was inconclusive. See [Finding stutters](performance.md).

### Co-op: a trace mod for debugging the shared world

A new read-only SDK module, `sdk.trace` (permission `trace`), shows what each
machine believes about a co-op session. It covers the session role, the
players and their mounts, and every enemy near the player: who owns it,
whether its owner's updates arrive, and the HP its owner last reported. It
also has the multiplayer-area barrier counters. `examples/coop_trace.lua`
draws all of it and flags frozen enemies, corpses standing on the other
screen, and players faded out. It logs rows keyed by the enemy's handle,
which is the same on every machine.

Every machine in a session sends its view to the others once a second, so
the host collects the whole session. Its overlay shows each joiner's view
beside its own, with the enemies the two machines disagree on. Its log
holds every machine's rows and a line whenever a disagreement starts or
ends. The overlay is in collapsible sections, with characters sorted and
the flagged ones first. Mods can use the same widgets: `sdk.ui.collapsing`
and `sdk.ui.tree`. See [`trace`](scripting.md#trace) and [Playing co-op](coop.md#the-logs).

### Co-op: a joiner arrives beside the host, so players see each other right

A joiner used to load where its own save stood, and its game then placed
things relative to a different spot than the host's. Players appeared a few
metres off and faced past each other, and a player on Torrent vanished from
the other screen. Now `coop join` asks the host where it stands before your
game starts and loads your character right there, the way a summon arrives
at the host. Your own respawn grace is unchanged: if you die, you respawn at
your grace, not at the host.

The host must be in its world when you join. If the host is on Torrent,
`coop join` says so and waits up to 90 seconds for it to get off. If the
host does not answer within a few seconds, you load where your save stands
and the log says why. Both players need this version.

A joiner is also never pulled back to a grace in the middle of a session
any more; calling Torrent used to trigger that.

### Co-op: Torrent stays under its rider after a death

After a player died and respawned somewhere else, the other machine drew
their Torrent, and the rider on it, far away (exactly one map tile), so a
mounted player vanished. Each machine now tells the others how its game
places its own horse, and the others place it the same way.

A player who stays on Torrent while the other player dies (or travels) is
no longer left floating on that player's screen until they whistle again:
the returning player's game puts them back on their horse.

### Co-op: a joiner's death keeps the time of day

A joiner who died came back at 07:00 while the host's world stayed at its
own time. The joiner's respawn now keeps the running clock, as the host's
already did.

### Every boss by name

Almost every boss now has a name in `sdk.bosses.id` (210 of 212):
`sdk.bosses.id.starscourge_radahn`, `sdk.bosses.id.messmer_the_impaler`.
Every name is the game's own, spelled as the game spells it.
`boss.name_measured` is true where the name was read off the boss itself in
the game, and false where it is assigned by encounter and not yet checked
live; a mod that needs certainty can check it.

### Co-op: a joiner sees the host's dead enemies dead

An enemy the host has already killed no longer stands alive in a joiner's
world. A joiner also takes the host's health for an enemy the host had
damaged before the joiner arrived, where before it only matched when both
players' enemies sat in the same order in memory.

### Co-op: enemies near a joiner come alive away from the host

The host's game only runs the enemies around the host. A joiner exploring
elsewhere met enemies that stood frozen and ignored it. The joiner's game now
runs the enemies the host is not running.

### The overlay stays off the game's HUD

The ermod menu and mod windows now open in the top-right corner instead of
over your health, FP and stamina bars. The overlay also scales with your
resolution: text and spacing grow and shrink with the display height (1080p
is the reference), and no window takes more than 40% of the screen's width
or 70% of its height. Anything longer scrolls.

For mod authors: `x`/`y` in `sdk.ui.window` options now count inward from
the window's `anchor` corner, which defaults to `"top_right"`. To keep a
window where it was, pass `anchor = "top_left"`. `"bottom_left"` and
`"bottom_right"` are available too. Positions and sizes are in 1080p pixels
and are scaled to the display.

## v0.4.0 (2026-10-03)

Game build **2.7.1.0**, as in v0.3.2. Every player in a co-op session needs the
same game build and this engine version.

### Before you update: two changes for mod authors

- **One `rules` permission for every game rule.** A mod that changes a rule
  now asks for `"rules"`, instead of a permission named after the rule
  (`boss_spectate`). A manifest that still lists a rule's name is refused as
  an unknown permission. Which rules a mod changes is still checked, and a
  conflict between two mods still names the rule.
- **`ermod-engine mod check` is now `mod verify`**, with no alias.

### Every mod is verified before the game loads it

`mod verify` runs each mod on your machine in a sandboxed process that can
open no files, start no programs and reach no network, and the game loads only
mods whose exact bytes this engine build has verified. A mod that crashes or
misbehaves in the check is rejected. The engine menu shows each mod's
verification.

### Co-op: spirit ashes are shared

A spirit one player summons now appears in every player's game, and leaves
when it is dismissed. A Mimic Tear looks like its owner on
every screen, and the blob it starts as goes away once the copy appears.

### Co-op: the whole map is open

A session was confined to the area it began in: a white wall at the area's
edge and a warp back inside past it, so a host could not even leave the
Stranded Graveyard. In co-op there is no wall and no warp back.

### Co-op: arriving together

- Two players who load onto the same spot are moved a step apart instead of
  standing inside each other, which could trap and kill one of them.
- A joiner whose save was written on horseback stays mounted, on their own
  Torrent. They used to land on the host's horse and be thrown.
- A character that had spent time joining as a guest could make a co-op load
  drop both players from the sky. Every launch now repairs the save.
- A player who drops out and rejoins quickly gets their character and horse
  again.

### Co-op: losing to the Grafted Scion

While a teammate fights on, losing to the Grafted Scion in the Chapel of
Anticipation is a death you spectate from, as for any boss. Your loss
cutscene used to carry the living teammate into the next map with you. The
last player's loss plays as usual.

### Summon spirits anywhere

The new rule `spirit_summon_anywhere` (off by default) lets spirit ashes be
summoned outside summoning pools, and the spirit stays. See
`examples/summon_anywhere.lua`.

### Every item by name: `sdk.items`

`sdk.items.<table>.<name>` is the row id of any item, spell, skill, Ash of
War or class, named as the game names it (6794 of them), and
`sdk.items.file.<table>` is its param file, so a mod can write
`sdk.params` rows by name. See `examples/class_flasks.lua`.

### Fixed: "?" in the engine menu

Dashes in menu text, the join-request window's title among them, showed as
"?". They draw correctly.

### Mods can bring bosses back

A mod with the `bosses` permission can revive any boss in the base game or
Shadow of the Erdtree, the one-off field bosses included:
`sdk.bosses.revive(10000850)` brings Margit back, and
`sdk.bosses.revive_all({ dlc = false })` brings back every base-game boss.
`sdk.bosses.all` lists all 212 encounters (map, DLC or not, rune reward), taken
from the game's own data. A revived boss is back the next time its map loads:
rest at a grace, warp or die. Its one-off drop does not come back. See
[`bosses` in the scripting guide](https://github.com/Benehiko/elden-ring-mods/blob/main/docs/scripting.md#bosses)
and `examples/boss_rematch.lua`.

### Events and param files are enums, like stats

Every game property a mod names now has a typed spelling on the SDK:
`sdk.hooks.on(sdk.hooks.event.on_death, fn)` and
`sdk.params.row(sdk.params.file.CharaInitParam, 3000)`, alongside the existing
`sdk.watch.stat.hp`. The type stubs declare each one as a LuaLS `---@enum`,
so an editor completes the names and flags one that does not exist; in the
game, indexing a name that does not exist (`sdk.hooks.event.on_levelup`) is an
error where it is written. `sdk.params.file` lists only files the engine has
a paramdef for, under the names the game loads them by (`ItemLotParam_map`,
`ItemLotParam_enemy`). Existing mods that pass plain strings keep working.

### Mods can watch HP, stats, runes and deaths

A mod with the `watch` permission can call `sdk.watch.on(sdk.watch.stat.hp, fn)` and be
told the old and new value on the frame it changes, or `sdk.watch.get("vigor")`
to read one at any time. Watchable: `deaths`, `runes`, `level`, the eight
stats, `hp` and `hp_max`. FP, stamina and flasks are not yet available. See
[`watch` in the scripting guide](https://github.com/Benehiko/elden-ring-mods/blob/main/docs/scripting.md#watch).

### Make a character without character creation

`ermod-engine character new --class samurai --keepsake golden-seed --name Sam`
writes a fresh character of any of the ten starting classes into your
profile's save and points Continue at it. It loads in the Chapel of
Anticipation with the class's weapons, armour, spells and stats, read from
the game's own regulation. `character list` and `character delete` manage the
slots. `--regulation` builds the class as a baked mod defines it, and the
`dev save set` fields (`grace=`, `level=`, `runes=` …) apply in the same
command. See
[Profiles, and your own save](https://github.com/Benehiko/elden-ring-mods/blob/main/docs/install.md#5-profiles-and-your-own-save).

### Shell completion

`ermod-engine completion bash|zsh|fish` prints a completion script. Every
command, option, class, keepsake, profile and path completes.

### Fixed: "Save data is corrupted" after authoring a fresh character

Changing the Steam id, grace or level of a character that had not yet picked
up a tutorial message wrote those fields 0x3FC bytes from where they belong.
The game then refused the save. Such characters now walk and write
correctly.

## v0.3.2 (2026-10-02)

Game build **2.7.1.0**, as in v0.3.1. Every player in a co-op session needs the
same game build and this engine version: an older engine neither says goodbye
nor drops a player who left.

### Co-op: leaving actually leaves, and a crashed player is dropped

"Leave co-op" in the engine menu, the new `ermod-engine coop leave`, and
quitting the game now tell every other player. Their games remove you and
despawn your character at once, and you keep playing alone in your own
world. Until now Leave told no one, and your character stood frozen in every
other world for the rest of their session.

A player whose game crashes cannot say goodbye. The others now drop it after
45 seconds without a word from it, and its character disappears. A joiner
whose host is gone leaves the session as well.

Every player needs this version: an older engine neither says goodbye nor
drops anyone.

### Co-op: `coop join` stops when the game closes

If the game exits while `coop join` waits for the host to admit you, the command
now says so and ends. It used to print `still waiting` until its 15-minute limit.

### Co-op: a joiner no longer hangs on a map load on game build 2.7.1.0

A player who joined a host and then warped to another map (for example from a
dungeon grace to the host's grace) could freeze on a loading screen. The engine
used an address from the previous game build to tell the game who hosts the
session, so the game never learned it. On 2.7.1.0 the load now finishes after a
short wait.

### Co-op: `coop join` says when your game is stuck on a loading screen

After you join, `coop join` keeps watching your game. If the game sits in one
map-load step for about 30 seconds, it says so, calls it the known joiner hang,
and points you to `ermod-runtime.log` to send with a bug report. It says so once,
and says when the load finishes.

### Logs live in the data directory

The engine now writes `ermod-runtime.log` and `ermod-launcher.log` to
`~/.local/share/ermod/logs/`, beside your mods and profiles. To report a
problem, copy them from there. Deleting or rebuilding the Wine prefix keeps
them. The first launch moves any logs an older engine left in the prefix's
`system32`. `ermod-engine paths` prints both paths.

## v0.3.1 (2026-09-30)

Game build **2.7.1.0**, as in v0.3.0. Every player in a co-op session needs
the same game build **and this engine version**: a v0.3.1 joiner waits for
the host to admit it, which a v0.3.0 host never does.

### Co-op: a player joins only once the host has let them in (2026-09-30)

A player who connects to your session is no longer part of it straight away.
They become a member only once their game-changing mods are exactly yours and
the host has let them in. Until then they cannot change anything in your world
(respawns, resting, enemy health, spectating), and a player the host refused
never reaches the game at all. If a member's mods stop matching mid-session,
they are paused until they match again.

`coop join` says `joined` only once the host has admitted you. If the host
refuses you, or does not answer in time, it names the host and gives the
reason.

### Co-op: the host can approve each player who joins (2026-09-30)

Set in `engine.cfg`:

```text
coop_join_approval = "ask"   # default "auto": every player whose mods match is let in
```

With `ask`, a player whose mods match waits. While the ermod menu is closed,
a notice tells the host who is waiting; the menu lists them with **Allow** and
**Refuse**. The joiner's game does not start joining until the host allows
it, so the host can take as long as they need. Allow has been tested live;
Refuse is covered by tests but has not yet been run in a live session.

### Skipping the title menu no longer plays the title music in the world (2026-09-30)

With the title menu skipped, the title theme kept playing over the world. It
now stops the same way it does when you press Continue yourself.

### Faster, checked address updates after a game patch (2026-09-30)

Behind the scenes: the addresses the engine uses are now carried from one game
build to the next by a tool that compares the two game executables, with every
carried address checked against the hand-verified tables. This release changes
nothing for supported builds; it makes support for the next game patch quicker
to deliver and less likely to be wrong.

## v0.3.0 (2026-09-29)

### Game build 2.7.1.0, with co-op (2026-09-29)

The engine now supports Elden Ring **2.7.1.0**, the latest game patch. Mods
load, param edits apply, the intro logos are skipped, the character sheet reads
correctly, and **co-op works**: `coop host` and `coop join` form a session, and
the co-op rule fixes (death, grace, warp, Torrent) and character sync are
active. Tested host + joiner on 2.7.1.0, in both a development and a release
build.

Grace travel and skipping the title menu work on 2.7.1.0 too. Every address
the patch moved was re-derived and checked against the 2.7.1.0 game before use;
anything that could not be checked is switched off rather than guessed. Every
player in a session needs the same game build.

### Co-op players see each other again after a warp (2026-09-29)

After one player travelled, host and joiner could stand side by side and each
see only themselves: the other player's character was not rebuilt after the
load. It now is, after a warp as well as after a death.

### Co-op joiners no longer crash on release builds (2026-09-29)

A joiner running a release build crashed the moment it joined a session, on
its first co-op message to the host. The cause was a diagnostic in the engine,
not the game, and it only misbehaved in optimised builds; it is gone. Debug and
release builds now behave the same.

### The engine refuses to call a game function at a wrong address (2026-09-29)

If a game function the engine calls is not where this game build puts it, the
engine now refuses the call and says so, instead of jumping into the middle of
other code and crashing the game.

### `--ignore-build-guard`: run an unsupported game build anyway (2026-09-29)

A game build the engine has no verified addresses for normally runs unmodded.
`--ignore-build-guard` runs it anyway, as the newest build the engine does
have complete addresses for (2.7.0.0). Every command that launches the game
takes it: `ermod-engine --ignore-build-guard`, `coop host
--ignore-build-guard`, `coop join … --ignore-build-guard`. It applies to that
one launch, and both the launcher and `ermod-runtime.log` say when it is in
effect.

It is unsafe by design: after a patch some of those addresses will have
moved. Expect crashes, and wrong reads or writes to the characters in your
modded profile; your own save is still never opened. A supported build runs as
itself with or without the flag; it only matters after a game patch the engine
does not know yet.

### macOS: protium, and choosing the Wine setup (2026-09-29)

CrossOver stays the default. If [protium](https://github.com/Benehiko/protium)
is installed (`~/.local/bin/protium` or on `PATH`) and one of its prefixes
holds Elden Ring, the engine uses it instead. It launches through
`protium run --prefix <name>`, so the prefix's own settings apply.
`--backend auto|crossover|whisky|protium`, or `macos_backend = "…"` in
`engine.cfg`, picks one outright. A named backend never falls back to
another vendor's Wine. Setup guide:
[Installing the engine, macOS](https://github.com/Benehiko/elden-ring-mods/blob/main/docs/install.md#macos).

## v0.2.0 (2026-09-29)

### Co-op: everyone runs the same game-changing mods (2026-09-29)

Players in a session must run the same mods that change how the game plays:
a game rule, or a param write. Mods that only draw, monitor or log may
differ. A joiner whose set differs is held at the door. The menu lists the
host's mods, downloaded for them and checked byte for byte, each with an
**Enable** button, and any game-changing mod the host does not run with a
**Switch off** button. Once they match, the joiner joins by itself. Nothing
is written to the mods directory until the player presses **Enable**. In the
session, a joiner cannot load a game-changing mod the host does not run, or
switch off one the host does; cosmetic mods load and reload freely.

### The menu no longer fights the camera (2026-09-29)

While the ermod menu is open, or `Insert` has given mod windows focus, the
mouse pointer moves freely and the camera stays still: the game's cursor
recentring is suspended and it reads the keyboard and mouse as idle. A
gamepad keeps working. The menu can also be driven from the keyboard: `Tab`
or the arrow keys to move, `Space` or `Enter` to press.

### Mod packs and game rules (2026-09-28)

A mod can be a **mod pack**: its manifest lists other mods by name
(`mods = { "level60", "boss-rules" }`). A pack and its members take
precedence over mods loaded on their own. When a pack and a standalone mod
set the same thing to different values, the pack's value is the one that
lands. The standalone mod still loads, and the log says which of its
settings was not applied.

Every mod's configuration (`sdk.params` writes, and the new `sdk.rules`) is
now checked before any of it reaches the game. The engine runs each mod's
entry point with its writes held back, compares them, and applies only what
passes. Two packs that set the same thing to different values are both
refused, along with their members. The same goes for two standalone mods.
The same value from both is fine. A mod already running keeps its place, so
a pack added later that disagrees with it is the one refused. Configuration
can only be changed from a mod's entry point; a write from an event handler
is an error.

`sdk.rules` holds engine-wide game rules. A mod sets a rule only with the
permission of the same name. The first rule is `boss_spectate` (default on):
off, a player who dies in a fog-wall boss fight respawns instead of being
held to watch a teammate.

### The world gate is the game's own (2026-09-07)

Everything that waits for "a world" — `dev world`, `dev wait-world`, `dev
state`, `dev warp`, `dev summon`, the co-op rig — now waits for the player to
be standing in one: the game's title, in-game and map-move step machines at
their resting steps with no title menu held. It used to be a null test on one
allocation, which passed on the title screen. `dev state` says
`world-loading` while the map step is still walking and `not-in-world` at the
title. `dev world --skip-menu` now presses the game's own Continue instead
of replaying it, because the replay loaded the world under the title window.

The first release. Everything below has been proven on a live, offline
launch of the real game unless it says otherwise.

**Supported game build: 2.6.2.0.** On any other build the engine logs that it
does not recognise the game, disables every hook and lets the vanilla game
run. It never guesses.

### What it is

`ermod-engine` launches Elden Ring with Easy Anti-Cheat left out — under
Proton on Linux, in a Wine bottle on macOS — and injects a runtime that can
run Lua mods in the live game and load a modded `regulation.bin` without
touching the game install.

### Playing with mods

- **Lua mods, live.** Drop `.lua` files in the engine's mods directory and
  they run in the game. Each mod is sandboxed in its own VM with only the
  modules it declares; a mod that misbehaves is disabled on the spot and the
  others carry on.
- **Mods can read and write the game's live parameter tables** — the same
  data a `regulation.bin` holds, edited in the running game.
- **Mods can draw** — an in-game overlay (`Insert` toggles input focus),
  report frame timing, and persist their own settings between sessions.
- **A modded `regulation.bin` loads without ModEngine.** Point the engine at
  an `ermod-engine dev apply` artifact and the game reads it instead of its
  own file.
  The game's own `regulation.bin` is never overwritten, so Steam's integrity
  check has nothing to revert.

### Getting to the game faster

- **`ermod-engine world` is the testing loop in one command.** Stop the
  game, author the save `Continue` will load (`--save FILE`, and
  `field=value` arguments applied by the engine itself), relaunch muted and
  headless,
  drive to a loaded world, print the character — about thirty seconds, no
  input, nothing on the desktop. It replaces an older script, so a mod
  author has it with the binary rather than with a checkout.
- **`--headless` keeps the game off your desktop.** The launch runs inside a
  headless gamescope session — its own nested display that is never shown —
  so the game does not open a window and does not take the keyboard or
  mouse. Meant for unattended test runs on a machine someone is also using;
  `ermod-engine shot`, `screen`, `key`, `state` and `drive` all work
  unchanged, because they act from inside the game rather than through the
  display. Needs `gamescope` installed; the launcher says so if it is not.
- **The logo screens are skipped by default.** The publisher and engine cards
  shown every launch. The game already has its own way of skipping them; the
  engine just always takes it, so nothing of ours runs on that path. Turn it
  off with `skip_title_cards = false` in `engine.cfg`, or on the Engine tab.
- **The opening movie can be skipped**, and the story cutscenes with it,
  each behind its own switch (`skip_boot_cinematics`,
  `skip_ingame_cinematics`, both off by default; also on the Engine tab).
  The engine presses the game's own `[Esc] Skip` the moment a movie it is
  told to skip opens, so the game ends it exactly as it ends one you skipped
  yourself — about three seconds in. The opening movie is proven live; the
  in-game switch is the same code against cutscenes not yet reached in a
  test. Four attempts to end the movie through Bink's own API came first and
  each was ruled out by a live run (one dropped every frame of the picture
  while the audio ran on; three crashed the game inside Bink).
- **`ermod-engine key` now moves the game.** It sends a real key event
  (`SendInput` from inside the process) as well as feeding the input hooks,
  and that turned out to be the only route the game's screens react to; the
  earlier message-queue delivery reached the pump and moved nothing. A
  test can now drive the game from `PRESS ANY BUTTON` through the policy
  dialogs, the main menu and character creation to the opening movie
  without a person at the keyboard.
- **The engine can tell which screen the game is on, and drive it by
  looking.** `ermod-engine screen` names the menu in front of it (a frame
  capture reduced to a small fingerprint and matched against references
  learned from the running game; `--learn` teaches it a new one), and
  `ermod-engine drive new-game` takes a freshly launched game from `PRESS
  ANY BUTTON` to the world — through whatever dialogs happen to appear —
  in under a minute, unattended. It replaced a timing script that broke on
  every unexpected dialog.
- **The engine can set the character, instead of driving the game to build
  one.** `ermod-engine state` prints the live character sheet — level, the
  eight stats, runes — and `ermod-engine state level=60 vigor=40
  runes=500000` writes it, printing the sheet as it stands afterwards so a
  clamped value is visible rather than silent. Proven live on a fresh
  Vagabond: the first read returned the class's own starting numbers, field
  for field, and after a write the game's own HUD showed the new rune total.
  It writes save-side fields only — it cannot warp or spawn, because where
  the player stands is not a field but the output of the game's
  map-streaming machinery. Writes are refused outside a loaded world, since
  the title screen's player data is zeroed and a write there would be
  discarded unread, and every value is clamped to its real range (stats to
  the game's own 99).
- **The engine reads a save file itself, with no Rust and no game.**
  `ermod-engine save show [<save.sl2>] [--slot N] [--all]` prints the
  characters in a save — name, level, runes, the eight stats, the save
  version, the map each stands in, and where each one actually is: position,
  the grace they last rested at, their spawn point, and the save's Steam
  account. It reads the file and never writes it. With no file it reads the
  active profile's save; your vanilla save is only read when you name it. It
  agrees field for field with the Rust tool it replaced, on every character
  of every save tested, across nine save versions.
- **The engine writes a save too, and there is no Rust left in the project.**
  `ermod-engine save set [<save.sl2>] --slot N field=value ...` writes level,
  the eight stats, runes, name, Steam id, event flags, the volume sliders and
  the position block, recomputing every section checksum and the player-data
  hash. `save set --slot N grace="The First Step"` puts a character at any
  overworld or legacy-dungeon grace, in the Lands Between or the Land of
  Shadow, so a test starts on `Continue` already
  standing there. Unlike the tool it replaced, it writes bytes in place: a set
  touches the slot you named and nothing else.
- **`ermod-engine save graces` lists every grace** it can place a character
  at — with its map, position, unlock flag and whether it can be stood at —
  and needs no save file. **`save regen-graces`** rebuilds that table from a
  save's own regulation copy, for the day a game patch moves a grace.
- The message-queue hooks no longer hang the game on a dialog: a message
  answered to a look-ahead peek is now kept for the removing call that
  follows, instead of vanishing and leaving `GetMessageW` to block.
- Every one of these is version-gated like the rest of the engine: on an
  unrecognised build, or if anything about the game does not look the way the
  signature says it should, the engine logs it and leaves the game alone —
  the intro plays exactly as it would without the engine.

### Writing mods

- **Edit and save; the game picks it up within a second.** No relaunch.
- **`--mods <dir>` points the game at your working tree**, so the files you
  edit are the files it loads.
- **The engine can capture what it draws** — `ermod-engine shot` writes the
  exact frame the game presented, overlay included.
- **The authoring tools are part of the engine**, under `ermod-engine dev`:
  `check` (would this mod load in-game?), `perf` (what does it cost per
  event?), `stubs` (LuaLS type stubs for the SDK), `img` (turn a frame
  capture into numbers), and `apply`, `ls`, `show` and `selftest` for
  working with a `regulation.bin` offline. `check` and `img diff` report
  through the exit code, so both drop straight into a pre-commit hook or CI.
- The SDK stubs, the worked examples and the scripting reference live in the
  open repo, which builds nothing: `stubs/ermod.lua` is generated from the
  engine's own binding tables, so it lists every `sdk.*` function a mod can
  call, exhaustively.

### Your characters

- **A modded game never plays on your own save.** Each session plays on a
  *profile* — a named save of its own — so a mod that grants a hundred levels
  or writes a bad value lands there and not in the save Steam Cloud carries
  to every machine you own. Your own save is only ever read.
- **The engine offers to copy your characters in.** On a first launch it
  shows what your own save holds and asks once whether to copy them into the
  profile — in a window if your desktop has one, in the terminal if not.
  Answer with `--port-vanilla` or `--no-port-vanilla` to skip the question,
  or `--no-gui` to be asked in the terminal; say no and it is remembered
  rather than asked again.

  ```text
  Profile 'default' has no characters yet.
  Your own save has 3:
      a                  lv 164    118h
      BBB                lv  32     13h
      test60             lv  60      0h

  Copy them into this profile? Your own save is only read. [Y/n]
  ```

- **`ermod-engine profile list` says what each profile holds** — every
  character, its level and its playtime — and which profiles were copied from
  your own save, including when that save has changed since.
- `ermod-engine profile new|use|delete|port` manage profiles; `profile
  export` is the one command that writes your own save back, it asks for
  `--yes`, and it never overwrites its own backup.
- `ermod-engine profile backup` copies your own save aside, under today's
  date. It reads that file and never writes it, and a second backup on one
  day never replaces the first.
- `ermod-engine paths` shows where everything lives, and the characters in
  your own save, so you can confirm the engine found the right file.

### A window, if you would rather not use a terminal

- **`ermod-engine settings` opens a settings window.** One page: your engine
  switches on one tab, your saves on the other.
- **The Profiles tab shows your own save first**, with the characters in it,
  and then every profile with its characters, when it was last written, and
  whether it was copied from your own save. Buttons do what the `profile`
  commands do: choose which profile the game plays on, copy your characters
  into one, copy one back over your own save, back your own save up, make a
  profile, delete one.
- **Anything that would overwrite characters asks twice**, and says what it
  is about to do while it waits for the second press.
- **A Mods tab switches mods on and off**, per profile — the same switches
  the engine's own in-game menu flips, so a mod turned off in one is off in
  the other. The window cannot say whether a mod is *running* or what it
  costs per frame; that is live, and the in-game menu is where it is shown.
- **The Engine tab is the engine's settings file.** The two key bindings are
  read from `engine.cfg` and written back. Each says what pressing that key
  in game actually does, shows the key it is on now, and rebinds by asking
  you to press the key you want — any key the engine can bind, not a short
  list — with a button back to the default beside it.
- Everything the window does has a command, and every command still works.
  On a machine with no display the window says so and names the commands
  instead.

### On a Mac

- **The engine runs on macOS.** The launcher builds as a native Apple Silicon
  binary and starts the game in a Wine bottle — CrossOver, Whisky, or anything
  else Wine-based — instead of under Proton, which is a Linux program and has
  no macOS build. It finds the bottle itself if you use CrossOver or Whisky;
  for anything else, name it with `--prefix <bottle> --wine <path to wine>`.
- **The Steam that has to be running is the Windows one inside the bottle.**
  That is the client the game's own Steamworks talks to. Offline Mode is not
  required on either platform.
- **An install with the executables renamed still works, and still refuses Easy
  Anti-Cheat.** Mac players commonly copy `eldenring.exe` over
  `start_protected_game.exe` so Steam's Play button starts the game. The
  engine reads each executable's own version resource rather than trusting its
  filename, so it launches whichever file really is the game and refuses
  whichever one really is Easy Anti-Cheat — in either direction. You do not
  need that rename for the engine, which never uses Steam's Play button, but
  having done it costs you nothing.
- **The overlay and frame capture work here too.** `sdk.ui` (the in-game
  overlay) and `sdk.screen` / `ermod-engine shot` (frame capture) had been off
  on macOS: they draw and read back through a D3D12 command queue, and the way
  the runtime learned the game's queue is a vtable write that D3DMetal does not
  allow. The overlay now falls back to a command queue of its own when it
  cannot learn the game's, so both work without that write. Linux is unchanged
  — there it still uses the game's queue. (Built and covered by the tests; that
  the overlay renders under D3DMetal is not yet confirmed on real hardware.)
- **`--muted` works here too.** It used to route audio into a PulseAudio null
  sink, which macOS has none of. The runtime now mutes the game's own audio
  session from inside the process (through `IAudioSessionManager` /
  `ISimpleAudioVolume`), so it needs nothing from the host, touches no prefix
  or game setting, and leaves nothing behind — on either platform.
- **What is not there yet.** `--headless` is Linux-only by nature: it is
  gamescope's nested offscreen compositor, and macOS has no gamescope and no
  equivalent, so the flag is refused there rather than half-faked. `dev coop
  host/join/udp` and `dev egress` have not been ported, and the settings
  window falls back to naming the equivalent commands. Each says so plainly
  instead of quietly doing nothing. `dev coop selftest` runs (it opens no
  socket), and `dev world` runs — muted but visible, and it says so, rather
  than asking for an offscreen launch the platform cannot give and never
  launching.
- **Each platform's code is in its own file, and the binary carries only its
  own.** The launcher's Linux code (`/proc`, Proton, gamescope, the raw-syscall
  co-op transports) and its macOS code (Wine bottles, `libproc`) live in
  `_linux.zig` and `_darwin.zig` files, the way Go does it, and the build
  compiles one set. A macOS launcher has no Linux syscall in it to reach by
  mistake, and vice versa. Building for any other OS is refused in one
  sentence; `make check-os` type-checks the platform you are not sitting at.
- **Not yet proven on real hardware.** Everything above is covered by the test
  suite and was driven end to end against a synthetic bottle; a launch of the
  real game on a real Mac has not happened yet.
  [Installing the engine, macOS](https://github.com/Benehiko/elden-ring-mods/blob/main/docs/install.md#macos)
  says what to expect.

### Safety

- **Never with anti-cheat.** The engine refuses to launch while Easy
  Anti-Cheat is running, and the runtime checks again inside the game before
  enabling anything. There is no bypass flag. Steam's Offline Mode is not
  required — the engine never starts the protected launcher.
- **The game install is never written to.** Everything the engine stages goes
  in the Wine prefix, and `ermod-engine uninstall` removes it again.
- **Your own save is only read**, including when the engine looks inside it
  to name your characters. The one command that writes it is `profile
  export`, which you have to ask for by name.
- **An unknown game build disables everything** rather than guessing at
  addresses that have moved.
- **Which file is the game is decided by reading it, not by its name.** The
  rule is "launch the game, never Easy Anti-Cheat", and it is kept by asking
  each executable what it is — every Windows binary records its own name
  inside itself, and copying or renaming a file does not change that. So an
  executable that has been renamed cannot smuggle Easy Anti-Cheat past the
  rule, and cannot hide the game from it either.
- **You can check what the game talks to.** `ermod-engine dev egress` reports
  every host the running game is connected to and says whether any of them is
  FromSoftware's. Worth knowing what it found: a modded session reaches no
  FromSoftware server, but it is not silent either — Elden Ring ships Epic
  Online Services and that dials `epicgames.dev` on its own, in a vanilla
  session as much as a modded one. The engine does not cause it and will not
  claim it does not happen. The command opens no connection itself.

### Knowing what you are running

- `ermod-engine --version` reports the engine, the mod front end it was built
  against, and the game builds it supports.
- If the installed game is not supported, the launcher says so before
  launching, in the terminal, and names what it does support.
- The launcher warns if the runtime beside it is from a different build,
  which is what a half-finished unpack over an older release looks like.
- `--help` and `--help-test` are styled when printed to a terminal: bold
  headings, subcommands in colour, arguments and flags picked out, and a blank
  line between entries so each command reads as its own block. Piped into a
  file or pager, with `NO_COLOR` set, or on `TERM=dumb`, the output is plain
  text, unchanged.
