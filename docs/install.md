# Installing the engine

This is the page for playing with mods, not for building anything. You need a
Steam copy of Elden Ring on Linux, Proton, and the engine archive. No
toolchain, no checkout, no ModEngine.

The engine is `ermod-engine`: it starts the game under Proton without Easy
Anti-Cheat and loads mods into it. It never writes to the game install.

---

## Before you start

**Put Steam in Offline Mode.** Steam → menu → *Go Offline*.

Modded play means playing with anti-cheat disabled, and FromSoftware bans
accounts that connect to their servers with a modified game.

The engine never starts anti-cheat: it launches `eldenring.exe` directly and
never `start_protected_game.exe`, refuses to run at all while Easy Anti-Cheat
is live, and re-checks from inside the game before enabling anything — no
bypass flag, in either place. What that does *not* cover is you (or Steam)
launching the game the normal way afterwards, with mods still installed.
Offline Mode is what closes that door, which is why it goes first.

You also need:

- **The game installed and launched normally at least once.** The first
  launch is what creates the Proton prefix the engine stages into.
- **Proton installed for Elden Ring** (Proton Experimental is the usual
  choice). The engine uses whichever Proton Steam is configured to use for
  the game — it reads Steam's own setting rather than guessing.

## 1. Unpack

Unpack the archive anywhere you like — your home directory is fine. It has
no installer and writes nothing outside the game's Proton prefix.

```sh
tar -xzf ermod-engine-v0.1.0-linux-x86_64.tar.gz
cd ermod-engine-v0.1.0-linux-x86_64
```

Keep the three binaries together. `ermod-engine` is the one you run; it finds
`ermod-launcher.exe` and `ermod-runtime.dll` beside itself. If you verified
the download, `sha256sum -c SHA256SUMS` in the directory you downloaded to
checks it against the release's published sums.

## 2. Check that it finds your game

```sh
./ermod-engine --dry-run
```

This resolves everything and stops before starting anything. A good run names
your install, your Proton and the command it would run:

```
info: ermod-engine v0.1.0
info: found Elden Ring: /home/you/.local/share/Steam/steamapps/common/ELDEN RING/Game
info: game build 22984413
info: using Proton: Proton - Experimental
info: launching eldenring.exe (never start_protected_game.exe)
info: dry run: not launching
```

If it cannot find something, this is the output to keep — it says which check
failed. Two common cases:

- **`no Proton build found`** — Elden Ring has never been launched through
  Proton on this machine, or Proton is not installed. Launch the game
  normally once, then try again.
- **A warning that your game build is not supported** (see below).

Run `./ermod-engine --version` at any time to see the engine version and the
game builds it knows.

## 3. Get a mod

Mods are Lua files. The example mods live in this repository under
[`examples/`](../examples/) — `level60.lua` (start at level 60),
`death_ping.lua` (log every death), `perf_monitor.lua` and `overlay.lua`
(in-game overlays). Download the ones you want, or clone the repo:

```sh
git clone https://github.com/Benehiko/elden-ring-mods.git
```

### Where mods go

```sh
./ermod-engine install ~/Downloads/level60.lua      # one mod
./ermod-engine install ~/Downloads/elden-ring-mods/examples   # or a directory of them
```

That is the whole of it. `install` copies `.lua` files into the engine's mods
directory, and they load on the next launch — or immediately, if the game is
already running.

If you would rather copy files yourself, the directory is:

```
~/.local/share/ermod/mods
```

`ermod-engine paths` prints that and every other path the engine uses. The
game, running under Wine, sees the same directory as `C:\ermod\mods` —
which is what the log calls it — because the engine links the prefix at your
home directory. That is deliberate: Proton rebuilds a prefix now and then
(a Proton version change, a "verify integrity of game files"), and anything
kept inside one eventually disappears. Your mods and your profile saves live
outside it.

One directory, one `.lua` file per mod, no subdirectories, no manifest to
register them in.

**Or keep your mods anywhere you like** and point the engine at them:

```sh
./ermod-engine --mods ~/ermod-mods
```

That links the prefix directory at yours and launches the game. The link
persists, so later launches are just `./ermod-engine`. This is the better
arrangement if you edit mods: the files you edit are the files the game
loads, and editing one while the game runs reloads it within a second — no
relaunch.

Writing your own is documented in [scripting.md](scripting.md).

## 4. Or load a modded regulation

Some mods are not scripts but a modified `regulation.bin`, built offline by
`ermod-engine dev apply` (see [deploy.md](deploy.md)). The engine loads one directly:

```sh
./ermod-engine --regulation ~/mods/regulation.bin
```

