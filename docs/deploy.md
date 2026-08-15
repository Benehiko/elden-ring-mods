# Deploying the mod (Linux / Proton)

> **Modded play must stay offline.** Both loaders below launch the game with
> Easy Anti-Cheat disabled. Never load a modified `regulation.bin` through the
> normal Steam launcher while connected to FromSoftware's servers — that risks
> a ban.

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

## 2. Choose a loader

The modded `regulation.bin` is a normal game file; something has to make the
game read it instead of its own. Two routes:

- **The engine** (`ermod-engine --regulation`). If you already run the
  private engine repo's launcher, it can load the artifact directly — it is
  in the game's load path anyway, and redirects the one file open that
  matters. Nothing to download, nothing to configure. See that repo's README
  ("Shipping an artifact") and `docs/e7-regulation-redirect-scoping.md`.
- **Mod Engine 2**, below. The route to use if you are not running the
  engine, and the one most Elden Ring players already have.

Both keep the game install read-only. Do not simply overwrite the game's
`regulation.bin`: Steam's integrity check reverts it, usually at the least
convenient moment.

## 3. Install Mod Engine 2

Download a release from [soulsmods/ModEngine2](https://github.com/soulsmods/ModEngine2)
and unpack it next to this repo (it is not committed here). You need
`modengine2_launcher.exe`, the `modengine2/` directory, and
`config_eldenring.toml`.

## 4. Point Mod Engine 2 at `mod/`

In `config_eldenring.toml`:

```toml
[modengine]
debug = false
external_dlls = []

[extension.mod_loader]
enabled = true
loose_params = false
mods = [
    { enabled = true, name = "elden-ring-mods", path = "/absolute/path/to/elden-ring-mods/mod" },
]
```

`path` must point at the `mod/` directory containing `regulation.bin`, not at the
file itself.

## 5. Launch through Proton

Mod Engine 2's launcher is a Windows executable, so it has to run in the same
Proton prefix as the game. Find the prefix (Elden Ring's Steam app ID is
`1245620`):

```sh
export STEAM_COMPAT_DATA_PATH="$HOME/.local/share/Steam/steamapps/compatdata/1245620"
export STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam"

PROTON="$HOME/.local/share/Steam/steamapps/common/Proton - Experimental/proton"
"$PROTON" run ./modengine2_launcher.exe -t er -c ./config_eldenring.toml
```

Adjust the Proton version to whichever one the game is set to use in Steam
(Properties → Compatibility).

Alternatively, add the launcher to Steam as a non-Steam game, set its
compatibility tool to the same Proton version, and put
`-t er -c /absolute/path/to/config_eldenring.toml` in the launch options — this
gets the environment variables right automatically.

## 6. Verify in game

Start a new character and check the class screen: every class should show
**level 60** with the stat spread from `mods/level60.zig`, and the extra weapon,
shield/catalyst and consumables from `mods/class_gear.zig`.

If the game starts but nothing changed, Mod Engine 2 is not loading the mod —
check that `path` is absolute and that `mod/regulation.bin` exists.

## Seamless Co-op

Seamless Co-op has its own launcher and its own mod-folder mechanism, and it is
closed source. Whether these param mods load alongside it has **not been tested**
— see the backlog in [tasks.md](tasks.md). All players in a session would need
identical param files, since starting stats and gear must agree.
