# Architecture

## Goal

Mods for Elden Ring on Linux that a player can write in **Lua** and run in the
live game, and that can also be shipped as a modified `regulation.bin` for
people who only want a file. The vanilla install is read-only input in both
directions; nothing here ever writes to it.

Two halves, one mod format:

- **In-game** — the engine injects a runtime into the running game, which
  loads `.lua` mods, hooks events, and reads and writes the game's live PARAM
  tables. Edit a mod and it reloads within a second.
- **Offline** — `ermod apply` runs the *same* Lua mod against an unpacked
  `regulation.bin` on the host and writes a modded copy. The engine can load
  that copy directly, so no ModEngine is required.

The Lua front end (`ermod-lua`) is shared by both, which is what makes
"author live, ship offline" one code path rather than two implementations
that drift.

Non-goals:

- We do not modify or redistribute the Seamless Co-op mod (closed source). Co-op
  bug fixes and player-limit changes are upstream feature requests, not our code.
- We do not touch multiplayer, anti-cheat, or the FromSoftware servers. Modded
  play is offline: the engine launches `eldenring.exe` directly, never
  `start_protected_game.exe`, so EAC never starts.

## What lives where

This repository is the open half. The engine — the launcher, the injected
runtime, the AOB signatures, the hooks — is a separate, **closed-source**
repository, and its binaries are published on this repository's Releases page
because that is where the people who need them are.

The split is deliberate and is drawn at the mod's blast radius:

| | |
| --- | --- |
| **Open (here)** | what a mod *is* and what it may touch: the Lua sandbox, the instruction budget, every `sdk.*` binding, the `Host` interface behind them, the paramdefs, and the offline `ermod` tool |
| **Closed (engine)** | what the game *is*: signature scanning, inline detours, live param-table walking, the D3D12 overlay, process launch and injection |

So a community mod's whole capability surface is `src/sdk/host.zig`, in the
open, readable without trusting the engine binary. If a capability is not a
function on that vtable, no mod can reach it.

## Constraints

1. **Never write into the game install directory.**
   `~/.local/share/Steam/steamapps/common/ELDEN RING/Game/` is read-only input.
   The engine honours this too: everything it stages lives in the Wine prefix.
2. **Reproducible output.** Mods are described declaratively or in sandboxed
   Lua and applied by the tool; running the pipeline twice from the same
   inputs yields the same mod folder. No hand-edited binaries.
3. **Zig only** for our code (currently Zig 0.16), plus system `libzstd` for DCX
   compression. No .NET tooling (Smithbox etc.) in the build path — we may use those
   interactively for research, but the pipeline must not depend on them.
   *Mods themselves are Lua, not Zig* — this constraint is about the tooling.
4. **Offline safety.** Documentation and output layout must make it hard to
   accidentally run modded files against the live game servers.

## The data we are modifying

Nearly all "gameplay numbers" in Elden Ring live in `regulation.bin`, a ~2 MB file in
the game root. It is a nested container:

```
regulation.bin                      (2 MB, encrypted)
└── AES-256-CBC                     key: community-known 32-byte key (SoulsFormats),
    │                               IV: first 16 bytes of the file (the game
    │                               ships zeros; so do we), no padding
    └── DCX container               big-endian header, "DCP" scheme = ZSTD
        │                           (ZSTD since game patch 1.12; older was DFLT/zlib)
        │                           the game's decoder keeps 64 KiB of history:
        │                           write with windowLog 16 (see dcx.zig)
        └── BND4 archive            ~54 MB, FromSoftware's generic file bundle
            └── ~250 *.param files  fixed-size row tables (CharaInitParam,
                                    ItemLotParam_map, SpEffectParam, ...)
```

Each layer is documented in the format sections below. The layers are independent:
encrypt/decrypt, compress/decompress, bundle/unbundle, and param row editing are
separate modules with their own tests.

## Pipeline

