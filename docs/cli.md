<!-- Generated from `ermod-engine --help` by `make cli-docs` in the engine repository. Do not edit by hand. -->

# Command reference

**ermod-engine** — launch Elden Ring under Proton (Linux) or in a Wine bottle (macOS) with the ermod runtime injected.

Every command here is in the release build, and `ermod-engine --help` prints the same text. A command marked "no launch" never starts the game.

**Usage:** [`ermod-engine`](#ermod-engine) [`paths`](#ermod-engine-paths) [`install`](#ermod-engine-install) [`coop id`](#ermod-engine-coop-id) [`coop host`](#ermod-engine-coop-host) [`coop join`](#ermod-engine-coop-join) [`coop leave`](#ermod-engine-coop-leave) [`profile`](#ermod-engine-profile) [`profile new|use|delete`](#ermod-engine-profile-newusedelete) [`profile backup`](#ermod-engine-profile-backup) [`profile port`](#ermod-engine-profile-port) [`profile export`](#ermod-engine-profile-export) [`character list`](#ermod-engine-character-list) [`character new`](#ermod-engine-character-new) [`character delete`](#ermod-engine-character-delete) [`completion bash|zsh|fish`](#ermod-engine-completion-bashzshfish) [`settings`](#ermod-engine-settings) [`shot`](#ermod-engine-shot) [`trace start`](#ermod-engine-trace-start) [`trace stop`](#ermod-engine-trace-stop) [`trace report`](#ermod-engine-trace-report) [`uninstall`](#ermod-engine-uninstall) [`check-build`](#ermod-engine-check-build) [`--version`](#ermod-engine---version) [`--help`](#ermod-engine---help)

**Writing a mod:** [`mod verify`](#ermod-engine-mod-verify) [`mod perf`](#ermod-engine-mod-perf) [`mod bake`](#ermod-engine-mod-bake)

## Usage

### `ermod-engine`

```text
ermod-engine [--dry-run] [--mods <dir>] [--regulation <file>|none]
```

Locate the game, stage the runtime, launch. Steam must be running — on macOS that means the Windows Steam inside the bottle, which is the client the game's own Steamworks talks to. Offline Mode is not required: the engine never starts the protected launcher. `--dry-run` reports without launching.

- `--mods <dir>` — link the prefix's mods directory at &lt;dir&gt;
- `--regulation <file>` — stage an `ermod-engine mod bake` output; the game reads it instead of its own regulation.bin
- `--regulation none` — clear a staged artifact
- `--muted` — launch with no sound (the runtime mutes the game's audio session in-process; the prefix and the game's own sound options are left alone)
- `--ignore-build-guard` — UNSAFE: run a game build with no verified address set as the newest one that has one, instead of vanilla. Expect crashes and wrong reads/writes in the modded profile; your own save is still never opened
- `--prefix <bottle>` — macOS: the Wine bottle holding the game, instead of searching CrossOver's and Whisky's bottle directories
- `--wine <path>` — macOS: the Wine binary to run it with, instead of searching. Together these two flags cover any Wine setup — Game Porting Toolkit, Homebrew, Heroic — without the engine knowing its layout. WINEPREFIX and WINE in the environment do the same.
- `--backend <name>` — macOS: auto, crossover, whisky or protium. auto (the default) uses protium when it is installed and has the game, else CrossOver. Naming one searches only that one. Also macos_backend = "&lt;name&gt;" in engine.cfg.
- `--no-gui` — never open a window; ask in the terminal
- `--port-vanilla` — on a first launch, copy your characters into the profile without asking
- `--no-port-vanilla` — on a first launch, never ask. Without either, you are asked once, in the terminal, and only if there is a choice to make.

### `ermod-engine paths`

```text
ermod-engine paths [--mods <dir>]
```

Print every path the engine uses — data directory, mods, profiles, the active profile's save, the prefix and the logs; no launch. `--mods` also shows the directory a launch with it would link.

### `ermod-engine install`

```text
ermod-engine install <mod.lua | dir/> [--force]
```

Copy a mod (or every .lua in a directory) into the mods directory.

### `ermod-engine coop id`

```text
ermod-engine coop id [--port N]
```

Print what a friend needs to play with you: this machine's Steam ID, its LAN address(es) and the UDP port (7777 unless `--port`), and the `coop join` line they type. No launch.

### `ermod-engine coop host`

```text
ermod-engine coop host [--port N] [--as ID] [<id>@<ip>[:port] ...] [<launch flags>]
```

Launch the game ready to host co-op. Press Continue at the title; once your world is loaded the command hosts the session and says so. Then your friends run `coop join`. You need not list them: the host learns each one when it joins.

### `ermod-engine coop join`

```text
ermod-engine coop join <host-id>@<ip>[:port] [<id>@<ip>[:port] ...] [--port N] [--as ID] [<launch flags>]
```

Launch the game and join a host. Press Continue at the title; once your world is loaded the command joins. The host must already be hosting: a joiner that comes first gets no session. With three or more players, also list each player who joined before you. For both: &lt;ip&gt; is an IPv4 address and a peer's port defaults to 7777. The machines must reach each other's UDP port directly — a LAN or a VPN; nothing crosses a NAT. Two machines on one Steam account: give one of them `--as` &lt;another Steam ID&gt; (any SteamID64 no one here uses), so the two are different players. Launch flags: `--mods`, `--regulation`, `--muted`, and on macOS `--prefix` and `--wine`. Every machine needs game build 2.7.0.0, and a joiner whose game-changing mods differ from the host's is held until it enables the host's mods in the ermod menu. The command ends when the game does.

### `ermod-engine coop leave`

```text
ermod-engine coop leave
```

Leave the co-op session the running game is in. Every other player's game drops you at once and you keep playing alone; the engine menu's "Leave co-op" does the same. Quitting the game leaves too. A player whose game crashes is dropped by the others after 45 seconds of silence.

### `ermod-engine profile`

```text
ermod-engine profile [list]
```

List profiles: the named saves the game plays on, and the characters in each. The active one is marked, and profiles copied from your own save say so. Your vanilla save is never played on or written.

### `ermod-engine profile new|use|delete`

```text
ermod-engine profile new|use|delete <name> [--force]
```

Create a profile, choose the one the game plays on, or delete one and its save. `--force` deletes the active profile.

### `ermod-engine profile backup`

```text
ermod-engine profile backup
```

Copy your own save aside, under today's date, into the engine's backups directory. Reads it; never writes it.

### `ermod-engine profile port`

```text
ermod-engine profile port <name> [--force]
```

Copy your vanilla save into a profile (reads it, never writes it).

### `ermod-engine profile export`

```text
ermod-engine profile export <name> --yes
```

Write a profile's save back over your vanilla save, with the game closed. The only command that writes it; the old one is kept.

### `ermod-engine character list`

```text
ermod-engine character list [--profile NAME | --save FILE]
```

The characters in a profile's save, slot by slot, with class and level. The active profile unless `--profile` names another.

### `ermod-engine character new`

```text
ermod-engine character new --class CLASS [--name NAME]
    [--keepsake KEEPSAKE] [--slot N] [--force] [--profile NAME |
    --save FILE] [--regulation FILE] [field=value ...]
```

Make a fresh character of a starting class without the game's character creation, and point the title menu's Continue at it. Takes the first empty slot unless `--slot` names one; a slot that holds a character is only replaced with `--force`. The class kit comes from the save's own regulation, or from `--regulation` (a mod bake output). field=value takes what dev save set takes, e.g. grace="The First Step" level=20 runes=10000. With the game closed. `character classes` lists the classes and keepsakes.

### `ermod-engine character delete`

```text
ermod-engine character delete --slot N [--profile NAME | --save FILE]
```

Empty a slot.

### `ermod-engine completion bash|zsh|fish`

```text
ermod-engine completion bash|zsh|fish
```

Print the shell completion script. Load it with, for bash, `source <(ermod-engine completion bash)` in ~/.bashrc; for zsh, the same with zsh in ~/.zshrc; for fish, `ermod-engine completion fish | source` in config.fish.

### `ermod-engine settings`

```text
ermod-engine settings
```

Open the settings window: engine switches, and the profiles your characters live in. Falls back to a message if there is no display (or if this build has no window in it); no launch.

### `ermod-engine shot`

```text
ermod-engine shot [--name N] [--scale S] [--out PATH] [--timeout MS]
```

Ask the running game for a frame capture; no launch.

### `ermod-engine trace start`

```text
ermod-engine trace start [--cpu LEVEL] [--gpu]
```

Start the running game's frame tracer: `--cpu` light|normal|detailed samples the game's threads (normal when nothing is given), `--gpu` times its GPU work (alone, GPU only); no launch.

### `ermod-engine trace stop`

```text
ermod-engine trace stop
```

Stop the frame tracer and close its file.

### `ermod-engine trace report`

```text
ermod-engine trace report [<file>]
```

What made the slow frames slow, from a trace (the newest in C:\ermod\trace by default).

### `ermod-engine uninstall`

```text
ermod-engine uninstall [--all] [--profiles]
```

Remove what the engine staged into the Wine prefix; no launch. `--all` also removes C:\ermod (mod store data and captures); your mods and profile saves live on the host and are only unlinked. `--profiles` deletes those saves too, and says how many.

### `ermod-engine check-build`

```text
ermod-engine check-build [<eldenring.exe>]
```

Does the engine know this game build? Scans the exe with every signature table and prints a row per pattern. The answer to "why does the launcher say this build is unsupported"; no launch.

### `ermod-engine --version`

```text
ermod-engine --version
```

Print the engine version (marked when it is a development build) and the game builds it supports; no launch.

### `ermod-engine --help`

```text
ermod-engine --help
```

## Writing a mod

### `ermod-engine mod verify`

```text
ermod-engine mod verify <mod.lua>...
```

Is each mod up to standard? Runs the game's own loader, sandbox, manifest rules and permission gating on this machine, with this process confined first (no files, no programs, no network), so a mod is never trusted while it is verified. A mod that would not load, or is not acceptable, is rejected with the reason. One line per mod; exit 1 if any is rejected.

### `ermod-engine mod perf`

```text
ermod-engine mod perf <mod.lua> [--frames N] [--runes N] [--deaths N]
                                [--regulation <regulation.bin>]
```

Fire a synthetic session and report cost per event against the real budget model, ending with the worst on_present frame as a percentage of a 60 fps frame. A pre-flight, not a promise: there is no game, so the overlay records instead of drawing. Without `--regulation`, `params` is unavailable exactly as it is before the game's tables load.

### `ermod-engine mod bake`

```text
ermod-engine mod bake <regulation.bin> <out.bin> <mod>...
```

Run launch mods offline and write a modded regulation.bin the engine loads in place of the game's own (`ermod-engine --regulation <out.bin>`). A mod is a built-in spec name (level60, class-gear) or a path to a .lua launch mod, and the two mix. Two mods writing one field is an error, not last-wins: bake names both and writes no file.
