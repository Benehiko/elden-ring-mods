# Writing mods in Lua

A mod is one Lua file. The same file runs two ways: `ermod-engine mod bake` executes it
on the host and writes a patched `regulation.bin` the engine loads with
`--regulation`, and the engine executes it inside the running game, where the writes land in live
memory. That is the promise the engine is built around, **author live, ship
offline**, and it is one code path, not two implementations that happen to
agree.

This document is the reference for writing that file. For how the offline
backend works underneath, see [architecture.md](architecture.md#applying-lua-mods-offline).

## The shortest whole mod

```lua
local mod = {
  name = "level60",
  version = "1.0.0",
  run_at = "launch",
  permissions = { "params", "log" },
}

function mod.on_launch(sdk)
  local row = sdk.params.row(sdk.params.file.CharaInitParam, 3000)   -- Vagabond
  sdk.log.info("Vagabond was level " .. row.soulLv)
  row.soulLv = 60
end

return mod
```

Run it against your install:

```sh
GAME="$HOME/.local/share/Steam/steamapps/common/ELDEN RING/Game"
mkdir -p mod
ermod-engine mod bake "$GAME/regulation.bin" mod/regulation.bin my_mod.lua
```

The game's file is read, never written. Everything lands in the output copy,
which the engine loads with `--regulation`. `mod bake` does not create the output
directory, hence the `mkdir`. See [deploy.md](deploy.md).

## Anatomy

A mod script returns one table. Five fields declare what it is (the last is
optional), and one function is its entry point.

| Field         | Meaning                                                                                                              |
| ------------- | -------------------------------------------------------------------------------------------------------------------- |
| `name`        | Identity. Appears in every log line (`mod[level60] info: …`) and owns the mod's param writes in the conflict ledger. |
| `version`     | Free-form string; carried, not interpreted.                                                                          |
| `run_at`      | `"launch"` or `"events"`, which decides when the engine runs it (below).                                             |
| `permissions` | The SDK modules it may touch, and the game rules it may set. This list is the whole of what the mod can reach.       |
| `mods`        | Optional. The names of other mods, which makes this mod a [mod pack](#mod-packs).                                    |

The manifest is parsed strictly. A `run_at` that is not one of the two names,
a permission that names neither a module nor a game rule, a missing field, or a manifest whose
declared entry point does not exist are each a load-time error rather than a
surprise later. A mod that declares when it runs but has no function to run
is a packaging mistake worth catching before the game starts.

### `run_at = "launch"`, entry point `on_launch(sdk)`

Runs once, at load. This is the kind of mod that edits data: params in,
params out, done. It is the only kind `ermod-engine mod bake` accepts, because it is
the only kind that means anything without a game running.

In-game, "at load" means the first rendered frame after the game's param
tables exist, not the moment the runtime attaches. A param mod that ran
earlier would have no tables to write to. A hot reload re-runs `on_launch`.

### `run_at = "events"`, entry point `setup(sdk)`

`setup` runs once and registers handlers; the handlers do the work when the
engine fires an event.

```lua
local mod = {
  name = "rune-counter",
  version = "1.0.0",
  run_at = "events",
  permissions = { "hooks", "log" },
}

local total = 0

function mod.setup(sdk)
  sdk.hooks.on(sdk.hooks.event.on_rune_gain, function(event)
    total = total + event.amount
    sdk.log.info(string.format("gained %d runes (session total %d)", event.amount, total))
  end)
end

return mod
```

Event mods are **in-game only**. `ermod-engine mod bake` refuses one rather than
silently doing nothing, because offline there is nothing to fire:

```text
bake: examples/rune_counter.lua is an event mod (events); event mods run in-game only
```

State kept in an upvalue (`total` above) is private to that mod. Each mod
gets its own Lua VM, so one mod cannot see or corrupt another's variables. It
does not survive a hot reload, which is a fresh VM; anything that must
outlive one belongs in `store`.

## Permissions are the sandbox

`permissions` is not a checklist the engine consults at each call. The `sdk`
table a mod receives is _built_ from it: an undeclared module is not present
at all, so `sdk.ui` is nil in a mod that did not ask for `ui`. A data-only
mod cannot draw, and cannot be made to draw by a bug.

The twelve modules are `log`, `hooks`, `params`, `perf`, `store`, `ui`,
`screen`, `watch`, `rules`, `bosses`, `trace` and `coop`. What each offers is in
[Modules](#modules) below. `rules` puts `sdk.rules` on the table and covers every game rule;
which rules a mod changes is what it sets, and that is what the engine checks
against other mods. `sdk.items` is on every table: it is read-only data and
needs no permission.

Around that, the VM itself is narrow. Only `base`, `table`, `string` and
`math` are opened. `io`, `os`, `package` and `debug` never are, and the
code-loading globals (`load`, `loadfile`, `dofile`, `require`, `loadstring`)
are removed from `base` afterwards, so a mod cannot pull in a new chunk or
reach native code. There is no `require`: one file is one mod.

The sandbox is the same offline. A mod reaching for `os` fails on the host
exactly as it would in your session, at the same line:

```text
mod[bad-sandbox] err: bad_sandbox.lua:19: attempt to index a nil value (global 'os')
bake: examples/bad_sandbox.lua errored in on_launch (RuntimeError)
```

### Budgets and strikes

Every call into Lua, meaning `on_launch`, `setup` and each handler, runs
under an instruction budget (10 000 000 instructions by default), counted by
the VM itself. A runaway loop is cut off and reported instead of hanging the
frame it was called from. Overrunning the budget disables the mod on the spot;
a handler that _errors_ is given three strikes first, since a bug that fires
on one code path should not cost a mod that works the rest of the time. A
disabled mod stops receiving events and says so once in the log. The other
mods are unaffected.

Offline the same model applies, so a mod too slow to finish `on_launch`
in-game is refused by `mod bake` rather than shipping.

## Modules

Full signatures live in `stubs/ermod.lua` (generated by the engine and
committed, so editor completion needs no build). What follows is what each
module is _for_, and what it costs.

### Naming game things: enums

Every game property a mod names (an event, a stat, a param file) has an
enum on the module that takes it:

| Enum              | Names                                                                                                                    | Used by                     |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------ | --------------------------- |
| `sdk.hooks.event` | `on_present`, `on_rune_gain`, `on_death`                                                                                 | `hooks.on`                  |
| `sdk.watch.stat`  | `deaths`, `runes`, `level`, the eight attributes, `hp`, `hp_max`                                                         | `watch.on`, `watch.get`     |
| `sdk.params.file` | `CharaInitParam`, `ItemLotParam_enemy`, `ItemLotParam_map`, `EquipParamWeapon`, `EquipParamProtector`, `EquipParamGoods` | `params.row`, `params.rows` |

```lua
sdk.hooks.on(sdk.hooks.event.on_death, function() ... end)
sdk.watch.on(sdk.watch.stat.hp, function(ch) ... end)
local row = sdk.params.row(sdk.params.file.CharaInitParam, 3000)
```

Write names this way. Three things follow from it:

- **The editor checks them.** Each enum is a LuaLS `---@enum` in
  `stubs/ermod.lua`, generated from the engine's own list, so completion
  offers exactly the names that exist, each with a one-line description.
- **A typo fails where it is written.** Indexing a name that does not exist
  (`sdk.hooks.event.on_deth`) is an error on that line, `unknown event
'on_deth'`, not a `nil` passed on to a call that then fails somewhere less
  obvious, or a handler that never fires.
- **A value is its own name.** `sdk.watch.stat.hp == "hp"`, so a handler
  can compare `ch.stat == sdk.watch.stat.hp`, a value logs readably, and a
  mod written with plain strings (`hooks.on("on_death", …)`) still works.

`pairs` over an enum lists what exists, so a mod that wants every stat need
not hard-code them. [`enums.lua`](../examples/enums.lua) shows all of this
in one file.

### `log`

`log.info(msg)`, `log.warn(msg)`, `log.error(msg)`. Lines are tagged with the
mod's name by the engine, so a mod cannot forge another's attribution.

### `params`

The one module that works both in-game and offline, and the reason the same
file ships.

```lua
local file = sdk.params.file.CharaInitParam
local row = sdk.params.row(file, 3000)  -- nil if no such row
row.soulLv = 60                         -- write by field name

for r in sdk.params.rows(file) do       -- every row, table order
  if r.id >= 3000 and r.id <= 3009 then r.baseVit = 30 end
end
```

Files are named by `sdk.params.file`, which lists exactly the files the
engine can open (a plain string, with or without `.param`, still works).
Field names are the paramdef's own (`soulLv`, `baseVit`, …). Reads and writes are typed from the engine's
paramdefs, and a write goes straight into the table's bytes. In-game that is
live memory and takes effect immediately; offline it is the unpacked
archive's bytes, packed at the end.

Two things to know:

- **Row ids are not unique.** Most tables key cleanly, but some ship
  duplicates (`RandomAppearParam` has 26). `row(file, id)` resolves to the
  _first_ descriptor with that id; later copies are reachable only by
  iterating with `rows`.
- **A param needs a paramdef in the engine.** Five are supported today:
  `CharaInitParam`, `ItemLotParam`, `EquipParamWeapon`,
  `EquipParamProtector`, `EquipParamGoods`. The game loads item lots only
  as `ItemLotParam_enemy` and `ItemLotParam_map`, so those are the names
  `sdk.params.file` offers. A file without a paramdef has no entry, and
  naming it (`sdk.params.file.GameAreaParam`) is an error naming the file,
  in-game and offline alike.

The field names are Paramdex's: each param's PARAMDEF XML in
[soulsmods/Paramdex `ER/Defs/`](https://github.com/soulsmods/Paramdex/tree/master/ER/Defs)
lists every field a row has, by the name a mod uses.

### `hooks`

`hooks.on(event, handler)`, with the event named by `sdk.hooks.event`:

```lua
sdk.hooks.on(sdk.hooks.event.on_death, function() sdk.log.info("died") end)
```

Five events exist: `on_boss_defeated` (payload `{ id, flag, kind }`, see
`bosses`), `on_evergaol_entered` (payload `{ id }`), `on_present` (a frame is about to be presented, payload
`{}`), `on_rune_gain` (payload `{ amount = n }`) and `on_death` (payload
`{ deaths = n }`: the character's lifetime death count, this death included).
`deaths` is the game's own counter, saved with the character, the same value
`sdk.watch.get(sdk.watch.stat.deaths)` reads at any time; a mod that wants a
count since it loaded keeps its own (`examples/death_ping.lua` shows both).
Indexing an event that does not exist (`sdk.hooks.event.on_levelup`)
is an error where it is written, and an unknown name passed as a string is an
error at subscribe time: never a handler that silently never fires.

`on_present` runs on the render thread, once per frame. It is the budget's
sharpest edge: whatever it does is paid every frame, so measure it with
`ermod-engine mod perf` before shipping.

### `watch`

`hooks` reports _events_; `watch` reports _values_: a number the game keeps
changed, from what to what.

```lua
sdk.watch.on(sdk.watch.stat.hp, function(ch)
  sdk.log.info(string.format("%s %d -> %d (%+d)", ch.stat, ch.old, ch.new, ch.delta))
end)
local vigor = sdk.watch.get(sdk.watch.stat.vigor)  -- nil when it cannot be read
```

`watch.on(stat, handler)` calls `handler` with `{ stat, old, new, delta }` on
the frame the value changes. `watch.get(stat)` reads it now. Stats are named
by `sdk.watch.stat` ([enums](#naming-game-things-enums)): indexing one that
does not exist (`sdk.watch.stat.mana`) is an error where it is written, and an
unknown name passed as a string is an error at subscribe time.

| Stat                                                                                     | Meaning                                                                               |
| ---------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| `deaths`                                                                                 | Times the current character has died                                                  |
| `runes`                                                                                  | Runes held (not the ones lying where the character last died)                         |
| `level`                                                                                  | Rune level                                                                            |
| `vigor`, `mind`, `endurance`, `strength`, `dexterity`, `intelligence`, `faith`, `arcane` | The eight attributes, one stat each                                                   |
| `hp`                                                                                     | Current HP of the local player                                                        |
| `hp_max`                                                                                 | Maximum HP; moves with vigor, buffs and talismans                                     |
| `coop_distance`                                                                          | Whole metres to the nearest other player in a co-op session; `nil` when there is none |

FP, stamina and flasks are not watchable yet, on purpose: none has an offset
derived from the game, and a guessed one would report a confident wrong
number.

Every value is `nil` outside a loaded world, and nothing fires there. The
first readable frame is a baseline, not a change, so loading a save does not
report the whole rune balance; a load or a death's reload makes the next
reading a new baseline. `hp` and `hp_max` read about a second after the world
loads. Changes fire after `on_death` and `on_rune_gain`, before
`on_present`, at most once per stat per frame, under the same budget and
strikes as `hooks`. [`watch_all.lua`](../examples/watch_all.lua) watches
every stat and is the quickest way to see them move.

### `ui`

An immediate-mode overlay (Dear ImGui, drawn in the present hook). Windows,
text, buttons, checkboxes, sliders, text input, combos, plots, progress bars,
collapsible sections (`collapsing(label, default_open)`) and tree nodes
(`tree(label, body, default_open)`).

```lua
sdk.ui.window("Example Settings", function()
  local v = sdk.ui.checkbox("Enabled", enabled)
  if v ~= enabled then enabled = v; sdk.store.set("enabled", v) end
end, { x = 20, y = 300, flags = { "auto_size" } })
```

**Where a window goes.** `x` and `y` count inward from the window's `anchor`
corner: `"top_right"` (the default, clear of the game's health, FP and
stamina bars), `"top_left"`, `"bottom_left"` or `"bottom_right"`. Positions
and sizes are in 1080p pixels and scale with the display, and no window takes
more than 40 % of the screen's width or 70 % of its height; longer content
scrolls. A window that used to sit at a position counted from the top-left
corner needs `anchor = "top_left"` to stay there.

Immediate mode means the widgets exist only while you are drawing them, so
every `ui` call is legal **only inside a frame**: from a handler running
during `on_present`, or the state events derived from it. Calling one from
`on_launch` is an error. Widgets that edit a value take the current value and
return the new one, so the mod owns the state; labels are unique per window,
and `"Label##id"` disambiguates two that must read the same.

`Insert` toggles whether the overlay takes input focus; `ui.focused()` says
whether it currently has it, and is the one `ui` call legal outside a frame
(it answers `false` when there is no overlay at all). Offline, `ui` reports
itself unavailable, because there is no frame to draw on.

### `perf`

`frame_ms()`, `fps()`, `frame()`, `now_ms()` and `mods()`, the last returning
every loaded mod's handler cost (`last_ms`, `avg_ms`, `total_ms`, `calls`),
not only the caller's. A performance-monitor mod is `perf` plus `ui` and
nothing else.

`spikes()` counts stutters: `{ count, last_ms, last_frame }`, meaning how many
frames since the game started took more than twice the typical frame time
(or 8 ms longer, whichever is larger), how long the latest one took, and
which frame it was. It uses the same rule as the engine's frame tracer, so a
mod's count and an `ermod-engine trace report` agree. To find out _why_ the
frames were slow, use the tracer; see [Finding stutters](performance.md).

### `store`

`get(key, default)`, `set(key, value)` (nil deletes), `keys()`. Strings,
numbers and booleans; keys match `[A-Za-z0-9_.-]+`. Per-mod and persistent.
This is the only filesystem access a mod has, and where the file lives is the
engine's business, not the mod's. Read at setup, write when a value changes.

### `screen`

`capture([name][, scale])` writes the next presented frame, overlay included,
as a PNG, and returns the path it will appear at (or nil and a reason). It
is the engine reading back its own swapchain, so what you get is exactly what
the game presented; see [frame captures](#frame-captures).

### `rules`

Engine-wide game rules, read and set as fields: `sdk.rules.boss_spectate =
false`. Any rule can be read. Setting one needs the `rules` permission,
takes a boolean, and works only from the entry point. An unknown name is an
error.

| Rule                     | Default | Meaning                                                                                                                                  |
| ------------------------ | ------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `boss_spectate`          | `true`  | In a fog-wall boss fight, a player who dies while a teammate lives is held and watches a survivor. Off, they respawn at the grace.       |
| `spirit_summon_anywhere` | `false` | Spirit ashes work outside summoning pools: one spirit at a time, and it stays with the player. Inside a pool the game's own rules apply. |

A rule set by a mod returns to its default when the mod is unloaded or
switched off. Rules exist only in the running game; `mod bake` has nowhere to
write one, so offline a rule reads as its default and setting it does
nothing.

### `items`

Every item, spell, skill and class the game names, as tables from a name to
its row id, with `sdk.items.file` naming the param file the ids are rows of.
On every `sdk`; no permission.

```lua
local row = sdk.params.row(sdk.items.file.classes, sdk.items.classes.wretch)
row.HpEstMax = 6                                     -- starting Crimson flasks
row.item_01 = sdk.items.upgrade_materials.golden_seed
```

The tables: `consumables`, `key_items`, `crafting_materials`,
`remembrances`, `sorceries`, `incantations`, `spirit_ashes`,
`crystal_tears`, `notes`, `upgrade_materials` (all `EquipParamGoods`),
`weapons`, `armor`, `talismans`, `ashes_of_war`, `skills` and `classes`. A
name is the English display name in lower case with words joined by `_`
(`flask_of_crimson_tears_plus_4`); the stub lists every one. Indexing a name
that does not exist is an error.

### `bosses`

Every boss the game awards a clear for — the base game and Shadow of the
Erdtree, field bosses included — with what a mod needs to reuse its fight.
Needs the `bosses` permission.

**Naming a boss.** `sdk.bosses.id.<name>` is the boss's id, an enum like
`sdk.items` (`sdk.bosses.id.margit_the_fell_omen`; a wrong name is an error,
and the stub lists every one). Every function also takes the plain id (the
boss's row, or its defeat flag). Almost every boss has a name, spelled as the
game spells it (210 of 212: `sdk.bosses.id.starscourge_radahn`); the rest
are `boss_<id>`. A boss's `name_measured` is true where the name was read off
the boss itself in the game, and false where it was assigned by encounter
and not yet checked live. `sdk.bosses.all` lists every boss and `sdk.bosses.find(id)`
returns one: `key`, `display_name`, `map`, `dlc`, `runes`, and where it has
been measured, `idle_pos` (where it waits before its fight — some wait
outside the arena), `arena` and `fight_pos` (where a recorded fight began and
where the boss fought), `bodies` (an encounter can be several: a duo, a
second phase, waves) and `npc_param`.

**Bringing one back.** `revive(id)` and `revive_all({ base = true, dlc =
true })` clear the boss's defeat record; the boss is back the next time its
map loads (rest at a grace, warp or die). Its one-off drop does not come
back; its runes do.

```lua
sdk.bosses.revive(sdk.bosses.id.margit_the_fell_omen)
```

**What kind of fight.** Each boss has `kind`: `"evergaol"`,
`"minor_erdtree"` (an Erdtree or Putrid Avatar), `"field"` (any other
open-world boss) or `"arena"` (a dungeon's boss room); `sdk.bosses.kind` is
the enum. `phases` is how many kills the game needed before it recorded the
defeat, where measured: each body or phase that comes back counts, so 1 is
one body with no second phase. An evergaol boss has `evergaol`, the
evergaol's name. `grace` is the grace `warp` travels to.

**Running a fight.** `warp(id)` travels to the boss's grace with the game's
own grace warp and stands the player beside the boss once it has loaded.
`wake(id)` starts the fight (the boss's AI wakes; the fog's music and boss
area are the event script's and do not start). `kill(id)` runs the game's
own death routine, and the game records the defeat itself; a boss with more
`phases` needs a kill for each. `reset(id)` makes the fight new again: the
defeat record and, for an evergaol, its own state. It lands when the map
next loads. A woken boss fights for real, so `wake` does not protect the
player.

```lua
local B = sdk.bosses
B.reset(B.id.margit_the_fell_omen)
B.warp(B.id.margit_the_fell_omen)
sdk.hooks.on(sdk.hooks.event.on_boss_defeated, function(ev)
  sdk.log.info(string.format("%d down (%s)", ev.id, ev.kind))
end)
```

`hooks.event.on_boss_defeated` fires when a boss dies and the game records
it: `{ id, flag, kind }`.

**Where a boss is.** `boss.spawns` lists where the boss was recorded:
`{ phase, entity, map, pos }` for `"idle"` (waiting before its fight),
`"fight"` (when the fight started) and `"kill1"`, `"kill2"`, … (each body
that had to be killed, so a second phase shows up as `kill2`). `pos` is
comparable with `player_pos()` near the boss; `map` is the boss's map block.
The list is empty for a boss not recorded yet.

**Evergaols: open them for the player, or let the player do it.** An
evergaol boss has `can_open` set when the SDK can open its evergaol.
`warp(id, { open = true })` warps there, opens the evergaol and walks the
player up to the boss. Plain `warp(id)` stands the player on the evergaol's
pad and leaves the opening to them. `open(id)` opens it when the player is
already near. Either way, `hooks.event.on_evergaol_entered` fires with
`{ id }` once the player is inside. The opening uses the game's own
controls, so it works while the game window has focus, which it does while
someone is playing.

```lua
local B = sdk.bosses
local bols = B.id.bols_carian_knight
B.reset(bols)                      -- a fresh evergaol, at the next map load
B.warp(bols, { open = true })      -- or B.warp(bols) to let the player open it
sdk.hooks.on(sdk.hooks.event.on_evergaol_entered, function(ev)
  sdk.log.info("in the evergaol of " .. ev.id)
end)
```

**Watching a fight.** `state(id)` is a loaded boss's live state — `alive`,
`hp`, `hp_max`, `pos`, and `bodies` / `bodies_alive` for every loaded body of
the encounter (it is alive while any body lives) — or nil when it is not
loaded; refreshed twice a second. `player_pos()` is the player's position,
`in_fight()` is true from the moment the player passes a boss's fog until it
dies, and `fight_entry()` is where the player stood when the fight began.
Positions are comparable within an arena, not across the world.

**Stats, and changing them while the fight runs.** `stats(id)` is the boss's
stats: `hp`; `damage_taken`, a multiplier on HP damage per damage type
(`neutral`, `slash`, `blow`, `thrust`, `magic`, `fire`, `thunder`, `dark`;
below 1 it resists that type, above 1 it is weak to it); `status_resist`,
how much build-up of each status (`poison`, `disease`, `blood`, `curse`,
`sleep`, `madness`) it takes before the status triggers; and `buffs`, its
resident effects. `stats(id, { default = true })` gives them as they were
before any change. `stat(id, field)` and `set_stat(id, field, value)` read and
write any field of the boss's NpcParam row, **at any time**, and
`reset_stats(id)` restores it. `set_hp`, `set_hp_max` and `set_immortal` act
on a live body (a lethal hit leaves an immortal body at 1 HP), which is how a
fight gets stages:

```lua
-- in an on_present handler: hold the boss at 1 HP, then refill it, harder
local s = sdk.bosses.state(boss)
if s and s.hp <= 1 and stage < 3 then
  stage = stage + 1
  sdk.bosses.set_stat(boss, "neutralDamageCutRate", 0.8 ^ stage)
  sdk.bosses.set_hp(boss, s.hp_max)
  sdk.bosses.set_immortal(boss, stage < 3)
end
```

`examples/boss_phases.lua` is the whole mod. A stat change applies to every
character using that NpcParam row.

### `trace`

A read-only view of a co-op session, for finding out why two players' games
disagree. Needs the `trace` permission. Nothing in it changes the game.

- `session()` gives the session's role (`"solo"`, `"host"`, `"joiner"`) and
  whether you are in a world.
- `player()` is you, `peers()` is the other players' bodies as your game
  shows them, and `chrs(radius)` is every character near you, nearest first.
  Each entry has its position, HP, whether it is dead or faded out, and who
  controls it. Its `sync` part says whether the owner's updates arrive. A
  character's `key` names the same enemy on every machine, so two players'
  logs can be matched on it.
- `barriers()` counts how often the game tried to wall in or warp back a
  player at the edge of the session's area.
- `remotes()` is every other machine's own view, which each one sends once a
  second. The host can therefore show and log the whole session.
- `jumps(after)` lists remote players' bodies that moved 10 m or more in a
  single frame.

The view is refreshed every 30 frames in a world, and `generation()` changes
when a new one lands. When the engine cannot read the co-op state on your
game build, `in_world` stays false and every list is empty.
`examples/coop_trace.lua` draws all of it, flags frozen enemies, corpses
still standing on another screen and faded-out players, and is the place to
start.

### `coop`

The co-op session, for mods that decide things per player, and the share of
runes your character takes. Needs the `coop` permission.

In a co-op session every player gets the full runes of every enemy any
player kills, and of every boss, however far apart they stand. That is the
default and needs no mod. Each character's own rune bonuses, such as a rune
talisman, still apply on top. A mod can change the share for the player
whose machine runs it:

```lua
sdk.hooks.on(sdk.hooks.event.on_present, function()
  if not sdk.coop.active() then return end
  local d = sdk.coop.get_distance()  -- metres, or nil when nobody is nearby
  if d and d <= 100 then sdk.coop.set_rune_rates({ enemy = 1, boss = 1 })
  else sdk.coop.set_rune_rates({ enemy = 0.25, boss = 0.5 }) end
end)
```

- `active()` is whether you are hosting or have joined a session, in a world.
  `is_host()` is whether you host it.
- `get_distance()` is the metres to the nearest other player loaded in your
  world, or nil. `distances()` lists every other player's distance, nearest
  first. `sdk.watch.stat.coop_distance` is the same distance in whole metres,
  as a watchable value.
- `set_rune_rates({ enemy = ..., boss = ... })` sets your character's share
  of every enemy kill and of every boss: 1 is the full amount (the default),
  0.25 a quarter, 0 none, at most 10. A field left out keeps its value.
  `rune_rates()` reads them back.

The rates are your machine's own. They change what your character gets,
nobody else's, and only in a session. A group that wants one rule for
everyone runs the same mod on every machine. Setting rates does not count
as changing the game, so it does not have to match the host's mods to join.
`examples/coop_runes.lua` is the whole mod.

## The author loop

### Offline

```sh
ermod-engine mod verify my_mod.lua                    # would it load in-game?
ermod-engine mod perf  my_mod.lua                    # what does it cost per event?
mkdir -p mod
ermod-engine mod bake "$GAME/regulation.bin" mod/regulation.bin my_mod.lua
```

`mod verify` runs the game's own loader, sandbox and manifest rules on the host,
so "passes `mod verify`" means "would load in-game". It prints one line per mod
and exits 1 if any would fail, which makes it a pre-commit hook:

```text
examples/level60.lua: ok  name=level60 run_at=launch entry=on_launch permissions=params,log
examples/rune_counter.lua: ok  name=rune-counter run_at=events entry=setup permissions=hooks,log
```

`mod verify` answers "would it _load_", not "does it work". `bad_sandbox.lua`
passes `mod verify` and then fails at the first line of its entry point, which is
the distinction.

`mod perf` fires a synthetic session against the real budget model and the real
dispatcher:

```text
$ ermod-engine mod perf examples/overlay.lua --frames 120 --runes 5 --deaths 1
examples/overlay.lua: hud-overlay (events mod) — synthetic session: 120 frames, 5 rune pickups, 1 deaths
host pre-flight: no live params (params calls fail as they do before the tables load), recording overlay, in-memory store

start (setup): 0.029 ms

event          handlers   fires   total ms    avg/fire ms   max/fire ms
on_present            1     120      1.376        0.0115        0.0624
on_rune_gain          1       5      0.011        0.0021        0.0058
on_death              1       1      0.001        0.0008        0.0008

worst on_present frame cost 0.0624 ms = 0.37% of a 60 fps frame
strikes 0/3; mod still active at end of session
```

It is a pre-flight, not a promise: there is no game, so the overlay records
instead of drawing and the store lives in memory. Without `--regulation`,
`params` is unavailable exactly as it is before the tables load, which means
a _launch_ mod dies at its first `params` call. Give it a `regulation.bin`
and `on_launch` runs against the unpacked archive, so launch mods get an
honest number too:

```text
$ ermod-engine mod perf examples/level60.lua --regulation "$GAME/regulation.bin"
examples/level60.lua: level60 (launch mod) — synthetic session: 600 frames, 10 rune pickups, 1 deaths
host pre-flight: params from /home/you/.local/share/Steam/steamapps/common/ELDEN RING/Game/regulation.bin (unpacked, never written back), recording overlay, in-memory store

start (on_launch): 0.292 ms
start wrote 90 param field(s) (into memory; nothing is packed)

event          handlers   fires   total ms    avg/fire ms   max/fire ms
on_present            0     600      0.065        0.0001        0.0006
on_rune_gain          0      10      0.001        0.0001        0.0002
on_death              0       1      0.000        0.0001        0.0001

worst on_present frame cost 0.0006 ms = 0.00% of a 60 fps frame
strikes 0/3; mod still active at end of session
```

Nothing is written back; `mod perf` never produces a file.

`mod bake` is the real run. Its log is the mod's own:

```text
$ ermod-engine mod bake "$GAME/regulation.bin" mod/regulation.bin examples/level60.lua
mod[level60] info: Vagabond: level 9 -> 60
…
mod[level60] info: Wretch: level 1 -> 60
mod[level60] info: level60 applied to 10/10 classes
bake: 90 Lua field write(s) from 1 mod(s)
applied 0 spec patch(es) across 0 param(s) -> mod/regulation.bin (1910224 bytes)
```

The engine's two built-in patch specs (`level60` and `class-gear`) and `.lua`
mods mix on one command line (`… level60.lua class-gear`). The specs are
applied first; both feed one write ledger, so a built-in patch and a Lua
write on the same field collide like any two mods.

### In-game

Drop the file in the engine's mods directory and it loads at launch:

```text
~/.local/share/ermod/mods
```

`ermod-engine install my_mod.lua` copies it there for you. The game, under
Wine, sees the directory as `C:\ermod\mods`, the name the log uses. One
`.lua` file per mod, no subdirectories, nothing to register them in.

While authoring, prefer `ermod-engine --mods <dir>`: it points that directory
at your working tree, so the file you edit is the file the game loads. Save,
and the running game picks it up within about a second. A launch mod re-runs
`on_launch`, an event mod re-registers its handlers, and the old VM is
closed. A reload that fails keeps the previous version running and says why.
`--mods` lasts one launch: a launch without it points the game back at
`~/.local/share/ermod/mods`.

Remember a reload is a fresh VM: upvalues reset, `store` does not.

### Frame captures

`sdk.screen.capture()`, or `ermod-engine shot` from a terminal, writes a PNG
of the presented frame, overlay included. "Did my overlay draw?" then has an
answer you can open, rather than a memory of the screen:

```sh
ermod-engine shot --out shot.png
```

## Conflicts

Every param write is recorded as `(mod, table, row, field)`. When two
_differently named_ mods write the same field, the policy depends on where
you are:

**Offline it is an error.** The file a player loads must not depend on the
order two mods were listed in, so `mod bake` names both mods and the field,
refuses to pack, and writes no output file:

```text
bake: conflict — class-tweaks wrote CharaInitParam[3000].soulLv, already written by level60
bake: refusing to pack; resolve the overlap or bake one mod at a time (1 conflicting write(s))
```

A half-patched archive is worse than none, so every refusal exits 1 having
written nothing: an event mod, a sandbox escape, a budget overrun, a conflict.

**In-game it is checked before anything lands.** The engine runs each mod's
entry point with its param and rule writes held back. The mod reads back what
it wrote, so it behaves as it would for real, but the game sees nothing yet.
When every mod has run, the engine compares what they want and applies only
what passes:

| Two mods set one thing to different values | Result                                                              |
| ------------------------------------------ | ------------------------------------------------------------------- |
| both standalone                            | neither loads                                                       |
| both in mod packs, different packs         | neither pack loads, nor their members                               |
| one in a pack, one standalone              | the pack's value lands; the standalone mod loads without that write |
| the same mod, or the same pack             | no conflict; the pack's own script has the last word                |

The same value from two mods is never a conflict. A mod already running keeps
its place: a mod added or edited later that disagrees with it is the one
refused, and an edited mod that is refused keeps its previous version
running. Every refusal names both mods, the setting and both values:

```text
mod[engine] warn: b.lua not loaded: it sets rule boss_spectate to true, but a.lua (already running) sets it to false
```

The check can only see writes made before it runs, so configuration is
locked once the entry point returns. A `params` or `rules` write from an
event handler is an error. A mod whose entry point errors lands none of its
writes. The one deliberate exception is `sdk.bosses.set_stat`, which changes
a boss's own stats while its fight runs; each such write is still recorded
against the mod that made it.

A mod edited in place is compared as itself, so hot reload never conflicts
with the version it replaces.

## Mod packs

A mod whose manifest lists `mods` is a mod pack:

```lua
local pack = {
  name = "boss-rules-pack", version = "1.0.0", run_at = "launch",
  permissions = { "rules", "log" },
  mods = { "level60" },
}

function pack.on_launch(sdk)
  sdk.rules.boss_spectate = false
end

return pack
```

Members are named by their manifest `name` and are ordinary mods in the same
mods directory, each with its own permissions. A pack does not stop other
mods from loading. It decides the settings it and its members make: against
a standalone mod the pack's value lands (see [Conflicts](#conflicts)).

A pack loads whole or not at all. A member refused for a conflict refuses
its pack, and a refused pack refuses its members. A pack that lists a mod
which is not loaded says so in the log and loads anyway. Within a pack,
members commit first and the pack's own script last, so a setting both make
ends at the pack's value and is judged by it.

## Editor setup

`stubs/ermod.lua` carries LuaLS annotations for the whole SDK and is
committed, so completion and type checking need only a path:

```json
{ "workspace.library": ["path/to/elden-ring-mods/stubs"] }
```

Regenerated by the engine (`make stubs` there) after an SDK change; `make check-stubs` here fails on drift.

## Example mods

`examples/` holds one worked example per SDK slice, the best place to read
working code, and the loader's own test corpus: `level60.lua` (params, the
reference gameplay mod and the offline golden test's subject),
`rune_counter.lua` (hooks and per-mod state), `enums.lua` (naming events,
stats and param files by enum), `settings.lua` (ui plus store),
`perf_monitor.lua` (ui plus perf), `overlay.lua` (ui plus hooks),
`boss_rules_pack.lua` (a mod pack setting a game rule), `boss_rematch.lua`,
`boss_watch.lua` and `boss_phases.lua` (bosses: revive, watch, stats and stages),
`coop_runes.lua` (coop: a player's rune share by distance to the others), and
`bad_sandbox.lua`, which exists to be refused. The reading order is in
[`examples/README.md`](../examples/README.md).
