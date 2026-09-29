# Shipping a mod as a regulation.bin

> A modded `regulation.bin` is safe to load through the engine and risks a
> ban only when the game's normal Steam launch loads it. See
> [Before you start](install.md#before-you-start).

## 1. Build the modded regulation

```sh
GAME="$HOME/.local/share/Steam/steamapps/common/ELDEN RING/Game"
mkdir -p mod
ermod-engine mod bake "$GAME/regulation.bin" mod/regulation.bin level60 class-gear
```

`mod bake` does not create the output directory, hence the `mkdir`.
`ermod-engine paths` prints the game directory if yours differs; on macOS
it is inside the Wine bottle.

The game directory is only ever read. Verify that for yourself at any time:

```sh
md5sum "$GAME/regulation.bin"   # unchanged before and after
```

## 2. Load it

```sh
ermod-engine --regulation mod/regulation.bin
```

The game reads your copy instead of its own, and the game's own
`regulation.bin` is never touched.
[install.md, step 4](install.md#4-or-load-a-modded-regulation) explains how
the link works and how to clear it; the rest of install.md sets up the
engine if you do not have it yet.

## 3. Verify in game

Start a new character and check the class screen: every class should show
**level 60** with a stat spread that keeps its identity, and the extra weapon,
shield or catalyst and consumables, the effects of the `level60` and
`class-gear` mods applied in step 1.

If nothing changed, read the runtime log. It names the redirect explicitly:

```
ermod-runtime: regulation redirect — game's regulation.bin -> C:\ermod\regulation.bin
```

`ermod-engine paths` prints where the log lives.

---

## Appendix: Mod Engine 2 (legacy)

[Mod Engine 2](https://github.com/soulsmods/ModEngine2) is **archived
upstream** and is not required by anything here. It is documented only because
some players already run it for other mods, and a `regulation.bin` produced by
`ermod-engine mod bake` is an ordinary file it can load.

Two limitations worth knowing before choosing this route:

- **It cannot run `.lua` mods.** It has no runtime inside the game, so it
  loads only what `mod bake` wrote into the file: no live params, no hot
  reload, no overlay, no events.
- **We do not test it.** The Mod Engine 2 route has never been booted
  against a current game build here. If it breaks on a game patch, upstream
  is archived.

If you still want it: unpack a Mod Engine 2 release beside this repo (it is
not committed) so you have `modengine2_launcher.exe`, the `modengine2/`
directory and `config_eldenring.toml`, then point its `config_eldenring.toml`
at your `mod/` directory:

```toml
[extension.mod_loader]
enabled = true
loose_params = false
mods = [
    { enabled = true, name = "elden-ring-mods", path = "/absolute/path/to/elden-ring-mods/mod" },
]
```

Its launcher is a Windows executable, so it has to run inside the game's own
Proton prefix, the same environment plumbing the engine's launcher does for
you. That plumbing is the fiddly part, and it is the reason the engine route
exists.

## Co-op

The engine's co-op syncs Lua mods, not a `regulation.bin` loaded with
`--regulation`. Every player in a session must load the same file, and
nothing checks that for you. See the [co-op guide](coop.md).
