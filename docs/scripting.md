# Writing mods in Lua

A mod is one Lua file. The same file runs two ways: `ermod-engine apply` executes it
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
  local row = sdk.params.row("CharaInitParam", 3000)   -- Vagabond
  sdk.log.info("Vagabond was level " .. row.soulLv)
  row.soulLv = 60
end

return mod
```

Run it against your install:

```sh
GAME="$HOME/.local/share/Steam/steamapps/common/ELDEN RING/Game"
mkdir -p mod
ermod-engine apply "$GAME/regulation.bin" mod/regulation.bin my_mod.lua
```

The game's file is read, never written. Everything lands in the output copy,
which the engine loads with `--regulation`. `apply` does not create the output
directory, hence the `mkdir`. See [deploy.md](deploy.md).

## Anatomy

A mod script returns one table. Five fields declare what it is (the last is
optional), and one function is its entry point.

| Field | Meaning |
| --- | --- |
| `name` | Identity. Appears in every log line (`mod[level60] info: …`) and owns the mod's param writes in the conflict ledger. |
| `version` | Free-form string; carried, not interpreted. |
| `run_at` | `"launch"` or `"events"`, which decides when the engine runs it (below). |
| `permissions` | The SDK modules it may touch, and the game rules it may set. This list is the whole of what the mod can reach. |
| `mods` | Optional. The names of other mods, which makes this mod a [mod pack](#mod-packs). |

The manifest is parsed strictly. A `run_at` that is not one of the two names,
a permission that names neither a module nor a game rule, a missing field, or a manifest whose
declared entry point does not exist are each a load-time error rather than a
surprise later. A mod that declares when it runs but has no function to run
is a packaging mistake worth catching before the game starts.

### `run_at = "launch"`, entry point `on_launch(sdk)`

Runs once, at load. This is the kind of mod that edits data: params in,
params out, done. It is the only kind `ermod-engine apply` accepts, because it is
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
  sdk.hooks.on("on_rune_gain", function(event)
    total = total + event.amount
    sdk.log.info(string.format("gained %d runes (session total %d)", event.amount, total))
  end)
end

return mod
```

Event mods are **in-game only**. `ermod-engine apply` refuses one rather than
silently doing nothing, because offline there is nothing to fire:

```
apply: examples/rune_counter.lua is an event mod (events); event mods run in-game only
```

State kept in an upvalue (`total` above) is private to that mod. Each mod
gets its own Lua VM, so one mod cannot see or corrupt another's variables. It
does not survive a hot reload, which is a fresh VM; anything that must
outlive one belongs in `store`.

## Permissions are the sandbox

`permissions` is not a checklist the engine consults at each call. The `sdk`
table a mod receives is *built* from it: an undeclared module is not present
at all, so `sdk.ui` is nil in a mod that did not ask for `ui`. A data-only
mod cannot draw, and cannot be made to draw by a bug.

