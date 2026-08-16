# Writing mods in Lua

A mod is one Lua file. The same file runs two ways: `ermod apply` executes it
on the host and writes a patched `regulation.bin` a player installs, and the
engine executes it inside the running game, where the writes land in live
memory. That is the promise the engine is built around — **author live, ship
offline** — and it is one code path, not two implementations that happen to
agree.

This document is the reference for writing that file. For how the offline
backend works underneath, see [architecture.md](architecture.md), "Applying
Lua mods offline"; for the milestones and the reasoning behind the design,
see [scripting-plan.md](scripting-plan.md).

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
ermod apply "$GAME/regulation.bin" mod/regulation.bin my_mod.lua
```

The file is read, never written. Everything lands in the output copy, which
the engine loads with `--regulation` — see [deploy.md](deploy.md).

## Anatomy

A mod script returns one table. Four fields declare what it is, and one
function is its entry point.

| Field | Meaning |
| --- | --- |
| `name` | Identity. Appears in every log line (`mod[level60] info: …`) and owns the mod's param writes in the conflict ledger. |
| `version` | Free-form string; carried, not interpreted. |
| `run_at` | `"launch"` or `"events"` — when the engine runs it (below). |
| `permissions` | The SDK modules it may touch. This list is the whole of what the mod can reach. |

The manifest is parsed strictly. A `run_at` that is not one of the two names,
a permission that is not a real module, a missing field, or a manifest whose
declared entry point does not exist are each a load-time error rather than a
surprise later — a mod that declares when it runs but has no function to run
is a packaging mistake worth catching before the game starts.

### `run_at = "launch"` — entry point `on_launch(sdk)`

Runs once, at load. This is the kind of mod that edits data: params in,
params out, done. It is the only kind `ermod apply` accepts, because it is
the only kind that means anything without a game running.

In-game, "at load" means the first rendered frame after the game's param
tables exist, not the moment the runtime attaches — a param mod that ran
earlier would have no tables to write to. A hot reload re-runs `on_launch`.

### `run_at = "events"` — entry point `setup(sdk)`

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

Event mods are **in-game only**. `ermod apply` refuses one rather than
silently doing nothing, because offline there is nothing to fire:

```
ermod: rune_counter.lua is an event mod (events); event mods run in-game only
```

State kept in an upvalue (`total` above) is private to that mod — each mod
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

Around that, the VM itself is narrow. Only `base`, `table`, `string` and
`math` are opened — `io`, `os`, `package` and `debug` never are — and the
code-loading globals (`load`, `loadfile`, `dofile`, `require`, `loadstring`)
are removed from `base` afterwards, so a mod cannot pull in a new chunk or
reach native code. There is no `require`: one file is one mod.

The sandbox is the same offline. A mod reaching for `os` fails on the host
exactly as it would in your session, at the same line:

```
mod[bad-sandbox] err: bad_sandbox.lua:15: attempt to index a nil value (global 'os')
ermod: bad_sandbox.lua errored in on_launch (RuntimeError)
```

### Budgets and strikes

Every call into Lua — `on_launch`, `setup`, each handler — runs under an
instruction budget (10 000 000 instructions by default), counted by the VM
itself. A runaway loop is cut off and reported instead of hanging the frame
it was called from. Overrunning the budget disables the mod on the spot; a
handler that *errors* is given three strikes first, since a bug that fires
on one code path should not cost a mod that works the rest of the time. A
disabled mod stops receiving events and says so once in the log. The other
mods are unaffected.

Offline the same model applies, so a mod too slow to finish `on_launch`
in-game is refused by `apply` rather than shipping.

## Modules

Full signatures live in `stubs/ermod.lua` (generated by `ermod stubs` and
committed, so editor completion needs no build). What follows is what each
module is *for*, and what it costs.

### `log`

`log.info(msg)`, `log.warn(msg)`, `log.error(msg)`. Lines are tagged with the
mod's name by the engine — a mod cannot forge another's attribution.

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
paramdefs, and a write goes straight into the table's bytes — in-game that is
live memory and takes effect immediately; offline it is the unpacked
archive's bytes, packed at the end.

Two things to know:

- **Row ids are not unique.** Most tables key cleanly, but some ship
  duplicates (`RandomAppearParam` has 26). `row(file, id)` resolves to the
  *first* descriptor with that id; later copies are reachable only by
  iterating with `rows`.
- **A param needs a vendored paramdef.** Five are generated today —
  `CharaInitParam`, `ItemLotParam`, `EquipParamWeapon`,
  `EquipParamProtector`, `EquipParamGoods`. Touching a param without one is
  an error naming the file, in-game and offline alike.

`ermod show <regulation.bin> <row-id>` prints the field names a row actually
uses, which is the quickest way to find what to write.

### `hooks`

`hooks.on(event, handler)`. Three events exist: `on_present` (a frame is
about to be presented — payload `{}`), `on_rune_gain` (payload
`{ amount = n }`) and `on_death` (payload `{}`). An unknown event name is an
error at subscribe time, not a handler that never fires.

`on_present` runs on the render thread, once per frame. It is the budget's
sharpest edge: whatever it does is paid every frame, so measure it with
`ermod perf` before shipping.

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
every `ui` call is legal **only inside a frame** — from a handler running
during `on_present`, or the state events derived from it. Calling one from
`on_launch` is an error. Widgets that edit a value take the current value and
return the new one, so the mod owns the state; labels are unique per window,
and `"Label##id"` disambiguates two that must read the same.

`Insert` toggles whether the overlay takes input focus; `ui.focused()` says
whether it currently has it, and is the one `ui` call legal outside a frame
(it answers `false` when there is no overlay at all). Offline, `ui` reports
itself unavailable — there is no frame to draw on.

### `perf`

`frame_ms()`, `fps()`, `frame()`, `now_ms()` and `mods()` — the last returning
every loaded mod's handler cost (`last_ms`, `avg_ms`, `total_ms`, `calls`),
not only the caller's. A performance-monitor mod is `perf` + `ui` and nothing
else.

### `store`

`get(key, default)`, `set(key, value)` (nil deletes), `keys()`. Strings,
numbers and booleans; keys match `[A-Za-z0-9_.-]+`. Per-mod and persistent —
this is the only filesystem access a mod has, and where the file lives is the
engine's business, not the mod's. Read at setup, write when a value changes.

### `screen`

`capture([name][, scale])` writes the next presented frame — overlay included
— as a PNG, and returns the path it will appear at (or nil and a reason). It
is the engine reading back its own swapchain, so what you get is exactly what
the game presented. Pair it with `ermod img` to turn a capture into numbers a
test can assert on; see [frame captures](#frame-captures).

## The author loop

### Offline

```sh
ermod check my_mod.lua                    # would it load in-game?
ermod perf  my_mod.lua                    # what does it cost per event?
ermod apply "$GAME/regulation.bin" mod/regulation.bin my_mod.lua
```

`check` runs the game's own loader, sandbox and manifest rules on the host,
so "passes `check`" means "would load in-game". It prints one line per mod
and exits 1 if any would fail, which makes it a pre-commit hook:

```
examples/level60.lua: ok  name=level60 run_at=launch entry=on_launch permissions=params,log
examples/rune_counter.lua: ok  name=rune-counter run_at=events entry=setup permissions=hooks,log
```

`check` answers "would it *load*", not "does it work" — `bad_sandbox.lua`
passes `check` and then fails at its first line, which is the distinction.

`perf` fires a synthetic session against the real budget model and the real
dispatcher:

```
$ ermod perf examples/overlay.lua --frames 120 --runes 5 --deaths 1
examples/overlay.lua: hud-overlay (events mod) — synthetic session: 120 frames, 5 rune pickups, 1 deaths
host pre-flight: no live params (params calls fail as they do before the tables load), recording overlay, in-memory store