```
                 read-only                          our output
 ┌────────────────────────────┐        ┌─────────────────────────────────┐
 │ $GAME/regulation.bin       │        │ mod/regulation.bin              │
 └─────────────┬──────────────┘        └───────────────▲─────────────────┘
               │ 1. AES decrypt                        │ 6. AES encrypt
               ▼                                       │
         DCX (ZSTD)                              DCX (ZSTD)
               │ 2. zstd decompress                    │ 5. zstd compress
               ▼                                       │    (header template
             BND4  ──────────────────────────────►   BND4    from step 2)
               │ 3. locate + parse params              ▲
               ▼                                       │ 4. serialize params
        param rows  ──── apply mod spec ────► modified param rows
                          (declarative)
```

Steps 1–2 and 5–6 are implemented and verified byte-for-byte against the real
install (see `src/crypto.zig`, `src/dcx.zig`). Steps 3–4 (BND4 + PARAM) and the mod
spec are the next milestones (see `docs/tasks.md`).

### DCX header strategy

We do not re-derive FromSoftware's DCX parameter fields. On unpack we keep the original
0x4C-byte header verbatim; on repack we reuse it and patch only the two DCS size fields
(uncompressed, compressed). This makes us robust to unknown/changed header fields across
game patches.

The same "preserve what you don't understand" principle applies to BND4: unknown header
fields and file entries we don't edit are copied through unchanged.

## Module layout

```
src/
  main.zig               CLI entry point (subcommands)
  crypto.zig             AES-256-CBC for regulation.bin (key, IV-prefix layout)
  dcx.zig                DCX container: parse header, zstd (de)compress via libzstd
  bnd4.zig               BND4 archive reader/writer
  param.zig              PARAM file reader (rows as raw bytes, edited in place)
  paramdef.zig           field access (ints, floats, bitfields) over row bytes
  spec.zig               declarative patch types, shared with mods/
  modspec.zig            applies specs to an archive; rejects conflicting patches
  generated/
    paramdefs.zig        field tables generated from the vendored XML
mods/                    built-in patch specs compiled into `ermod` -- NOT how a
                         mod is written (a mod is a .lua file; see scripting.md)
  mods.zig               spec registry
  level60.zig            all classes start at level 60
  class_gear.zig         extra weapon/shield/consumables per class
paramdefs/               vendored Paramdex XML (see its README)
tools/gen_paramdef.py    XML -> Zig field tables
examples/                the example mods -- what a mod looks like; also the SDK test corpus
docs/                    architecture (this file), install, scripting, deployment, tasks
build_out/, mod/         output, gitignored
```

Module dependencies are acyclic: `mods/` and `src/modspec.zig` both depend on
`src/spec.zig`, which depends on nothing. This is why the patch types live in
their own file rather than in `modspec.zig` — Zig also forbids a module from
importing files above its root directory, so `mods/` must be its own module.

### CLI surface (current and planned)

```
ermod decrypt <regulation.bin> <out.dcx>          # layer 1 only
ermod encrypt <in.dcx> <out.bin>                  # layer 1 only
ermod unpack  <regulation.bin> <out.bnd>          # layers 1+2
ermod pack    <in.bnd> <template.bin> <out.bin>   # layers 5+6
ermod ls      <regulation.bin>                    # list BND4 entries
ermod extract <regulation.bin> <name> <out>       # extract one param
ermod show    <regulation.bin> <row> [field]      # inspect CharaInitParam rows
ermod mods                                        # list available mods
ermod verify-ids <regulation.bin>                 # check mod IDs exist in the game
ermod selftest   <regulation.bin>                 # golden checks (see Testing)
ermod apply   <regulation.bin> <out.bin> <mod>... # full pipeline; a mod is a
                                                  # built-in spec name or a .lua
                                                  # launch mod path
```

`ermod apply` is the offline command: reads the game's regulation.bin, applies
the named mods (built-in specs or `.lua` files), and writes a modded copy that
the engine loads with `ermod-engine --regulation`.
`make apply` wraps it with the default game path and mod list.

### Applying Lua mods offline

A mod argument is either a built-in spec name (`level60`) or a path to a `.lua`
launch mod; the two can be mixed on one command line:

```
ermod apply "$GAME/regulation.bin" mod/regulation.bin level60.lua class-gear
```

