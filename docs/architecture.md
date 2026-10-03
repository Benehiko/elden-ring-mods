# Architecture

## Goal

Mods for Elden Ring on Linux and macOS that a player can write in **Lua** and
run in the live game, and that can also be shipped as a modified
`regulation.bin` for people who only want a file. The vanilla install is
read-only input in both directions; nothing here ever writes to it.

Two halves, one mod format:

- **In-game.** The engine injects a runtime into the running game, which
  loads `.lua` mods, hooks events, and reads and writes the game's live PARAM
  tables. Edit a mod and it reloads within a second.
- **Offline.** `ermod-engine mod bake` runs the _same_ Lua mod against an
  unpacked `regulation.bin` on the host and writes a modded copy. The engine
  can load that copy directly, so no ModEngine is required.

One Lua front end inside the engine serves both, which is what makes "author
live, ship offline" one code path rather than two implementations that drift.

Non-goal: FromSoftware's servers and anti-cheat. The engine launches
`eldenring.exe` directly, so Easy Anti-Cheat never runs and no modded session
reaches FromSoftware's servers. The engine's own co-op runs peer to peer
between the players' machines. [install.md](install.md#before-you-start)
states the safety rules in full.

## What lives where

This repository is the open half. The engine, meaning the launcher, the
injected runtime, the AOB signatures and the hooks, is a separate
**closed-source** repository, and its binaries are published on this
repository's Releases page because that is where the people who need them are.

The split is deliberate and is drawn at the mod's blast radius:

|                     |                                                                                                                                                                                      |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Open (here)**     | the surface a mod is written against: the generated SDK stubs, the worked examples, and this documentation                                                                           |
| **Closed (engine)** | everything executable: the Lua sandbox and every `sdk.*` binding, plus signature scanning, inline detours, live param-table walking, the D3D12 overlay, process launch and injection |

A community mod's whole capability surface is the `Host` vtable behind the
`sdk.*` bindings: if a capability is not a function on it, no mod can reach
it. That interface lives in the engine with the rest of the front end, so
what is published here is an exhaustive _enumeration_ of the surface,
`stubs/ermod.lua`, generated from the binding tables themselves, rather than
an implementation you can read. The sandbox's behaviour remains testable from
outside: `base`, `table`, `string` and `math` only, code-loading globals
stripped, an instruction budget per call.

## Constraints

1. **Never write into the game install directory.**
   `~/.local/share/Steam/steamapps/common/ELDEN RING/Game/` is read-only input.
   The engine honours this too: everything it stages lives in the Wine prefix
   or in its own data directory.
2. **Reproducible output.** Mods are described declaratively or in sandboxed
   Lua and applied by the tool; running the pipeline twice from the same
   inputs yields the same file. No hand-edited binaries.
3. **Zig only** for the engine (currently Zig 0.16), with a vendored
   `libzstd` for DCX compression. No .NET tooling (Smithbox etc.) in the
   build path. We may use those interactively for research, but the pipeline
   must not depend on them. _Mods themselves are Lua, not Zig_; this
   constraint is about the tooling.
4. **Safety by layout.** Documentation and output layout must make it hard to
   launch a modded `regulation.bin` through the protected launcher.

## The data we are modifying

Nearly all "gameplay numbers" in Elden Ring live in `regulation.bin`, a ~2 MB file in
the game root. It is a nested container:

```text
regulation.bin                      (2 MB, encrypted)
└── AES-256-CBC                     key: community-known 32-byte key (SoulsFormats),
    │                               IV: first 16 bytes of the file (the game
    │                               ships zeros; so do we), no padding
    └── DCX container               big-endian header, "DCP" scheme = ZSTD
        │                           (ZSTD since game patch 1.12; older was DFLT/zlib)
        │                           the game's decoder keeps 64 KiB of history:
        │                           write with windowLog 16
        └── BND4 archive            ~54 MB, FromSoftware's generic file bundle
            └── 194 *.param files   fixed-size row tables (CharaInitParam,
                                    ItemLotParam_map, SpEffectParam, ...)
```

