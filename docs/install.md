# Installing the engine

This page is for playing with mods, not for building anything. You need a
Steam copy of Elden Ring and the engine archive for your machine:

- **Linux (x86-64):** the game under Proton.
- **macOS (Apple Silicon):** the game inside a Wine bottle (CrossOver,
  Whisky, or any Wine you name).

No toolchain, no checkout, no ModEngine.

The engine is `ermod-engine`. It starts the game without Easy Anti-Cheat,
loads your mods into it, and never writes to the game install.

This file ships inside the release archive as `INSTALL.md`. The latest copy
lives at
<https://github.com/Benehiko/elden-ring-mods/blob/main/docs/install.md>.

---

## Before you start

**Anti-cheat and online play.** Read this section in full.

- **Easy Anti-Cheat never runs.** The engine launches `eldenring.exe`
  directly, never `start_protected_game.exe`. It refuses to launch while
  Easy Anti-Cheat is running, and the runtime checks again from inside the
  game before it enables anything. Neither check has a bypass flag.
- **No modded session reaches FromSoftware's servers.** The game's own
  online play runs through Easy Anti-Cheat, which never starts. Leave Steam
  online; Offline Mode is not needed.
- **The engine's co-op is its own.** It runs peer to peer, directly between
  the players' machines, and never touches FromSoftware's servers. See the
  [co-op guide](https://github.com/Benehiko/elden-ring-mods/blob/main/docs/coop.md).
- **What risks a ban** is launching the game the normal way, through Steam,
  with a modified `regulation.bin` installed over the game's own. That launch
  starts Easy Anti-Cheat and connects to FromSoftware's servers with a
  modified game. Keep a modded `regulation.bin` in a directory of your own
  and load it with `--regulation` ([step 4](#4-or-load-a-modded-regulation)).
  The game's own file then stays vanilla, and a normal launch stays safe.

You also need:

- **The game installed and launched normally at least once.** On Linux that
  first launch creates the Proton prefix the engine stages into.
- **Steam running.** The game talks to a Steam client as it starts. On macOS
  that is the Windows Steam inside the bottle, not a macOS Steam.

### Linux

**Proton installed for Elden Ring** (Proton Experimental is the usual
choice). The engine reads Steam's own setting for the game and uses the
Proton it names.

### macOS

- **A Wine bottle holding Windows Steam and the game.** Elden Ring is not a
  macOS title, so the Steam that installs it is Windows Steam, running in
  the same bottle as the game. That Steam must be running, and signed in,
  when you launch.
- **The engine finds the bottle and the Wine itself** if you use
  [CrossOver](https://www.codeweavers.com/crossover),
  [Whisky](https://github.com/Whisky-App/Whisky) or
  [protium](https://github.com/Benehiko/protium). It searches CrossOver's and
  Whisky's bottle directories, and protium's prefixes when `protium` is on
  your `PATH` or at `~/.local/bin/protium`. It takes the first bottle that
  holds a verified Elden Ring install and prefers the Wine from the same
  vendor. `--backend crossover|whisky|protium` (or `macos_backend` in
  `engine.cfg`) limits the search to one of them.
- **Any other Wine** (Game Porting Toolkit, Homebrew, Heroic) works when you
  name both:

  ```sh
  ./ermod-engine --prefix ~/path/to/bottle --wine /path/to/wine
  ```

  `WINEPREFIX` and `WINE` in the environment do the same.
- **Turn off the Steam overlay.** In the bottle's Steam: Elden Ring →
  Properties → uncheck "Enable the Steam Overlay while in-game". With it on,
  the game black-screens and closes itself under Wine on macOS, with or
  without the engine.
- **Apple Silicon.** The archive's `ermod-engine` is a native arm64 binary.
  The game and the engine's runtime are x86-64 Windows code, which your
  Wine runs through Rosetta 2, as it does for the game alone.
- **Gatekeeper will refuse the first run** of a browser download, because the
  engine is not notarized by Apple. Check the download, then clear the
  quarantine: see [On macOS: clear the quarantine](#on-macos-clear-the-quarantine).

A few things differ on macOS. The settings window is not built yet, so
`ermod-engine settings` prints the equivalent commands, and the first-launch
question about your characters is asked in the terminal. The in-game
overlay draws through the same path as on Linux, but no one has yet seen it
on a Mac's screen.

## 1. Unpack

Unpack the archive anywhere you like; your home directory is fine. It has
no installer and writes nothing outside the game's Wine prefix (the Proton
prefix on Linux, the bottle on macOS) and the engine's own data directory.

Releases are published on the
[Releases page](https://github.com/Benehiko/elden-ring-mods/releases). Each
archive is named for the engine version and your machine. Download yours, and
beside it `SHA256SUMS` and `SHA256SUMS.sigstore.json`, into one directory.

### Check the download is ours

Every release is signed. The signature covers `SHA256SUMS`, which pins each
archive by hash. Run these two steps from the download directory, **in this
order**, before you unpack anything.

**1. Check the signature over the checksums.** Install
[cosign](https://docs.sigstore.dev/cosign/system_config/installation/) (on a
Mac: `brew install cosign`; on Linux: your distribution's package, or a binary
from cosign's releases page), then:

```sh
cosign verify-blob SHA256SUMS \
  --bundle SHA256SUMS.sigstore.json \
  --certificate-identity 18033717+Benehiko@users.noreply.github.com \
  --certificate-oidc-issuer https://github.com/login/oauth
```

It must print `Verified OK`. Anything else means `SHA256SUMS` was not signed by
us: stop, and do not run anything from the download.

**2. Check your archive against the checksums.**

```sh
sha256sum --ignore-missing -c SHA256SUMS            # Linux
shasum -a 256 --ignore-missing -c SHA256SUMS        # macOS
```

Your archive must be listed as `OK`. `--ignore-missing` skips the archives
you did not download.

Step 1 is what makes step 2 mean anything: checksums downloaded from the same
page as the archive only prove the two agree, not that either came from us.

### Unpack

```sh
tar -xzf ermod-engine-<version>-linux-x86_64.tar.gz    # or ...-macos-aarch64.tar.gz
cd ermod-engine-<version>-linux-x86_64
```

Keep the three binaries together. `ermod-engine` is the one you run; it finds
`ermod-launcher.exe` and `ermod-runtime.dll` beside itself.

### On macOS: clear the quarantine

The macOS `ermod-engine` is signed ad hoc, not with an Apple Developer ID, and
is not notarized. A web browser marks what it downloads as quarantined, and
Gatekeeper refuses to run a quarantined binary it cannot trace to a registered
developer. The message reads _"ermod-engine" cannot be opened because the
developer cannot be verified_, or, on macOS 15 and later, _Apple could not
verify "ermod-engine" is free of malware_.

Once you have checked the download (above), clear the quarantine from the
unpacked directory:

```sh
xattr -dr com.apple.quarantine ermod-engine-<version>-macos-aarch64
```

Or, after the first refusal: System Settings → Privacy & Security → scroll to
the message about `ermod-engine` → **Open Anyway**.

Downloads made with `curl` or `gh release download` are not quarantined and
need neither step. Linux has no equivalent.

## 2. Check that it finds your game

```sh
./ermod-engine --dry-run
```

This resolves everything and stops before starting anything. A good run on
Linux names your install, your Proton, the prefix, and what it would stage,
link and run:

```text
info: ermod-engine <version>
info: found Elden Ring: /home/you/.local/share/Steam/steamapps/common/ELDEN RING/Game
info: game build 23850278
info: using Proton: Proton - Experimental
info: prefix /home/you/.local/share/Steam/steamapps/compatdata/1245620/pfx
info: launching eldenring.exe, never Easy Anti-Cheat
info: dry run: would stage ermod-launcher.exe and ermod-runtime.dll into /home/you/.local/share/Steam/steamapps/compatdata/1245620/pfx/drive_c/windows/system32
info: dry run: would run '/home/you/.local/share/Steam/steamapps/common/Proton - Experimental/proton waitforexitandrun C:\windows\system32\ermod-launcher.exe' (ERMOD_GAME_EXE=Z:\home\you\.local\share\Steam\steamapps\common\ELDEN RING\Game\eldenring.exe, ERMOD_RUNTIME_DLL=C:\windows\system32\ermod-runtime.dll)
info: dry run: would link /home/you/.local/share/Steam/steamapps/compatdata/1245620/pfx/drive_c/ermod/profiles -> /home/you/.local/share/ermod/profiles
info: dry run: would link /home/you/.local/share/Steam/steamapps/compatdata/1245620/pfx/drive_c/ermod/mods -> /home/you/.local/share/ermod/mods
info: dry run: not launching
```

On macOS the same run names the Wine it chose (`using Wine: …`) and gives
the bottle as the prefix.

If it cannot find something, this output says which check failed, so keep
it. Common cases:

- **`no Proton build found`** (Linux) means Elden Ring has never been
  launched through Proton on this machine, or Proton is not installed.
  Launch the game normally once, then try again.
- **`no Wine bottle found`** or **`found a Wine bottle but no Elden Ring
inside it`** (macOS) means none of the bottles the engine searched holds
  the game. Name the right one with `--prefix`.
- **`no Wine found to run the bottle with`** (macOS): name one with
  `--wine`.
- **A warning that your game build is not supported**: see
  [When something does not work](#when-something-does-not-work).

`./ermod-engine --version` prints the engine version and the game builds it
supports. `./ermod-engine paths` prints every path the engine uses.

## 3. Get a mod

Mods are Lua files. The example mods live in the
[`examples/`](https://github.com/Benehiko/elden-ring-mods/tree/main/examples)
directory of the mods repository. Three worth playing with:

- `level60.lua`: every starting class begins at level 60.
- `overlay.lua`: a small HUD of runes gained and deaths this session.
- `perf_monitor.lua`: frame rate and each mod's cost, in a window.

Download the ones you want, or clone the repository:

```sh
git clone https://github.com/Benehiko/elden-ring-mods.git
```

### Where mods go

Install each one by name:

```sh
./ermod-engine install elden-ring-mods/examples/level60.lua
./ermod-engine install elden-ring-mods/examples/overlay.lua
```

Do not install the whole `examples/` directory. Some of its mods teach
rather than play: `bad_sandbox.lua` fails on purpose, `double_runes.lua`
names a param the engine has no definition for and errors, and
`boss_rules_pack.lua` changes a game rule.

`install` copies a `.lua` file (or every `.lua` file in a directory you
name) into the engine's mods directory. The mod loads on the next launch,
or at once if the game is already running.

If you would rather copy files yourself, the mods directory is:

```text
~/.local/share/ermod/mods
```

The path is the same on Linux and macOS (`$XDG_DATA_HOME/ermod/mods` if you
set `XDG_DATA_HOME`). One `.lua` file per mod, no subdirectories, no
manifest to register them in.

The game, running under Wine, sees that directory as `C:\ermod\mods`, the
name the log uses. On every launch the engine links two directories in the
prefix to your data directory:

```text
<prefix>/drive_c/ermod/mods      -> ~/.local/share/ermod/mods
<prefix>/drive_c/ermod/profiles  -> ~/.local/share/ermod/profiles
```

That is deliberate. Proton rebuilds a prefix now and then (a Proton version
change, a "verify integrity of game files"), and anything kept inside one
eventually disappears. Your mods and your profile saves live outside it.

**Or keep your mods anywhere you like** and point the engine at them:

```sh
./ermod-engine --mods ~/ermod-mods
```

That links `C:\ermod\mods` to your directory for this launch only. A launch
without `--mods` links it back to `~/.local/share/ermod/mods`, so pass
`--mods` every time you want your own directory. `install` always copies
into `~/.local/share/ermod/mods`, never into a `--mods` directory.

This is the better arrangement if you edit mods: the files you edit are the
files the game loads, and saving one while the game runs reloads it within
a second. No relaunch.

The [scripting guide](https://github.com/Benehiko/elden-ring-mods/blob/main/docs/scripting.md)
covers writing your own.

## 4. Or load a modded regulation

Some mods are not scripts but a modified `regulation.bin`, built by
`ermod-engine mod bake` (see
[deploy.md](https://github.com/Benehiko/elden-ring-mods/blob/main/docs/deploy.md)).
The engine loads one directly:

```sh
./ermod-engine --regulation ~/mods/regulation.bin
```

The game reads that file instead of its own. The link stays in place, so
later launches keep loading it until you clear it with
`--regulation none`. **Your game's own `regulation.bin` is never
overwritten**, which matters, because Steam's integrity check silently
reverts a game file you replace by hand, usually at the worst moment.

Script mods and a modded regulation can both be active at once.

## 5. Profiles, and your own save

**The modded game never plays on your own save, and never writes it.**

This is not a setting. A mod that grants a hundred levels, a bad regulation
file, a script with a bug in it: none of that can reach the save Steam Cloud
carries to every machine you own, because the modded game never reads that
file. It plays on a _profile_, a save of the engine's own, kept in
`~/.local/share/ermod/profiles/`.

The first launch creates a profile called `default`, which is empty. Without
your characters in it, the first thing you would see is a game with no
characters. **The engine offers to copy them in before that happens.** On
the first launch it shows you the characters in your own save and asks
whether to copy them into the profile: a window if your desktop has one, a
question in the terminal if not. Answer either way and it does not ask
again.

If you said no, or you want a second profile to start from your characters,
the same thing has a command:

```sh
./ermod-engine profile port default
```

That reads your own save and writes a copy into the profile. Your file is
never modified. The engine says so after every port, and you can check with
`sha256sum` if you like.

You can also open that window whenever you like:

```sh
./ermod-engine settings
```

It lists your own save and every profile, with the characters in each, and
has buttons for the commands below, including backing your own save up.

The rest:

```sh
./ermod-engine profile list                # what you have, and which is active
./ermod-engine profile new no-scaling      # a second, separate save
./ermod-engine profile use no-scaling      # play on it from now on
./ermod-engine profile port no-scaling     # start it from your vanilla characters
./ermod-engine profile backup              # copy your own save aside, dated
./ermod-engine profile delete no-scaling   # and its save, permanently
```

A profile also records which mods you have switched off, so two profiles can
run different mods.

### Going the other way

If you want a character you built in a profile to become your real save:

```sh
./ermod-engine profile export no-scaling --yes    # game closed
```

This is the only command in the engine that writes your own save, it never
runs by itself, and it copies your existing save aside as
`ER0000.sl2.ermod-bak` first. It refuses rather than overwriting that
backup, because it may be your only copy.

## 6. Play

```sh
./ermod-engine
```

The game starts as normal, with mods loaded.

| Key                | What it does                                                                                                  |
| ------------------ | ------------------------------------------------------------------------------------------------------------- |
| `` ` `` (backtick) | Opens and closes the engine's menu: every mod with its state and cost, a switch per mod, profiles, and co-op. |
| `Insert`           | Gives mouse and keyboard to mod windows (an overlay, a settings panel), and hands them back to the game.      |

While the menu is open, or `Insert` has given mod windows focus, the mouse
belongs to them: the pointer moves freely and the camera stays still. The
game ignores the keyboard and mouse until you close the menu or press
`Insert` again. A gamepad keeps working. In the menu, `Tab` or the arrow keys
move between entries, and `Space` or `Enter` presses the highlighted one.

To play with friends, see the
[co-op guide](https://github.com/Benehiko/elden-ring-mods/blob/main/docs/coop.md).

### Settings: `engine.cfg`

The engine keeps its own settings in `~/.local/share/ermod/engine.cfg`.
`./ermod-engine settings` edits them in a window; you can also write the
file yourself. The game reads it as it starts, so a change takes effect on
the next launch.

```text
menu_key = "F10"
focus_key = "insert"
skip_title_cards = true
skip_boot_cinematics = false
skip_ingame_cinematics = false
frame_trace_cpu = "off"
```

| Setting                  | Default    | What it does                                                                                                                                                                            |
| ------------------------ | ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `menu_key`               | `"grave"`  | The key that opens and closes the engine's menu.                                                                                                                                        |
| `focus_key`              | `"insert"` | The key that gives mod windows the mouse and keyboard.                                                                                                                                  |
| `skip_title_cards`       | `true`     | Skips the publisher and engine logo screens at startup.                                                                                                                                 |
| `skip_boot_cinematics`   | `false`    | Skips the cinematics the game plays as it boots.                                                                                                                                        |
| `skip_ingame_cinematics` | `false`    | Skips cinematics that play during the game.                                                                                                                                             |
| `coop_join_approval`     | `"auto"`   | Who gets into your co-op session. `"auto"` lets in every player whose game-changing mods match yours; `"ask"` holds each one until you press **Allow** or **Refuse** in the ermod menu. |
| `frame_trace_cpu`        | `"off"`    | Starts a frame trace at launch that samples the game's code: `"light"`, `"normal"` or `"detailed"`. See [Finding stutters](performance.md).                                              |
| `frame_trace_gpu`        | `false`    | Starts a frame trace at launch that times the game's GPU work. See [Finding stutters](performance.md).                                                                                  |

One setting per line, as `name = value`. Setting names are lowercase,
exactly as above. A key or a level is a quoted name; a switch is `true` or
`false`.
Lines starting with `#` are comments.

A key name is one of:

- `grave` or `backtick` (the `` ` `` key)
- `insert`, `home`, `end`, `delete`, `pause`, `scrolllock`, `pageup`,
  `pagedown`, `tab`
- `backslash`, `minus`, `equals`, `leftbracket`, `rightbracket`,
  `semicolon`, `apostrophe`, `comma`, `period`, `slash`
- `F1` to `F24`
- a single letter or digit

Key names ignore case: `F10`, `f10`, `Insert` and `INSERT` all work. A key
name the engine does not know leaves that key at its default, and the log
says so. A line the engine cannot read at all stops the reading: that line
and every setting after it keep their defaults.

---

## When something does not work

**"My characters are gone."** They are not. The modded game deliberately
does not open your save. The first launch offers to copy them into the
profile; if you declined, or the offer never appeared, run
`./ermod-engine settings` and use the button beside your own save, or
`./ermod-engine profile port default`. See
[Profiles, and your own save](#5-profiles-and-your-own-save). Your own file
is untouched throughout, and playing through Steam normally still finds it.

**The logs** live inside the game's Wine prefix. `./ermod-engine paths`
prints where, along with every other path the engine uses. On Linux:

```text
~/.local/share/Steam/steamapps/compatdata/1245620/pfx/drive_c/windows/system32/ermod-launcher.log
~/.local/share/Steam/steamapps/compatdata/1245620/pfx/drive_c/windows/system32/ermod-runtime.log
```

On macOS they sit in the same place inside the bottle,
`<bottle>/drive_c/windows/system32/`. `ermod-launcher.log` covers starting
the game and injecting the runtime; `ermod-runtime.log` starts with the
engine version and records every decision the runtime made in the game.
Include both in a bug report, together with `./ermod-engine --version`.

**"not supported"** (a game build the engine does not know) means the game
has been patched and the engine does not yet have verified addresses for the
new version. The engine warns before launching and names the builds it
supports. The game still runs, just unmodded; nothing is broken and nothing
is at risk. By default the engine never guesses at addresses that may have
moved, because a wrong guess is what would corrupt a save. To see what the engine
finds in your game:

```sh
./ermod-engine check-build
```

It scans your `eldenring.exe` against every table the engine carries, says
whether one exists for your build, and prints a row per pattern. Check the
[Releases page](https://github.com/Benehiko/elden-ring-mods/releases) for a
newer engine.

If you want to run mods on that build anyway, at your own risk, launch with
`--ignore-build-guard` (engine releases after v0.2.0):

```sh
./ermod-engine --ignore-build-guard
```

The engine then treats your game as the newest build it has complete
addresses for, instead of running it unmodded. Those addresses were not
checked against your game, and after a patch some of them will have moved.
**Expect crashes, and wrong reads or writes to the characters in your modded
profile.** Your own save is still never opened. Both the launcher and
`ermod-runtime.log` say when the override is in effect. It applies to that
one launch only; leave the flag off to go back to the safe behaviour.

Every command that launches the game takes it, co-op included:
`./ermod-engine coop host --ignore-build-guard`, and the same for
`coop join`. See the [co-op guide](coop.md#wrong-game-build).

**"Easy Anti-Cheat is running"**, followed by a refusal to launch, means a
copy of the game (or its protected launcher) is still running. Close it,
including anything started through Steam's normal Play button, and try
again. There is no flag to override this.

**A warning that the runtime was built as a different version** means the
three files are not from the same release, usually an unpack of a new
archive over an old one. Unpack the new archive into an empty directory
instead.

**On macOS, "cannot be opened" or "Apple could not verify"** when you run
`ermod-engine`: Gatekeeper has refused a quarantined download. See
[On macOS: clear the quarantine](#on-macos-clear-the-quarantine).

**On macOS, a black screen and then the game closes**: turn off the Steam
overlay in the bottle's Steam (see [macOS](#macos)). **`SteamAPI_Init
returned false`** in a log means the bottle's Steam is not signed in; sign
it in and launch again.

## Removing it

```sh
./ermod-engine uninstall
```

That removes what the engine staged into the Wine prefix: the two binaries,
its logs, and the links to your mods, profiles and regulation. Add `--all`
to also clear `C:\ermod` in the prefix (per-mod settings and frame
captures).

**Neither touches your mods or your profile saves**, which live in
`~/.local/share/ermod/` and are only unlinked. To delete the saves as well,
and be told how many went:

```sh
./ermod-engine uninstall --profiles
```

Your own save is not involved in any of this, because the engine never wrote
it. The game install is never touched either, so nothing needs restoring; the
game launches normally through Steam afterwards.