The Lua mod runs through the shared `ermod-lua` front end — the same loader,
manifest validation, sandbox and instruction budget the injected runtime uses,
compiled for the host. What differs is only the `Host`: `src/offline_host.zig`
implements `param_table` as "BND4 entry name → `paramview.Table` over that
entry's bytes", where the runtime implements it as a walk of the game's
`SoloParamRepository`. Both hand back a view over the same on-disk PARAM
layout, so `sdk.params.row("CharaInitParam", 3000).soulLv = 60` writes the same
bytes at the same offset in both. That is the whole of "author live, ship
offline": one code path, two backends.

Everything else on the `Host` vtable is unavailable offline and says so — there
is no frame to draw an overlay on, no session to measure, no game to persist a
store for. Consequently **only launch mods are accepted**; an event mod is
refused with "event mods run in-game only" rather than silently doing nothing,
because offline has no events to fire.

Three refusals exit 1 without writing an output file, since a half-patched
archive is worse than none: an event mod, a mod that errors or exceeds its
instruction budget in `on_launch`, and a cross-mod write conflict. The sandbox
and budget are the game's, not a weaker host copy — a mod calling `os.execute`
finds `os` nil offline exactly as it does in-game, and a runaway `on_launch` is
cut off rather than hanging `apply`.

**Conflicts are an error offline, a warning live.** Both halves feed one
`param_writes.Ledger` keyed by `(table, row, field)`, including the Zig `spec`
pipeline, so a Zig patch and a Lua write on one field collide like any two
mods:

```
ermod: conflict — class-tweaks wrote CharaInitParam[3000].soulLv, already written by level60
ermod: refusing to pack; resolve the overlap or apply one mod at a time (1 conflicting write(s))
```

In the game, a later write wins and the conflict is logged — a hot-reloaded mod
rewrites its own fields by design. Offline, the file a player installs must not
depend on the order two mods happened to be listed in, so `apply` refuses. One
ledger, two policies.

Two consequences worth stating:

- The ledger keys ownership by **mod name**, so two mods that share a name are
  treated as one and never conflict with each other. That is the same rule that
  makes a hot reload silent, and it means `level60.lua` and the `level60` spec
  (which deliberately share a name and write the same 90 fields) can be applied
  together without complaint.
- The Zig `spec` pipeline runs first, then the Lua mods. `modspec` replaces an
  entry's buffer when it writes a param back, and the Lua host holds views into
  those buffers — so the specs must settle before any view is taken.

## Format notes

### BND4

Little-endian archive, 0x40-byte header: `BND4` magic, big-endian and bit-order
flags, file count (194 in the shipped regulation), header size (0x40), an 8-byte
version string (`11611000`), per-entry size (0x24), and a `dataStart` field.
Entries follow at 0x40, then a UTF-16LE name table, then file data. Names are full
authoring paths, e.g.
`N:\GR\data\Param\param\GameParam\merged\DLC02\CharaInitParam.param`.

Per entry (0x24 bytes): flags byte (`0x40` = uncompressed), `0xFFFFFFFF`, u64 size,
u64 uncompressed size, u32 data offset, u32 id, u32 name offset. Param files in the
regulation BND4 are stored uncompressed, so we reject any other flag value rather
than silently mishandling it.

Two traps worth knowing, both confirmed against the shipped file:

- **`dataStart` is not where data starts.** In the regulation BND4 the header's
  `dataStart` is 291841 while the first entry's data begins at 37728 — the field
  marks the end of the header/hash region, which sits *after* some file data.
  Laying files out from `dataStart` inflates the archive by ~254 KB. The writer
  therefore derives the real start from the smallest entry data offset.
- **The entry size is not a constant.** It is implied by the format byte's bit
  flags (IDs, Names, LongOffsets, Compression). 0x24 is the common Elden Ring
  case, not a rule; we assert it rather than assume it, so a differently
  configured binder fails loudly.

Entries are padded to 16-byte alignment. The writer reuses the original header and
name table verbatim and recomputes only sizes and data offsets, which is what makes
a no-op rebuild byte-identical.

Reference implementation: SoulsFormats `BND4.cs` / `BinderFileHeader.cs`.

### PARAM

Each `.param` file is a fixed-schema table. Elden Ring uses the 64-bit variant:

- `0x00` u32 strings offset, `0x08` u16 paramdef data version, `0x0A` u16 row count,
  `0x10` u64 offset to the param type string (e.g. `CHARACTER_INIT_PARAM`),
  `0x2C` endianness and format flag bytes, `0x30` u64 data start
- `0x40` row descriptors, 24 bytes each: u32 row ID, 4 bytes padding, u64 data
  offset, u64 name offset (usually 0 — row names live in Paramdex, not the file)
- row data: a fixed-size packed struct, identical layout for every row

**Row size is not stored anywhere.** It is derived from the gap between the first two
rows' data offsets (320 bytes for `CharaInitParam`), falling back to the strings
offset when there is only one row.

The row *layout* is likewise absent from the file. Field names, types and offsets
come from community **paramdefs** (Paramdex XML). We vendor the XML for the params we
touch and generate Zig field tables from it with `tools/gen_paramdef.py`.

Two details the generator has to get right:

- Fields are packed with **no alignment padding** — padding is explicit via `dummy8`
  fields — so offsets are a simple running sum.
- Consecutive bitfields share a storage unit, and `dummy8` bitfields pack into the
  *same* unit as an adjacent `u8`. Treating `dummy8` as a separate type yields 321
  bytes for `CharaInitParam` instead of the correct 320, which would shift every
  field after the bitfield and corrupt rows.

The generated `row_size` is checked against the game's actual row stride at runtime,
so a paramdef that no longer matches the installed game version is caught rather than
silently writing to wrong offsets.

**Row IDs are not unique.** They are unique in every param a mod has touched so far,
but not in general: `RandomAppearParam` ships 26 IDs that appear on more than one
descriptor, each with its own row data. Both readers resolve a lookup by ID to the
*first* matching descriptor (`param.findRow`, `paramview.Table.row`); the later copies
are reachable only by position (`Table.rowAt`). A mod that edits a duplicated ID
therefore edits the first row of that ID and no other — consistently offline and live,
since both paths use the same rule, but worth knowing before writing a mod against a
param where IDs repeat. This is a case no synthetic fixture had; `ermod selftest`'s
reader cross-check over the real archive is what surfaced it.

For editing we only need: find row by ID → patch bytes at known field offsets → write
back, in place. Row sizes never change, so no offsets need recomputing. Full paramdef
coverage of all 194 params is not required.

### Params of interest

| Param | Purpose for us |
| --- | --- |
| `CharaInitParam` | Starting class definitions: level, stats, equipped gear, items. Rows for the ten playable classes (Vagabond … Wretch). Our level-60 and starting-gear mods are edits here. Exact row IDs to be confirmed against paramdef during implementation. |
| `EquipParamWeapon` / `EquipParamProtector` | Weapon/armor IDs referenced from CharaInitParam; read-only lookups to pick gear. |
| `ItemLotParam_map` | Treasure item lots (chests, corpses). Needed if we go the "physical chest in the world" route. |
| `SpEffectParam` | Buffs/heals; relevant to the later NPC-healer idea. |

### "Chest with items" — two implementation routes

1. **Starting inventory (param-only, recommended first).** `CharaInitParam` rows contain
   equipment and item slots per class. Granting each class its gear at creation needs
   only param edits — fully covered by this architecture.
2. **Physical chest near spawn (world edit).** Requires a treasure asset placement in a
   map file (`.msb`) plus an `ItemLotParam_map` row, and possibly an EMEVD event script
   edit. That drags in two more file formats. Deferred; tracked as a stretch task.

## Deployment

Two ways a mod reaches the game. Both leave the install untouched and both run
with EAC absent; the difference is what the player has to install.

### The engine (default)

`.lua` mods are read from one directory in the game's Proton prefix, which the
launcher creates:

```
<prefix>/pfx/drive_c/ermod/          ← everything the engine stages, outside the install
  mods/                              ← .lua files, one per mod; C:\ermod\mods in-game
  regulation.bin                     ← optional: an `ermod apply` artifact to load
  store/                             ← per-mod persistent settings
  captures/                          ← frame captures
```

where `<prefix>` is `steamapps/compatdata/1245620`. `ermod-engine --mods <dir>`
symlinks `mods/` at a working tree instead, so an author edits the files the
game loads; `--regulation <file>` does the same for the artifact.