The game reads that file instead of its own. **Your game's own
`regulation.bin` is never overwritten** — which matters, because Steam's
integrity check silently reverts a game file you replace by hand, usually at
the worst moment. `--regulation none` clears it again.

Script mods and a modded regulation can both be active at once.

## 5. Profiles, and your own save

**The modded game never plays on your own save, and never writes it.**

This is not a setting. A mod that grants a hundred levels, a bad regulation
artifact, a script with a bug in it — none of that can reach the save Steam
Cloud carries to every machine you own, because the modded game is not
reading that file at all. It plays on a *profile*: a save of the engine's
own, kept in `~/.local/share/ermod/profiles/`.

The first launch creates a profile called `default`, which is empty — so
without your characters in it, the first thing you would see is a game with
no characters. **The engine offers to copy them in before that happens.** On
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
never modified — the engine says so after every port, and you can check with
`sha256sum` if you like.

You can also open that window whenever you like:

```sh
./ermod-engine settings
```

It lists your own save and every profile, with the characters in each, and
has buttons for the things below — including backing your own save up.

The rest:

```sh
./ermod-engine profile list                # what you have, and which is active
./ermod-engine profile new no-scaling      # a second, separate save
./ermod-engine profile use no-scaling      # play on it from now on
./ermod-engine profile port no-scaling     # start it from your vanilla characters
./ermod-engine profile backup              # copy your own save aside, dated
./ermod-engine profile delete no-scaling   # and its save, permanently
```

A profile is also where the engine remembers which mods you have switched
off, so two profiles can run different mods.

### Going the other way

If you want a character you built in a profile to become your real save:

```sh
./ermod-engine profile export no-scaling --yes    # game closed
```

This is the only command in the engine that writes your own save, it never
runs by itself, and it copies your existing save aside as
`ER0000.sl2.ermod-bak` first — and refuses rather than overwriting that
backup, because it may be your only copy.

## 6. Play

```sh
./ermod-engine
```

The game starts as normal, with mods loaded.

In-game, **backtick** (`` ` ``) opens the engine's menu: which mods are
loaded, what each one costs per frame, and a checkbox to turn any of them off
or back on without restarting. `Insert` separately toggles whether a *mod's*
own overlay takes keyboard focus.

Both keys can be changed. Write `~/.local/share/ermod/engine.cfg`:

```
menu_key = "F10"
focus_key = "insert"
```

Names are `grave` (backtick), `insert`, `home`, `end`, `delete`, `pause`,
`pageup`, `pagedown`, `tab`, the bracket/punctuation keys, `F1`–`F24`, or a
single letter or digit.

---

## When something does not work

**"My characters are gone."** They are not — the modded game deliberately
does not open your save. The first launch offers to copy them into the
profile; if you declined, or the offer never appeared, run
`./ermod-engine settings` and use the button beside your own save, or
`./ermod-engine profile port default`. See [Profiles, and your own
save](#5-profiles-and-your-own-save). Your own file is untouched throughout,
and playing through Steam normally still finds it.

**The log is inside the Proton prefix:**

```
~/.local/share/Steam/steamapps/compatdata/1245620/pfx/drive_c/windows/system32/ermod-runtime.log
```

It starts with the engine version and records every decision the runtime
made — which is usually enough to say what happened. Include it in a bug
report, together with `./ermod-engine --version`.

**"unsupported build"** means the game has been patched and the engine does
not yet have verified addresses for the new version. The engine tells you
before launching and names the builds it does support. The game still runs,
just unmodded; nothing is broken and nothing is at risk. Check the releases
page for a newer engine. The engine never guesses at addresses that may have
moved — that is what would corrupt a save.

**"Easy Anti-Cheat is running — refusing to launch"** means a copy of the
game (or its protected launcher) is still running. Close it, including
anything started through Steam's normal Play button, and try again. There is
no flag to override this.

**A warning that the runtime was built as a different version** means the
three files are not from the same release — usually an unpack of a new
archive over an old one. Unpack the new archive into an empty directory
instead.

## Removing it

```sh
./ermod-engine uninstall
```

That removes what the engine staged into the Proton prefix — the two
binaries, its logs, and the links to your mods, profiles and regulation.
Add `--all` to also clear `C:\ermod` in the prefix (per-mod settings and
frame captures).

**Neither touches your mods or your profile saves**, which live in
`~/.local/share/ermod/` and are only unlinked. To delete the saves as well,
and be told how many went:

```sh
./ermod-engine uninstall --profiles
```

Your own save is not involved in any of this — the engine never wrote it.
The game install is never touched either, so nothing needs restoring; the
game launches normally through Steam afterwards.
