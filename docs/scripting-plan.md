# Engine plan: a standalone Lua mod engine for Elden Ring

> **Historical.** This is the plan as written before the work started, kept
> for the reasoning behind the design. It has since been built: milestones
> E1–E7 are done and proven in the running game, and E8 (release packaging)
> is complete bar publication. Where this document says "will", read "does" —
> and for what actually exists, see [architecture.md](architecture.md) and
> [scripting.md](scripting.md), which are maintained.

Decision: build our own engine, not a Mod Engine 2 extension. ME2 is archived;
we want something simpler and fully under our control. The product is:

1. A Zig-compiled **engine** (closed source): launcher + injected runtime that
   hooks the game, enforces offline mode, and checks for a legitimate copy.
2. **Launch mods** — single Lua scripts the engine executes at game start
   (data edits, one-shot setup).
3. **Event mods** — Lua scripts whose handlers fire on engine-driven hooks
   (damage dealt, rune gain, frame presented, menu opened, …).
4. A Lua **SDK** shipped with the engine: typed bindings for params, hooks,
   UI, and engine services. A modder never sees an address or a struct offset.
5. **Tooling**: static checks for Lua mods — performance lints, dependency
   graphs, API validation — runnable without launching the game.

Target authoring experience: a whole side-application in Lua — performance
monitors, in-game overlays, in-game settings screens — with the engine as the
platform.

The existing offline pipeline (regulation.bin unpack/patch/repack, generated
paramdefs, conflict-checked apply) is carried forward: it becomes the data
layer of the SDK and the fallback path for users who want file-based mods
without injection.

---

## Architecture

```
┌────────────────────────── engine (closed source, Zig) ──────────────────────┐
│                                                                             │
│  launcher (native ELF)               runtime (dll, injected into game)      │
│  ├─ legitimacy check                 ├─ AOB scan + version gate             │
│  ├─ offline enforcement (no EAC)     ├─ hook framework (trampolines)        │
│  ├─ drive Proton to start game       ├─ Lua VM pool + sandbox               │
│  └─ arrange DLL injection            ├─ SDK modules (params/hooks/ui/perf)  │
│     (WINEDLLOVERRIDES)               ├─ DX12 present hook → overlay/UI     │
│                                      └─ mod lifecycle (load/reload/kill)   │
└─────────────────────────────────────────────────────────────────────────────┘
        ▲                                        ▲
        │ reads                                  │ loads
  mods/*.lua  (open ecosystem)             sdk/*.lua (shipped stubs + docs)
```

- **The launcher is a native binary** for the user's OS (Linux by default),
  not a Windows exe. Its job — find the install, drive Proton, arrange
  injection — happens outside the game process, so running it under Wine
  would only add indirection. It starts the Windows game the way Steam does:
  invoking the `proton` script with the `STEAM_COMPAT_*` environment, minus
  EAC. Injection then rides Proton's own Wine loader via `WINEDLLOVERRIDES`,
  so the launcher never has to ptrace anything.
