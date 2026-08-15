# Test mods

Lua fixtures for exercising the runtime's mod loader, sandbox and SDK. They
are not shipping mods — each targets one slice of the engine so a failing
runtime test points at a specific capability.

| Fixture | Exercises | Expected |
| --- | --- | --- |
| `hello_launch.lua` | manifest parse, `run_at = "launch"`, `log`, one dispatch | loads and runs |
| `rune_counter.lua` | `run_at = "events"`, `hooks.on`, typed payload, per-mod state | loads and runs |
| `double_runes.lua` | `params.rows`, typed field read/write | loads (needs a `GameAreaParam` paramdef to run) |
| `level60.lua` | `params.row`, typed field read/write, launch mod | runs (host, synthetic table) + **live-proven** |
| `present_ping.lua` | `hooks` + `log`, per-frame `on_present` handler | loads and runs (offline + live) |
| `death_ping.lua` | `hooks` + `log`, `on_death` and `on_rune_gain` handlers | live fixture (not embedded in host tests) |
| `perf_monitor.lua` | `ui` + `perf`: frame plot, per-mod cost table | runs (recording backend) + **live-proven** |
| `settings.lua` | `ui` + `store`: every control persists on change, survives reload | runs (recording backend + in-memory store) + **live-proven** |
| `overlay.lua` | `ui` + `hooks`: HUD driven by `on_rune_gain` / `on_death` | runs (recording backend) + **live-proven** |
| `bad_sandbox.lua` | `os`/`io`/undeclared-module access | **must be rejected** |

`ermod check test/mods/*.lua` loads every fixture the way the game
would (all pass, including `bad_sandbox` — it loads; it fails at its entry
point, which is the point); `ermod perf test/mods/overlay.lua` runs one
against a synthetic session and reports handler cost.

Permission model: a mod may only touch SDK modules listed in its manifest
`permissions`. `bad_sandbox.lua` is the negative case that proves the
sandbox denies both stdlib escapes (`os`, `io`) and undeclared SDK modules.

The SDK surface used here (`log`, `hooks`, `params`, `ui`, `perf`, `store`)
matches `docs/scripting-plan.md`; `docs/scripting.md` is the author-facing
reference for the format these fixtures are written in.

These files belong to the `ermod-lua` package, which is why they are reached
from `src/lua/fixtures` (a symlink to this directory) as well as from here —
both consumers embed them from one copy. Every fixture but `double_runes` and
`death_ping` is executed by the tests, not merely loaded: `hello_launch`,
`rune_counter`, `overlay`, `perf_monitor`, `settings` and `bad_sandbox` in
`src/lua/loader.zig`; `level60` in `src/sdk/params.zig` against a synthetic
`CharaInitParam` table; `settings` again in `src/sdk/store.zig` against the
in-memory store. The engine runs the three E4 showcase mods together in its
`src/runtime/registry.zig`, against the recording UI backend
(`src/ui_backend.zig` here), a fake clock and the in-memory store.

`present_ping` is the fixture the runtime loads on disk for the live
`on_present` test; `level60` is the live E3 proof and the subject of the
offline golden test (`level60.lua` ≡ the `level60` Zig spec, byte-identical);
the three showcase mods are the live E4 proof. `double_runes` uses
`GameAreaParam`, which has no vendored paramdef yet.
