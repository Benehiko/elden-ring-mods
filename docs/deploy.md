# Deploying the mod (Linux / Proton)

> **Modded play must stay offline.** The engine launches the game with Easy
> Anti-Cheat absent — it runs `eldenring.exe` directly, never
> `start_protected_game.exe`. Never load a modified `regulation.bin` through
> the normal Steam launcher while connected to FromSoftware's servers — that
> risks a ban.

## 1. Build the modded regulation

```sh
zig build
GAME="$HOME/.local/share/Steam/steamapps/common/ELDEN RING/Game"
./zig-out/bin/ermod apply "$GAME/regulation.bin" mod/regulation.bin level60 class-gear
```

The game directory is only ever read. Verify that for yourself at any time:

```sh
md5sum "$GAME/regulation.bin"   # unchanged before and after
```

## 2. Load it

The modded `regulation.bin` is a normal game file; something has to make the
game read it instead of its own.

```sh
ermod-engine --regulation mod/regulation.bin
```

That is the whole step. The engine is already in the game's load path — it
launches the game and injects its runtime — so it redirects the single file
open that matters and hands back your copy. Nothing else to download, nothing
to configure, and the game's own `regulation.bin` is never touched, so Steam's
integrity check has nothing to revert. [install.md](install.md) is the setup
if you do not have the engine yet.

Do not simply overwrite the game's `regulation.bin`. Steam's integrity check
reverts it, usually at the least convenient moment.

## 3. Verify in game

Start a new character and check the class screen: every class should show
**level 60** with a stat spread that keeps its identity, and the extra weapon,
shield/catalyst and consumables — the effects of the `level60` and
`class-gear` mods applied in step 1.

If nothing changed, read the runtime log — it names the redirect explicitly:

```
regulation redirect — game's regulation.bin -> C:\ermod\regulation.bin
```

The log lives at
`<prefix>/pfx/drive_c/windows/system32/ermod-runtime.log`.

---

## Appendix: Mod Engine 2 (legacy)

[Mod Engine 2](https://github.com/soulsmods/ModEngine2) is **archived
upstream** and is not required by anything here. It is documented only because
some players already run it for other mods, and a `regulation.bin` produced by
`ermod apply` is an ordinary file it can load.

Two limitations worth knowing before choosing this route:

- **It cannot run `.lua` mods.** It has no runtime inside the game, so it
  loads only what `apply` baked into the file — no live params, no hot
  reload, no overlay, no events.
- **We do not test it.** The engine route is verified on the live game every
  milestone; the Mod Engine 2 route has never been booted against a current
  game build here. If it breaks on a game patch, upstream is archived.

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
Proton prefix — the same environment plumbing the engine's launcher does for
you. That plumbing is the fiddly part, and it is the reason the engine route
exists.

## Seamless Co-op

Seamless Co-op has its own launcher and its own mod-folder mechanism, and it is
closed source. Whether these param mods load alongside it has **not been tested**
— see the backlog in [tasks.md](tasks.md). All players in a session would need
identical param files, since starting stats and gear must agree.
