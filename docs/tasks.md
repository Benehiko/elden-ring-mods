# Task Breakdown

Implementation plan for the mod pipeline described in [architecture.md](architecture.md).
Tasks are ordered by dependency; each is self-contained enough to hand to a separate
contributor. "AC" = acceptance criteria.

Status legend: ✅ done · 🔲 open · 🧪 needs in-game verification

## Milestone 0 — Container pipeline ✅

Done and verified (byte-identical roundtrip against the real install):

- ✅ AES-256-CBC layer (`src/crypto.zig`)
- ✅ DCX/ZSTD layer with header-template repack (`src/dcx.zig`)
- ✅ CLI `decrypt` / `encrypt` / `unpack` / `pack` (`src/main.zig`)

---

## Milestone 1 — Archive & param access

### T1. BND4 reader/writer ✅

`src/bnd4.zig`. Parse the BND4 produced by `ermod unpack`: header, file entry table,
UTF-16LE names, per-file data slices. Writer re-serializes with modified file data
(sizes and offsets recomputed, unknown fields preserved verbatim).

- Reference: SoulsFormats `BND4.cs` (read the code, port the logic; do not add a .NET dependency).
- AC: synthetic-fixture roundtrip test; real-file roundtrip `unpack → parse → serialize → cmp` byte-identical when nothing is modified; `ermod ls` prints all entry names and sizes of the real regulation BND4.

### T2. PARAM reader/writer ✅

`src/param.zig`. Parse a `.param` file: header, row descriptors (ID, data offset,
name offset), fixed-size row data as raw bytes. API: iterate rows, get row by ID,
mutable access to a row's byte slice. Writer re-serializes (offsets recomputed if row
count changes; modifying rows in place must not shift anything).

- AC: roundtrip tests as in T1; `ermod extract regulation.bin CharaInitParam.param out.param` works against the real file; extracted param reports the expected param type string.
- Result: done. The real param type is **`CHARACTER_INIT_PARAM`** (not `CHARA_INIT_PARAM_ST` as guessed when this task was written), 3240 rows, 320-byte stride. Row size is derived from consecutive row offsets since it is not stored in the file.

### T3. Paramdef field layouts ✅

`src/paramdef.zig`. We need field name → (offset, type, size) for the params we edit.
Source: Paramdex XML from the Smithbox repo (vendor the XML files for `CharaInitParam`,
`ItemLotParam_map`, `EquipParam*`, `SpEffectParam` under `paramdefs/`, with upstream
commit noted in a README there).

Decision for the implementer: parse XML at runtime vs. a small codegen step that emits
Zig structs. Either is fine; prefer whichever stays simpler, and keep bitfields in mind
(paramdefs contain packed bitfield rows).

- AC: given a real extracted `CharaInitParam.param`, print each class row's `soulLv` (or equivalently named field) with a plausible value; unit test validates offsets against at least three hand-checked fields.
- Result: done via codegen (`tools/gen_paramdef.py` → `src/generated/paramdefs.zig`), XML vendored under `paramdefs/`. The paramdef source turned out to be **soulsmods/Paramdex**, not Smithbox, and the ER file is `CharaInitParam.xml` / `ItemLotParam.xml` (no `_map` suffix); no `SpEffectParam.xml` exists there, so it was dropped from the vendored set.
- The bitfield trap is real: `dummy8` bitfields pack into the same storage unit as an adjacent `u8`. Getting this wrong yields a 321-byte row instead of 320 and shifts every later field. The generated `row_size` matching the game's actual stride is what proves the layout correct.

---

## Milestone 2 — Declarative mods

### T4. Mod spec + `ermod apply` ✅

`src/modspec.zig`. A mod is a declarative spec in `mods/` describing param patches:

```
target param → row ID (or "all class rows") → field → new value
```

`ermod apply <regulation.bin> <out.bin> <mod>...` runs the full pipeline: read the game's
regulation.bin (read-only), apply one or more specs, write the modded copy.
Multiple specs compose; conflicting writes to the same field are an error, not
last-wins.