- **The runtime is a Windows PE DLL** (`x86_64-windows-gnu`), because it is
  injected into `eldenring.exe`'s address space — a Wine PE process, into
  which a native `.so` cannot be loaded. This split is the most-native design
  the platform allows: native kernel, native GPU driver, native Vulkan (via
  VKD3D-Proton translating the game's D3D12), native launcher; only the
  game's own code and code injected into it stay PE and translated by Wine.
- **Launcher** and **runtime** are one Zig codebase with two build targets
  (host for the launcher, `x86_64-windows-gnu` for the runtime); developed
  and tested on Linux, with the runtime path exercised under Proton.
- **Mods are open**; the engine is the closed part. The SDK surface (Lua API,
  documentation, type stubs) is public so mod development needs nothing
  proprietary.
- This repository stays the open half (tooling, SDK stubs, docs, the offline
  param pipeline). The engine sources move to a private repository; releases
  ship stripped binaries. Decide the split at milestone E0 — retrofitting
  privacy after code is public is impossible.

### Enforcement layer (launcher)

Honest scoping — these are deterrents and safety rails, not DRM:

- **Legitimate copy**: verify a Steam install (app manifest for app 1245620,
  expected executable present, sane install layout). This blocks the casual
  pirated-copy case. It cannot be made cryptographically strong against a
  determined user, and we should not pretend otherwise or arms-race it.
- **Offline enforcement**: hard rule — the runtime never attaches to a
  process with Easy Anti-Cheat active. The install ships two executables:
  `start_protected_game.exe` starts EAC and then the game, `eldenring.exe` is
  the game itself. The launcher runs the latter directly through Proton and
  never the former, and the runtime double-checks before installing any hook.
  This is a safety guarantee to the user (no bans), so it is belt *and*
  braces.
- **Version gate**: on unknown game build the runtime logs, disables all
  hooks, and lets the vanilla game run. Never crash, never half-attach.

### Hook framework (runtime)

- AOB (array-of-bytes) signatures, never fixed addresses; community
  reverse-engineering (SoulsMods research, TGA's table) seeds the signature
  set. Signatures live in a versioned data file so a game patch needs a data
  update, not an engine release.
- Trampoline hooks behind a registry of **named events**. Scripts subscribe to
  names ("on_rune_gain"); the engine owns everything below that line.
- Per-game-patch signature upkeep is the standing maintenance cost of the
  whole project. The signature-data-file design exists to make that cheap.

### Lua runtime + sandbox

- Lua 5.4 vendored, compiled into the runtime by Zig (no system deps).
- Per-mod VM instance: one misbehaving mod cannot corrupt another's state,
  and the engine can kill/reload a single mod.
- Sandbox: `base`/`table`/`string`/`math` only; no `io`, `os`, `require`,
  no loading new chunks. File/OS needs go through vetted SDK modules instead.
- Budgets, enforced per event dispatch via `lua_sethook` instruction counting
  and a wall-clock cap: a handler that overruns is suspended and reported —
  a slow overlay script must never become a game stutter. This is also what
  makes the perf tooling (below) truthful: the same budget model, offline.

### SDK modules (v1)

| Module   | Surface                                                            |
| -------- | ------------------------------------------------------------------ |
| `params` | Same API online and offline: `rows(file)`, `row(file, id)`, typed field read/write from generated paramdefs. Offline it produces regulation.bin patches; in-game it edits the live param tables. One script, both modes. |
| `hooks`  | `on(event, handler)`, `off(...)`; event payloads are typed read views with whitelisted mutable fields. |
| `ui`     | Immediate-mode overlay API (windows, text, plots, toggles, sliders) rendered via the DX12 present hook. Backed by vendored cimgui (C bindings, compiles under Zig like Lua does). |
| `perf`   | Frame timing, per-mod script cost, counters — the data source for a performance-monitor mod. |
| `store`  | Per-mod persistent key/value (settings screens need it). The only sanctioned filesystem access. |
| `log`    | Structured logging into the engine's log file, tagged per mod. |

The example applications fall out of these directly: performance monitor =
`perf` + `ui`; in-game settings = `ui` + `store`; overlays = `ui` + `hooks`.

### Mod format

One script = one mod. A table at the top declares identity and intent:

```lua
local mod = {
  name = "rune-counter",
  version = "1.0.0",
  run_at = "launch" | "events",     -- points 2 and 3 of the vision
  permissions = { "ui", "hooks" },  -- SDK modules it may touch
}

function mod.on_launch(sdk) ... end          -- launch mods
function mod.setup(sdk) sdk.hooks.on(...) end -- event mods

return mod
```

Declared permissions gate which SDK modules the sandbox exposes — a
data-only mod physically cannot draw UI or read files, and users can see at
install time what a mod is allowed to do.

### Tooling (offline, in this open repo)

`ermod` grows mod-developer commands, sharing the engine's Lua front end:

- `ermod check <mod.lua>` — sandbox-load, validate manifest, param/field
  names, permission declarations. Static; no game needed.
- `ermod graph <mods-dir>` — dependency/conflict graph: which params, rows,
  fields, events each mod touches; flags conflicting writes across mods
  before anyone launches the game (same conflict rule as the offline
  pipeline, lifted to the whole mod set).
- `ermod perf <mod.lua>` — run handlers against recorded/synthetic event
  traces under the instruction-count budget model; report cost per event and
  the hot paths. An honest pre-flight, not a promise — real in-game cost is
  what `perf` + the engine's per-mod accounting report.
- `ermod stubs` — emit Lua type stubs (LuaLS annotations) for the SDK, so
  authors get completion and type checking in any editor.

---

## Milestones

Ordering rule: the offline experience ships value at every step, and the
in-game runtime grows behind it. Each milestone is releasable.

### E0 — Repo split + feasibility spike *(gate for everything else)*

- Split: engine → private repo; this repo keeps SDK stubs, tooling, docs,
  offline pipeline.
- Spike: Zig launcher starts Elden Ring under Proton with EAC off, injects a
  Zig DLL that logs to a file and installs **one** AOB-scanned hook that
  fires. Kill/proceed on: game stable, hook fires, dev loop bearable.

### E1 — Offline Lua (the former Phase 1, unchanged in substance)

Lua vendored into `ermod`; `params` module against the offline pipeline;
sandbox; conflict-checked patch recording; `level60` ported as the reference
mod with a byte-identical golden test; `ermod check`; `docs/scripting.md`.

Ships alone as a useful product: scripted regulation.bin mods, no injection.

### E2 — Runtime core

Hook framework (AOB scanner, trampolines, signature data file, version
gate), per-mod VMs with budgets, `hooks` + `log` modules, mod lifecycle
(load at launch, kill on misbehaviour). Launch mods (`run_at = "launch"`)
and first event mods work in-game.

### E3 — Live params

Locate in-memory param tables; the `params` SDK module gains its live
backend. The same script that patched regulation.bin offline now edits the
running game — the engine's core promise ("author live, ship offline")
lands here.

### E4 — UI + the platform modules

DX12 present hook, vendored cimgui, `ui`/`perf`/`store` modules. The three
showcase mods get built as SDK validation and shipped as examples:
performance monitor, an in-game settings screen, a gameplay overlay.

### E5 — Developer experience round-out

`ermod graph`, `ermod perf`, `ermod stubs`; mod hot-reload in-game (edit
script, engine reloads that VM — the iteration loop that makes Lua authoring
actually pleasant); signature-update release process documented.

---

## Standing risks

- **Game patches** invalidate signatures and param layouts. Mitigations:
  signature data file (data update, not binary release), version gate
  (graceful disable), paramdef identity checks (already in place).
- **Closed engine vs. community trust.** An injected closed-source binary
  asks for real trust. Mitigations: open SDK/tooling/docs, per-mod
  permission model users can inspect, the hard offline/EAC guarantee, and a
  public changelog for engine releases.
- **Proton dev loop** is slow; every runtime milestone pays this tax. The
  spike (E0) measures it before we commit; hot-reload (E5) exists to cut it
  for mod authors even if engine iteration stays slow.
- **Legitimacy check ceiling.** It stays a shallow deterrent by design;
  strong DRM is out of scope and an arms race we would lose.
