# Example mods

Eleven mods, one file each, every one readable in a minute. Copy one into your
mods directory and it loads on the next frame; edit it and it hot-reloads
without restarting the game.

Read them in roughly the order below. Every example's header comment says
what it teaches and what to try.

## Start here

| Example | What it teaches |
| --- | --- |
| [`hello_launch.lua`](hello_launch.lua) | the manifest, `run_at = "launch"`, `sdk.log`: the smallest mod that does anything |
| [`rune_counter.lua`](rune_counter.lua) | `run_at = "events"`, `sdk.hooks.on`, typed event payloads, per-mod state |
| [`present_ping.lua`](present_ping.lua) | running code every frame without flooding the log |
| [`death_ping.lua`](death_ping.lua) | `on_death` and `on_rune_gain` side by side, a live sanity check |

## Changing the game

| Example | What it teaches |
| --- | --- |
| [`level60.lua`](level60.lua) | **the reference mod.** Every starting class begins at level 60: `sdk.params.row`, typed field read and write, and the offline `ermod-engine apply` path |
| [`double_runes.lua`](double_runes.lua) | `sdk.params.rows` over a whole PARAM table |
| [`boss_rules_pack.lua`](boss_rules_pack.lua) | a mod pack: `mods`, a rule permission, `sdk.rules`, and precedence over standalone mods |

`double_runes` uses `GameAreaParam`, which has no vendored paramdef yet. It
passes `check`, but its entry point fails with "unknown param file" in the
game and offline alike: read it for the shape. `level60` runs both ways,
offline against `regulation.bin` and live against the game's own param
tables.

## Drawing on screen

| Example | What it teaches |
| --- | --- |
| [`overlay.lua`](overlay.lua) | a HUD driven by game events: `sdk.ui` plus `sdk.hooks`, borderless input-transparent windows |
| [`perf_monitor.lua`](perf_monitor.lua) | a tool window: `sdk.perf` counters, plots, per-mod script cost |
| [`settings.lua`](settings.lua) | an in-game settings screen whose values survive a relaunch: `sdk.ui` plus `sdk.store` |

Press **Insert** to give the overlay mouse and keyboard focus, Insert again to
hand it back to the game. While it has focus the pointer moves freely and the
camera stays still; `Tab` or the arrow keys move between controls and `Space`
or `Enter` presses one. See [In the game](../README.md#in-the-game).

## What a mod may not do

| Example | What it teaches |
| --- | --- |
| [`bad_sandbox.lua`](bad_sandbox.lua) | the negative case: it **must be refused** |

A mod receives exactly the `sdk.*` modules its manifest `permissions` lists.
An undeclared module is not blocked at the call. It is absent from `sdk`
entirely, so it cannot be reached. `os` and `io` are not in the sandbox at
all. `bad_sandbox.lua` reaches for all three and fails at its entry point,
which is the point.

## Running them

```sh
# check every example the way the game loads it
ermod-engine check examples/*.lua

# run one against a synthetic session and report handler cost
ermod-engine perf examples/overlay.lua --frames 120 --runes 5 --deaths 1

# apply a params mod offline, producing a modded regulation.bin
mkdir -p mod
ermod-engine apply "$GAME/regulation.bin" mod/regulation.bin examples/level60.lua
```

`ermod-engine check` passes on all eleven, `bad_sandbox` and `double_runes`
included: `check` asks whether a mod *loads*, and both fail only when their
entry point runs.

[`docs/scripting.md`](../docs/scripting.md) is the full author-facing
reference for the format, and `stubs/ermod.lua` gives editor completion by
cloning this repository. Nothing to build.

## They are also the test corpus

The engine keeps a copy of these files as its test corpus, one example per
SDK slice, and checks that its copy matches this one byte for byte.

Live-proven in a running game: `level60` (params), `present_ping`,
`rune_counter` and `death_ping` (event hooks), and all three UI examples
(the overlay).
