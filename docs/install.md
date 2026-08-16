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

The engine reads mods from one directory inside the game's Proton prefix,
which it creates for you on the first launch:

```
~/.local/share/Steam/steamapps/compatdata/1245620/pfx/drive_c/ermod/mods
```

(That is the Linux path. The game, running under Wine, sees the same
directory as `C:\ermod\mods` — which is what the log calls it.)

Copy `.lua` files straight in there and they load on the next launch. Nothing
else is read: one directory, one `.lua` file per mod, no subdirectories, no
manifest to register them in.

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
`ermod apply` (see [deploy.md](deploy.md)). The engine loads one directly:

```sh
./ermod-engine --regulation ~/mods/regulation.bin
```

The game reads that file instead of its own. **Your game's own
`regulation.bin` is never overwritten** — which matters, because Steam's
integrity check silently reverts a game file you replace by hand, usually at
the worst moment. `--regulation none` clears it again.

Script mods and a modded regulation can both be active at once.

## 5. Play

```sh
./ermod-engine
```

The game starts as normal, with mods loaded. In-game, `Insert` toggles
whether the overlay takes keyboard focus (only relevant if you run a mod that
draws one).

---

## When something does not work

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
binaries, its logs, and the links to your mods and regulation — and leaves
your mods, your saved settings and your captures where they are. Add `--all`
to remove those too. The game install is never touched, so nothing needs
restoring; the game launches normally through Steam afterwards.