The seven modules are `log`, `hooks`, `params`, `perf`, `store`, `ui` and
`screen`. What each offers is in [Modules](#modules) below.

Each game rule is a permission too, named after the rule. Holding any rule
permission puts `sdk.rules` on the table; setting a rule needs that rule's
own permission. The only rule so far is `boss_spectate`.

Around that, the VM itself is narrow. Only `base`, `table`, `string` and
`math` are opened. `io`, `os`, `package` and `debug` never are, and the
code-loading globals (`load`, `loadfile`, `dofile`, `require`, `loadstring`)
are removed from `base` afterwards, so a mod cannot pull in a new chunk or
reach native code. There is no `require`: one file is one mod.

The sandbox is the same offline. A mod reaching for `os` fails on the host
exactly as it would in your session, at the same line:

```
mod[bad-sandbox] err: bad_sandbox.lua:19: attempt to index a nil value (global 'os')
apply: examples/bad_sandbox.lua errored in on_launch (RuntimeError)
```

### Budgets and strikes

Every call into Lua, meaning `on_launch`, `setup` and each handler, runs
under an instruction budget (10 000 000 instructions by default), counted by
the VM itself. A runaway loop is cut off and reported instead of hanging the
frame it was called from. Overrunning the budget disables the mod on the spot;
a handler that *errors* is given three strikes first, since a bug that fires
on one code path should not cost a mod that works the rest of the time. A
disabled mod stops receiving events and says so once in the log. The other
mods are unaffected.

Offline the same model applies, so a mod too slow to finish `on_launch`
in-game is refused by `apply` rather than shipping.

## Modules

Full signatures live in `stubs/ermod.lua` (generated by the engine and
committed, so editor completion needs no build). What follows is what each
module is *for*, and what it costs.

### `log`

`log.info(msg)`, `log.warn(msg)`, `log.error(msg)`. Lines are tagged with the
mod's name by the engine, so a mod cannot forge another's attribution.

### `params`

The one module that works both in-game and offline, and the reason the same
file ships.

```lua
local row = sdk.params.row("CharaInitParam", 3000)  -- nil if no such row
row.soulLv = 60                                      -- write by field name

for r in sdk.params.rows("CharaInitParam") do        -- every row, table order
  if r.id >= 3000 and r.id <= 3009 then r.baseVit = 30 end
end
```

Field names are the paramdef's own (`soulLv`, `baseVit`, …); `.param` on the
file name is optional. Reads and writes are typed from the vendored
paramdefs, and a write goes straight into the table's bytes. In-game that is
live memory and takes effect immediately; offline it is the unpacked
archive's bytes, packed at the end.

Two things to know:

- **Row ids are not unique.** Most tables key cleanly, but some ship
  duplicates (`RandomAppearParam` has 26). `row(file, id)` resolves to the
  *first* descriptor with that id; later copies are reachable only by
  iterating with `rows`.
- **A param needs a vendored paramdef.** Five are generated today:
  `CharaInitParam`, `ItemLotParam`, `EquipParamWeapon`,
  `EquipParamProtector`, `EquipParamGoods`. Touching a param without one is
  an error naming the file, in-game and offline alike.

The paramdef XML in [`paramdefs/`](../paramdefs/) lists every field a row
has, by the name a mod uses, which is the quickest way to find what to write.

### `hooks`

`hooks.on(event, handler)`. Three events exist: `on_present` (a frame is
about to be presented, payload `{}`), `on_rune_gain` (payload
`{ amount = n }`) and `on_death` (payload `{}`). An unknown event name is an
error at subscribe time, not a handler that never fires.

`on_present` runs on the render thread, once per frame. It is the budget's
sharpest edge: whatever it does is paid every frame, so measure it with
`ermod-engine perf` before shipping.

### `ui`

An immediate-mode overlay (Dear ImGui, drawn in the present hook). Windows,
text, buttons, checkboxes, sliders, text input, combos, plots, progress bars.

```lua
sdk.ui.window("Example Settings", function()
  local v = sdk.ui.checkbox("Enabled", enabled)
  if v ~= enabled then enabled = v; sdk.store.set("enabled", v) end
end, { x = 20, y = 300, flags = { "auto_size" } })
```

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
false`. Any rule can be read. Setting one needs the permission of the same
name, takes a boolean, and works only from the entry point. An unknown name
is an error.

| Rule | Default | Meaning |
| --- | --- | --- |
| `boss_spectate` | `true` | In a fog-wall boss fight, a player who dies while a teammate lives is held and watches a survivor. Off, they respawn at the grace. |

A rule set by a mod returns to its default when the mod is unloaded or
switched off. Rules exist only in the running game; `apply` has nowhere to
write one, so offline a rule reads as its default and setting it does
nothing.

## The author loop

### Offline

```sh
ermod-engine check my_mod.lua                    # would it load in-game?
ermod-engine perf  my_mod.lua                    # what does it cost per event?
mkdir -p mod
ermod-engine apply "$GAME/regulation.bin" mod/regulation.bin my_mod.lua
```

`check` runs the game's own loader, sandbox and manifest rules on the host,
so "passes `check`" means "would load in-game". It prints one line per mod
and exits 1 if any would fail, which makes it a pre-commit hook:

```
examples/level60.lua: ok  name=level60 run_at=launch entry=on_launch permissions=params,log
examples/rune_counter.lua: ok  name=rune-counter run_at=events entry=setup permissions=hooks,log
```

`check` answers "would it *load*", not "does it work". `bad_sandbox.lua`
passes `check` and then fails at the first line of its entry point, which is
the distinction.

`perf` fires a synthetic session against the real budget model and the real
dispatcher:

```
$ ermod-engine perf examples/overlay.lua --frames 120 --runes 5 --deaths 1
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
a *launch* mod dies at its first `params` call. Give it a `regulation.bin`
and `on_launch` runs against the unpacked archive, so launch mods get an
honest number too:

```
$ ermod-engine perf examples/level60.lua --regulation "$GAME/regulation.bin"
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

Nothing is written back; `perf` never produces a file.

`apply` is the real run. Its log is the mod's own:

```
$ ermod-engine apply "$GAME/regulation.bin" mod/regulation.bin examples/level60.lua
mod[level60] info: Vagabond: level 9 -> 60
…
mod[level60] info: Wretch: level 1 -> 60
mod[level60] info: level60 applied to 10/10 classes
apply: 90 Lua field write(s) from 1 mod(s)
applied 0 spec patch(es) across 0 param(s) -> mod/regulation.bin (1910224 bytes)
```

The engine's two built-in patch specs (`level60` and `class-gear`) and `.lua`
mods mix on one command line (`… level60.lua class-gear`). The specs are
applied first; both feed one write ledger, so a built-in patch and a Lua
write on the same field collide like any two mods.

### In-game

Drop the file in the engine's mods directory and it loads at launch:

```
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
*differently named* mods write the same field, the policy depends on where
you are:

**Offline it is an error.** The file a player loads must not depend on the
order two mods were listed in, so `apply` names both mods and the field,
refuses to pack, and writes no output file:

```
apply: conflict — class-tweaks wrote CharaInitParam[3000].soulLv, already written by level60
apply: refusing to pack; resolve the overlap or apply one mod at a time (1 conflicting write(s))
```

A half-patched archive is worse than none, so every refusal exits 1 having
written nothing: an event mod, a sandbox escape, a budget overrun, a conflict.

**In-game it is checked before anything lands.** The engine runs each mod's
entry point with its param and rule writes held back. The mod reads back what
it wrote, so it behaves as it would for real, but the game sees nothing yet.
When every mod has run, the engine compares what they want and applies only
what passes:

| Two mods set one thing to different values | Result |
| --- | --- |
| both standalone | neither loads |
| both in mod packs, different packs | neither pack loads, nor their members |
| one in a pack, one standalone | the pack's value lands; the standalone mod loads without that write |
| the same mod, or the same pack | no conflict; the pack's own script has the last word |

The same value from two mods is never a conflict. A mod already running keeps
its place: a mod added or edited later that disagrees with it is the one
refused, and an edited mod that is refused keeps its previous version
running. Every refusal names both mods, the setting and both values:

```
mod[engine] warn: b.lua not loaded: it sets rule boss_spectate to true, but a.lua (already running) sets it to false
```

The check can only see writes made before it runs, so configuration is
locked once the entry point returns. A `params` or `rules` write from an
event handler is an error. A mod whose entry point errors lands none of its
writes.

A mod edited in place is compared as itself, so hot reload never conflicts
with the version it replaces.

## Mod packs

A mod whose manifest lists `mods` is a mod pack:

```lua
local pack = {
  name = "boss-rules-pack", version = "1.0.0", run_at = "launch",
  permissions = { "boss_spectate", "log" },
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
`rune_counter.lua` (hooks and per-mod state), `settings.lua` (ui plus store),
`perf_monitor.lua` (ui plus perf), `overlay.lua` (ui plus hooks),
`boss_rules_pack.lua` (a mod pack setting a game rule), and
`bad_sandbox.lua`, which exists to be refused. The reading order is in
[`examples/README.md`](../examples/README.md).