start (setup): 0.023 ms

event          handlers   fires   total ms    avg/fire ms   max/fire ms
on_present            1     120      1.326        0.0111        0.0498
on_rune_gain          1       5      0.010        0.0020        0.0054
on_death              1       1      0.001        0.0007        0.0007

worst on_present frame cost 0.0498 ms = 0.30% of a 60 fps frame
strikes 0/3; mod still active at end of session
```

It is a pre-flight, not a promise: there is no game, so the overlay records
instead of drawing and the store lives in memory. Without `--regulation`,
`params` is unavailable exactly as it is before the tables load — which means
a *launch* mod dies at its first `params` call. Give it a `regulation.bin`
and `on_launch` runs against the unpacked archive, so launch mods get an
honest number too:

```
$ ermod perf examples/level60.lua --regulation "$GAME/regulation.bin"
host pre-flight: params from …/regulation.bin (unpacked, never written back), recording overlay, in-memory store

start (on_launch): 0.270 ms
start wrote 90 param field(s) (into memory; nothing is packed)
```

Nothing is written back; `perf` never produces a file.

`apply` is the real run. Its log is the mod's own:

```
$ ermod apply "$GAME/regulation.bin" mod/regulation.bin examples/level60.lua
mod[level60] info: Vagabond: level 9 -> 60
…
mod[level60] info: Wretch: level 1 -> 60
mod[level60] info: level60 applied to 10/10 classes
ermod: 90 Lua field write(s) from 1 mod(s)
applied 0 spec patch(es) across 0 param(s) -> mod/regulation.bin (1765424 bytes)
```

`ermod`'s two built-in patch specs and `.lua` mods mix on one command line
(`… level60.lua class-gear`). The specs are applied first; both feed one
write ledger, so a Zig patch and a Lua write on the same field collide like
any two mods.

### In-game

Drop the file in the engine's mods directory and it loads at launch:

```
~/.local/share/Steam/steamapps/compatdata/1245620/pfx/drive_c/ermod/mods
```

which the game, under Wine, sees as `C:\ermod\mods` — the name the log uses.
One `.lua` file per mod, no subdirectories, nothing to register them in.

While authoring, prefer `ermod-engine --mods <dir>`: it points that directory
at your working tree, so the file you edit is the file the game loads. Save, and the running game picks it
up within about a second — a launch mod re-runs `on_launch`, an event mod
re-registers its handlers, and the old VM is closed. A reload that fails
keeps the previous version running and says why.

Remember a reload is a fresh VM: upvalues reset, `store` does not.

### Frame captures

`sdk.screen.capture()` (or `ermod-engine shot`) writes a PNG of the presented
frame; `ermod img` measures it, so "did my overlay draw?" is a shell test
rather than a squint:

```sh
ermod img stat shot.png --rect 20,20,420,260   # mean colour, lit coverage, distinct colours
ermod img diff before.png after.png            # changed pixels + bbox; exit 1 if nothing changed
```

## Conflicts

Every param write is recorded as `(mod, table, row, field)`. When two
*differently named* mods write the same field, the policy depends on where
you are:

**Offline it is an error.** The file a player installs must not depend on the
order two mods were listed in, so `apply` names both mods and the field,
refuses to pack, and writes no output file:

```
ermod: conflict — class-tweaks wrote CharaInitParam[3000].soulLv, already written by level60
ermod: refusing to pack; resolve the overlap or apply one mod at a time (1 conflicting write(s))
```

A half-patched archive is worse than none, so every refusal — an event mod, a
sandbox escape, a budget overrun, a conflict — exits 1 having written
nothing.

**In-game it is a warning.** The later write wins and the overlap is logged.
That is deliberate: a hot-reloaded mod rewrites its own fields every reload,
and a warning is the honest report of something a player can still act on
mid-session.

Ownership is keyed by **mod name**, so two mods sharing a name are treated as
one and never conflict. That is what makes hot reload quiet, and it is why
`level60.lua` and the built-in `level60` spec — same name, same 90 fields —
can be applied together.

## Editor setup

`stubs/ermod.lua` carries LuaLS annotations for the whole SDK and is
committed, so completion and type checking need only a path:

```json
{ "workspace.library": ["path/to/elden-ring-mods/stubs"] }
```

Regenerate with `make stubs` after an SDK change; CI fails on drift.

## Example mods

`examples/` holds one worked example per SDK slice — the best place to read
working code, and the loader's own test corpus. `level60.lua` (params, the
reference gameplay mod and the offline golden test's subject),
`rune_counter.lua` (hooks and per-mod state), `settings.lua` (ui + store),
`perf_monitor.lua` (ui + perf), `overlay.lua` (ui + hooks), and
`bad_sandbox.lua`, which exists to be refused. The reading order is in
[`examples/README.md`](../examples/README.md).