A modded `regulation.bin` is loaded by hooking the one file open that matters
(`CreateFileW` through the executable's import table) and returning our copy —
so the game's own file is never overwritten, and Steam's integrity check has
nothing to revert. See the engine repo's `docs/e7-regulation-redirect-scoping.md`.

### Mod Engine 2 (legacy, untested)

[Mod Engine 2](https://github.com/soulsmods/ModEngine2) is archived upstream.
An `ermod apply` artifact is an ordinary modded `regulation.bin`, so it can
load one — but it has no runtime in the game, meaning no `.lua` mods, no live
params, no hot reload and no overlay. We do not test this route against
current game builds. [deploy.md](deploy.md) documents it in an appendix for
players who already run it.

## Testing strategy

- **Unit tests** per module (`zig build test`): crypto and DCX roundtrips, BND4 and
  PARAM parse/serialize on synthetic fixtures, bitfield read/write isolation, and mod
  spec invariants (stat spreads sum to the target level, weapon IDs are base IDs, all
  ten classes covered exactly once). These need no game data, so they run in CI.
- **Golden checks against the real install** — `ermod selftest`, run via
  `make selftest`. Needs the game, so it is local-only, never CI:
  1. Parsing the real 54 MB BND4 and rebuilding it with no patches is **byte-identical**
     to the original. This is the strong guarantee: any layout mistake in the writer
     shows up immediately instead of as a subtly broken archive.
  2. Applying both mods changes exactly 264 bytes, all within `CharaInitParam.param`,
     leaving the other 193 params bit-for-bit untouched.
  3. Row size and param type from the generated paramdefs match the shipped data, so a
     game patch that changes a param's layout fails loudly.
  4. The two PARAM readers agree on every table in the archive — 194 tables, 178 935
     rows. `param.zig` owns a copy of a file and is what `apply` patches; `paramview.zig`
     (in `ermod-lua`) is a zero-copy view over bytes it does not own, and is what a Lua
     mod sees through `sdk.params`, live or offline. A mod is authored against the
     second and shipped through the first, so a divergence between them would mean a
     field edited in-game lands somewhere else in the packed archive. `src/paramcheck.zig`
     holds the comparison; it also runs over synthetic images in CI.
  5. **The golden test for the offline half**: `level60.lua` and `level60.zig` carry
     the same ten stat spreads written two different ways — one through `sdk.params`
     against the offline `Host`, one through the Zig `spec` pipeline — and must
     produce the same BND4, byte for byte. This is the proof that a mod authored
     against the live backend ships unchanged through the offline one.

     The comparison is at the BND4 payload, which is what the mods touch; the
     container around it is deterministic too (zero IV, fixed zstd parameters),
     so two `apply` outputs from the same input are byte-identical files.
- **ID validation** — `ermod verify-ids` resolves every weapon, armour and goods ID the
  mods reference against the game's own tables. This is what caught that upgraded
  weapon IDs (`base + 6`) do not exist as rows.
- **In-game verification**: final acceptance for each mod is loading it in the
  running game through the engine and checking behaviour. Done for the
  `level60` artifact — the live `CharaInitParam` table reads `soulLv=60` for
  row 3000 with no mods loaded, through the `--regulation` redirect.

## Security / legal posture

- The AES key is community-public (shipped in SoulsFormats and every param editor);
  including it is standard practice in the modding ecosystem.
- We never distribute FromSoftware's data — the repo holds only tooling and mod specs.
  `build_out/` (which can contain unpacked game data) is gitignored.
- Modded play stays offline. The README and deploy docs must repeat this warning.
- **The engine binaries published here are closed-source**, which is a real
  thing to ask of a user: an injected DLL running inside their game. What
  offsets that is what is *not* closed — the sandbox a mod runs in, its
  instruction budget, every `sdk.*` binding and the `Host` vtable that bounds
  them are all in this repository, so the capability surface of any community
  mod is auditable without the engine's source. The engine's own guarantees
  (never `start_protected_game.exe`, EAC re-checked in-process, unknown game
  build disables every hook, the install never written) are stated in its
  changelog and observable in the log it writes.
