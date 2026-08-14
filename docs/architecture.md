# Architecture

## Goal

Build Elden Ring gameplay mods (custom starting level, starting gear, item lots, and
later more ambitious content) using our own tooling written in Zig, without ever
modifying the installed game. The vanilla install is treated as read-only input; all
modified files are written to a separate mod directory that
[Mod Engine 2](https://github.com/soulsmods/ModEngine2) overlays at runtime.

Non-goals:

- We do not modify or redistribute the Seamless Co-op mod (closed source). Co-op
  bug fixes and player-limit changes are upstream feature requests, not our code.
- We do not touch multiplayer, anti-cheat, or the FromSoftware servers. Modded play
  is strictly offline (Mod Engine 2 disables EAC).

## Constraints

1. **Never write into the game install directory.**
   `~/.local/share/Steam/steamapps/common/ELDEN RING/Game/` is read-only input.
2. **Reproducible output.** Mods are described declaratively and applied by the tool;
   running the pipeline twice from the same inputs yields the same mod folder.
   No hand-edited binaries.
3. **Zig only** for our code (currently Zig 0.16), plus system `libzstd` for DCX
   compression. No .NET tooling (Smithbox etc.) in the build path — we may use those
   interactively for research, but the pipeline must not depend on them.
4. **Offline safety.** Documentation and output layout must make it hard to
   accidentally run modded files against the live game servers.

## The data we are modifying

Nearly all "gameplay numbers" in Elden Ring live in `regulation.bin`, a ~2 MB file in
the game root. It is a nested container:

```
regulation.bin                      (2 MB, encrypted)
└── AES-256-CBC                     key: community-known 32-byte key (SoulsFormats),
    │                               IV: first 16 bytes of the file, no padding
    └── DCX container               big-endian header, "DCP" scheme = ZSTD
        │                           (ZSTD since game patch 1.12; older was DFLT/zlib)
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
mods/
  mods.zig               mod registry
  level60.zig            all classes start at level 60
  class_gear.zig         extra weapon/shield/consumables per class
paramdefs/               vendored Paramdex XML (see its README)
tools/gen_paramdef.py    XML -> Zig field tables
docs/                    architecture (this file), deployment, task breakdown
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
ermod apply   <regulation.bin> <out.bin> <mod>... # full pipeline
```

`ermod apply` is the end-user command: reads the game's regulation.bin, applies the
named mods, and writes a modded copy ready for Mod Engine 2. `make apply` wraps it
with the default game path and mod list.

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

## Deployment (Mod Engine 2)

Output layout:

```
mod/                      ← Mod Engine 2 mod directory (ours, in this repo or ~/games)
  regulation.bin          ← produced by `ermod apply`
modengine2/               ← unpacked Mod Engine 2 release (not committed)
  config_eldenring.toml   ← points at mod/
```

On Linux/Proton, Mod Engine 2's launcher is run through the same Proton prefix as the
game (documented in `docs/deploy.md` once written). Mod Engine 2 loads `mod/regulation.bin`
in place of the game's own at runtime and disables EAC; the install stays untouched and
the game stays offline while modded.

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
- **ID validation** — `ermod verify-ids` resolves every weapon, armour and goods ID the
  mods reference against the game's own tables. This is what caught that upgraded
  weapon IDs (`base + 6`) do not exist as rows.
- **In-game verification**: final acceptance for each mod is loading it through
  Mod Engine 2 and checking behaviour. Still outstanding — see tasks.md.

## Security / legal posture

- The AES key is community-public (shipped in SoulsFormats and every param editor);
  including it is standard practice in the modding ecosystem.
- We never distribute FromSoftware's data — the repo holds only tooling and mod specs.
  `build_out/` (which can contain unpacked game data) is gitignored.
- Modded play stays offline. The README and deploy docs must repeat this warning.
