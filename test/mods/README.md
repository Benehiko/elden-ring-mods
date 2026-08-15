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

`ermod-dev check test/mods/*.lua` loads every fixture the way the game
would (all pass, including `bad_sandbox` — it loads; it fails at its entry
point, which is the point); `ermod-dev perf test/mods/overlay.lua` runs one
against a synthetic session and reports handler cost.

Permission model: a mod may only touch SDK modules listed in its manifest
`permissions`. `bad_sandbox.lua` is the negative case that proves the
sandbox denies both stdlib escapes (`os`, `io`) and undeclared SDK modules.

The SDK surface used here (`log`, `hooks`, `params`, `ui`, `perf`, `store`)
matches the plan in the open repo's `docs/scripting-plan.md`.

Every module is implemented, so every fixture but `double_runes` and
`death_ping` is executed by the tests, not merely loaded: `hello_launch`,
`rune_counter`, `present_ping` and `bad_sandbox` in
`src/runtime/sdk/mod_instance.zig` and `src/runtime/registry.zig`;
`level60` in `src/runtime/sdk/params.zig` against a synthetic
`CharaInitParam` table; and the three E4 showcase mods together in
`src/runtime/registry.zig` against the recording UI backend
(`src/runtime/ui_backend.zig`), a fake clock and the in-memory store.
`present_ping` is also the fixture the runtime loads on disk for the live
`on_present` test; `level60` is the live E3 proof; the three showcase mods
are the live E4 proof (`docs/e4-ui-platform-scoping.md`). `double_runes`
uses `GameAreaParam`, which has no vendored paramdef yet.