Each layer is documented in the format sections below. The layers are independent:
encrypt/decrypt, compress/decompress, bundle/unbundle, and param row editing are
separate modules in the engine, each with its own tests.

## Pipeline

```text
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
        param rows  ──── apply mods ─────────► modified param rows
```

The engine implements all six steps. Rebuilding the real archive with no
mods applied is byte-identical to the original.

### DCX header strategy

We do not re-derive FromSoftware's DCX parameter fields. On unpack we keep the original
0x4C-byte header verbatim; on repack we reuse it and patch only the two DCS size fields
(uncompressed, compressed). This makes us robust to unknown or changed header fields
across game patches.

The same "preserve what you don't understand" principle applies to BND4: unknown header
fields and file entries we don't edit are copied through unchanged.

## The author commands

```text
ermod-engine mod verify <mod.lua>...                                # would each mod load in-game?
ermod-engine mod perf  <mod.lua> [--frames N] [--runes N] [--deaths N] [--regulation <file>]
ermod-engine mod bake <regulation.bin> <out.bin> <mod>...         # full pipeline; a mod is a
                                                               # built-in spec name or a
                                                               # .lua launch mod path
```

`ermod-engine mod bake` is the offline command: it reads the game's
`regulation.bin`, applies the named mods (built-in specs or `.lua` files), and
writes a modded copy that the engine loads with `ermod-engine --regulation`.
`ermod-engine --help` lists every command.

### Applying Lua mods offline

A mod argument is either a built-in spec name (`level60`) or a path to a `.lua`
launch mod; the two can be mixed on one command line:

```text
ermod-engine mod bake "$GAME/regulation.bin" mod/regulation.bin level60.lua class-gear
```

The Lua mod runs through the same loader, manifest validation, sandbox and
instruction budget the injected runtime uses, compiled for the host. Only the
`Host` differs. Offline, `param_table` returns a view over a BND4 entry's
bytes; in the game it walks the game's `SoloParamRepository`. Both hand back a
view over the same on-disk PARAM layout, so
`sdk.params.row(sdk.params.file.CharaInitParam, 3000).soulLv = 60` writes the same bytes at
the same offset in both. That is the whole of "author live, ship offline":
one code path, two backends.

Everything else on the `Host` vtable is unavailable offline and says so. There
is no frame to draw an overlay on, no session to measure, no game to persist a
store for. [scripting.md](scripting.md) lists what that means for a mod:
which mods `mod bake` accepts, what it refuses, and how it treats two mods
writing one field.

