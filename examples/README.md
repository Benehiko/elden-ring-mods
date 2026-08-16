# Example mods

Ten mods, one file each, every one readable in a minute. Copy one into your
mods directory and it loads on the next frame; edit it and it hot-reloads
without restarting the game.

Read them in roughly the order below — every example's header comment says
what it teaches and what to try.

## Start here

| Example | What it teaches |
| --- | --- |
| [`hello_launch.lua`](hello_launch.lua) | the manifest, `run_at = "launch"`, `sdk.log` — the smallest mod that does anything |
| [`rune_counter.lua`](rune_counter.lua) | `run_at = "events"`, `sdk.hooks.on`, typed event payloads, per-mod state |
| [`present_ping.lua`](present_ping.lua) | running code every frame without flooding the log |
| [`death_ping.lua`](death_ping.lua) | `on_death` and `on_rune_gain` side by side — a live sanity check |

## Changing the game

| Example | What it teaches |
| --- | --- |
| [`level60.lua`](level60.lua) | **the reference mod** — every starting class begins at level 60; `sdk.params.row`, typed field read/write, and the offline `ermod apply` path |
| [`double_runes.lua`](double_runes.lua) | `sdk.params.rows` over a whole PARAM table |

`double_runes` uses `GameAreaParam`, which has no vendored paramdef yet: it
loads, but will not run offline. `level60` runs both ways — offline against
`regulation.bin` and live against the game's own param tables.

## Drawing on screen

| Example | What it teaches |
| --- | --- |
| [`overlay.lua`](overlay.lua) | a HUD driven by game events — `sdk.ui` + `sdk.hooks`, borderless input-transparent windows |
| [`perf_monitor.lua`](perf_monitor.lua) | a tool window — `sdk.perf` counters, plots, per-mod script cost |
| [`settings.lua`](settings.lua) | an in-game settings screen whose values survive a relaunch — `sdk.ui` + `sdk.store` |

Press **Insert** to give the overlay keyboard focus, Insert again to hand it
back to the game.

## What a mod may not do

| Example | What it teaches |
| --- | --- |
| [`bad_sandbox.lua`](bad_sandbox.lua) | the negative case: it **must be refused** |

A mod receives exactly the `sdk.*` modules its manifest `permissions` lists.
An undeclared module is not blocked at the call — it is absent from `sdk`
entirely, so it cannot be reached. `os` and `io` are not in the sandbox at
all. `bad_sandbox.lua` reaches for all three and fails at its entry point,
which is the point.

## Running them

```sh
# check every example the way the game loads it
ermod check examples/*.lua

# run one against a synthetic session and report handler cost
ermod perf examples/overlay.lua --frames 120 --runes 5 --deaths 1

# apply a params mod offline, producing a modded regulation.bin
ermod apply "$GAME/regulation.bin" mod/regulation.bin examples/level60.lua
```

`ermod check` passes on all ten, `bad_sandbox` included — it *loads*; it
fails when its entry point runs.

[`docs/scripting.md`](../docs/scripting.md) is the full author-facing
reference for the format, and `stubs/ermod.lua` gives editor completion by
cloning this repository — nothing to build.

## They are also the test corpus

These files double as the engine's own test corpus — one example per SDK
slice, so a failing test points at a specific capability. They belong to the
`ermod-lua` package and are reached from `src/lua/examples` (a symlink to
this directory) as well as from here, so both consumers embed one copy.

Executed by the tests, not merely loaded: `hello_launch`, `rune_counter`,
`overlay`, `perf_monitor`, `settings` and `bad_sandbox` in
`src/lua/loader.zig`; `level60` in `src/sdk/params.zig` against a synthetic
`CharaInitParam` table, and again as the offline golden test where its output
must be byte-identical to the independent `level60` Zig spec; `settings`
again in `src/sdk/store.zig` against the in-memory store. The engine runs the
three UI examples together in its `src/runtime/registry.zig` against the
recording UI backend (`src/ui_backend.zig` here), a fake clock and the
in-memory store.

Live-proven in a running game: `level60` (params), `present_ping`,
`rune_counter` and `death_ping` (event hooks), and all three UI examples
(the overlay).