- AC: applying an empty spec reproduces a byte-identical regulation.bin (modulo fresh AES IV — compare after decrypt); applying a spec that sets one known field changes exactly that row's bytes and nothing else (assert with a diff over the unpacked BND4); README section documenting the spec format.
- Result: done, both ACs verified by `ermod selftest` against the real install — a no-op rebuild of the 54 MB archive is byte-identical, and applying both mods changes exactly 264 bytes, all inside `CharaInitParam.param`.
- Specs are written as Zig (`mods/*.zig`) rather than ZON, so stat spreads and patch tables are computed at comptime and validated by unit tests. They import `src/spec.zig`, a dependency-free module holding just the patch types; Zig forbids importing files above a module root, so `mods/` is its own module.

### T5. Mod: level 60 start ✅🧪 (needs in-game verification)

`mods/level60`. Set every starting class to level 60 with a sensible stat spread.
CharaInitParam stores base stats per class; level must equal the sum-derived value the
game expects (level = stat total − 79 in Elden Ring terms) or character creation
misbehaves — implementer must verify the exact relation from paramdef/community docs
and encode per-class stat distributions, not just the level field.

- AC: spec applies cleanly; in-game: new character of at least two different classes starts at level 60 with the specified stats, runes-to-next-level sane.
- Result: spec applies cleanly to all ten classes; the `soulLv = stat total − 79` relation was confirmed against every vanilla row (see docs/classes.md) and each level-60 spread is unit-tested to sum to 139 with all stats in 1..99. **In-game verification still outstanding.**

### T6. Mod: starting gear per class ✅🧪 (needs in-game verification)

`mods/class-gear`. Route 1 from the architecture doc: fill each class's
`CharaInitParam` equipment/item slots (swords, armor, consumables) instead of spawning
a physical chest. Gear IDs come from `EquipParamWeapon` / `EquipParamProtector`
(read-only lookups; document chosen IDs in the spec's comments).

- AC: spec applies cleanly; in-game: at least two classes spawn with the configured weapons/armor equipped and items in inventory.
- Result: spec applies cleanly; every referenced ID is checked against the game's own tables by `ermod verify-ids`. That check caught a real trap: **upgraded weapon IDs do not exist as rows** (reinforcement comes from `ReinforceParamWeapon` at runtime), so only base IDs are used. **In-game verification still outstanding.**

---

## Milestone 3 — Deployment & project hygiene

### T7. Mod Engine 2 deploy docs + helper ✅🧪 (docs written; launch not yet verified)

`docs/deploy.md`: obtaining Mod Engine 2, directory layout (`mod/`, `modengine2/`),
Proton launch steps for this machine's Steam install, and the offline-safety warning.
Optionally an `ermod deploy` convenience (copy `regulation.modded.bin` →
`mod/regulation.bin`).

- AC: following the doc from scratch on this machine boots the game through Mod Engine 2 with a trivially observable param change, vanilla install untouched (verify with file mtimes/hashes).

### T8. CI ✅

GitHub Actions: `zig fmt --check`, `zig build`, `zig build test` on push/PR
(container or setup-zig action pinned to 0.16; libzstd available). Real game data is
not available in CI — tests must pass on synthetic fixtures alone.

- AC: green pipeline; a PR with a formatting error or failing test is blocked.
- Result: `.github/workflows/ci.yml` runs fmt/build/test plus a job asserting the committed paramdef tables still match the vendored XML. Not yet exercised on GitHub — no remote is configured.

### T9. Initial commit & repo setup ✅

Conventional commits. `make hooks` activates the pre-commit hook and marks it
executable (the sandbox here blocks `chmod`, so it must be run once locally).

---

## Backlog / stretch (not scheduled)

- **Physical chest near spawn** — route 2: `.msb` map edit + `ItemLotParam_map` +
  possibly EMEVD. Needs two new format modules; research task first.
- **NPC healer** — research spike: what exists in params alone (SpEffect auras,
  summon-style NPC via existing params) vs. what needs ESD/EMEVD/HKS scripting; write
  findings to `docs/npc-healer.md` before any implementation.
- **Seamless Co-op interplay** — verify param mods load under the co-op launcher
  (it has its own mod-folder mechanism); document what works. Player cap / respawn
  fixes remain upstream issues, out of scope here.
- **Latency/party overlay** — separate project (DLL injection, Windows/Proton),
  intentionally not part of this pipeline.