Both halves feed one write ledger keyed by `(table, row, field)`, including
the built-in Zig specs, so a Zig patch and a Lua write on one field collide
like any two mods. Offline, a collision is an error; in the game, the engine
checks every mod's writes before any of them land
([scripting.md, Conflicts](scripting.md#conflicts)). Two consequences worth
stating:

- The ledger keys ownership by **mod name**, so two mods that share a name are
  treated as one and never conflict with each other. That is the same rule that
  makes a hot reload silent, and it means `level60.lua` and the `level60` spec
  (which deliberately share a name and write the same 90 fields) can be applied
  together without complaint.
- The Zig specs run first, then the Lua mods. Writing a param back replaces
  an entry's buffer, and the Lua host holds views into those buffers, so the
  specs must settle before any view is taken.

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
  `dataStart` is 291841 while the first entry's data begins at 37728. The field
  marks the end of the header and hash region, which sits _after_ some file data.
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
  offset, u64 name offset (usually 0, since row names live in Paramdex, not the file)
- row data: a fixed-size packed struct, identical layout for every row

**Row size is not stored anywhere.** It is derived from the gap between the first two
rows' data offsets (320 bytes for `CharaInitParam`), falling back to the strings
offset when there is only one row.

The row _layout_ is likewise absent from the file. Field names, types and offsets
come from community **paramdefs** (Paramdex XML). The engine keeps the XML for the
params it touches and generates its Zig field tables from it.

Two details the generator has to get right:

- Fields are packed with **no alignment padding**, since padding is explicit via
  `dummy8` fields, so offsets are a simple running sum.
- Consecutive bitfields share a storage unit, and `dummy8` bitfields pack into the
  _same_ unit as an adjacent `u8`. Treating `dummy8` as a separate type yields 321
  bytes for `CharaInitParam` instead of the correct 320, which would shift every
  field after the bitfield and corrupt rows.

The generated `row_size` is checked against the game's actual row stride at runtime,
so a paramdef that no longer matches the installed game version is caught rather than
silently writing to wrong offsets.

**Row IDs are not unique.** They are unique in every param a mod has touched so far,
but not in general: `RandomAppearParam` ships 26 IDs that appear on more than one
descriptor, each with its own row data. Both of the engine's PARAM readers resolve a
lookup by ID to the _first_ matching descriptor; the later copies are reachable only
by position. A mod that edits a duplicated ID therefore edits the first row of that
ID and no other, consistently offline and live, since both paths use the same rule,
but worth knowing before writing a mod against a param where IDs repeat. No
synthetic fixture had this case; the engine's cross-check of both readers over the
real archive surfaced it.

For editing we only need: find row by ID → patch bytes at known field offsets → write
back, in place. Row sizes never change, so no offsets need recomputing. Full paramdef
coverage of all 194 params is not required.

### Params of interest

| Param                                      | Purpose for us                                                                                                                                                                                                        |
| ------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `CharaInitParam`                           | Starting class definitions: level, stats, equipped gear, items. Rows 3000 to 3009 are the ten playable classes (Vagabond … Wretch; see [classes.md](classes.md)). Our level-60 and starting-gear mods are edits here. |
| `EquipParamWeapon` / `EquipParamProtector` | Weapon/armor IDs referenced from CharaInitParam; read-only lookups to pick gear.                                                                                                                                      |
| `ItemLotParam_map`                         | Treasure item lots (chests, corpses). Needed if we go the "physical chest in the world" route.                                                                                                                        |
| `SpEffectParam`                            | Buffs/heals; relevant to the later NPC-healer idea.                                                                                                                                                                   |

### "Chest with items": two implementation routes

1. **Starting inventory (param-only, recommended first).** `CharaInitParam` rows contain
   equipment and item slots per class. Granting each class its gear at creation needs
   only param edits, fully covered by this architecture.
2. **Physical chest near spawn (world edit).** Requires a treasure asset placement in a
   map file (`.msb`) plus an `ItemLotParam_map` row, and possibly an EMEVD event script
   edit. That drags in two more file formats. Deferred.

## Deployment

Two ways a mod reaches the game. Both leave the install untouched and both run
with EAC absent; the difference is what the player has to install.

### The engine (default)

The runtime reads everything from `C:\ermod` inside the game's Wine prefix
(`<prefix>/drive_c/ermod`). The mods and profiles there are links to the
engine's data directory on the host, re-made on every launch, so a rebuilt
prefix loses nothing:

```text
<prefix>/drive_c/ermod/
  mods/            → ~/.local/share/ermod/mods (or the --mods directory, for that launch)
  profiles/        → ~/.local/share/ermod/profiles
  engine.cfg       → ~/.local/share/ermod/engine.cfg
  regulation.bin   → the --regulation file, until --regulation none
  store/           per-mod persistent settings
  captures/        frame captures
```

`<prefix>` is the Proton prefix on Linux
(`steamapps/compatdata/1245620/pfx`) and the Wine bottle on macOS.
[install.md](install.md) is the player's view of the same layout.

A modded `regulation.bin` is loaded by hooking the one file open that matters
(`CreateFileW` through the executable's import table) and returning our copy,
so the game's own file is never overwritten, and Steam's integrity check has
nothing to revert.

### Mod Engine 2 (legacy, untested)

[Mod Engine 2](https://github.com/soulsmods/ModEngine2) is archived upstream.
An `ermod-engine mod bake` artifact is an ordinary modded `regulation.bin`, so it can
load one, but it has no runtime in the game, meaning no `.lua` mods, no live
params, no hot reload and no overlay. We do not test this route against
current game builds. [deploy.md](deploy.md) documents it in an appendix for
players who already run it.
