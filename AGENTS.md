# Working rules for this repository

This is the **open** half of ermod. It publishes the surface a mod author
writes against and nothing else. The engine (launcher, runtime, Lua sandbox,
SDK bindings, param pipeline, and every tool its maintainers run) is the
closed repository `elden-ring-mods-engine`.

## What belongs here

| Path                           | What it is                                                | Where it comes from                                                                                                                    |
| ------------------------------ | --------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `stubs/ermod.lua`              | LuaLS annotations for every `sdk.*` binding               | generated: `make -C ../elden-ring-mods-engine stubs`. Never edit by hand.                                                              |
| `docs/cli.md`, `docs/cli.html` | the command reference, for the repository and the website | generated from the engine's `--help`: `make -C ../elden-ring-mods-engine cli-docs`. Never edit by hand; change the help in the engine. |
| `examples/*.lua`               | worked mods                                               | must stay byte-identical to the engine's `examples/` (`zig build test-examples` there)                                                 |
| `docs/`, `README.md`           | the author- and player-facing docs                        | written here                                                                                                                           |
| `LICENSE`, `NOTICE`            | Apache-2.0 and what it does not cover                     | written here                                                                                                                           |

## What does not belong here

- **No tooling. Do not add `tools/`, scripts or generators.** If only the
  engine's maintainers run it, it belongs in the engine. `tools/gen_paramdef.py`
  and the Paramdex XML sat here for weeks for that reason. They now live in
  the engine as `tools/paramdef_gen.zig` and `data/paramdefs/`.
- **No Python, ever.** The project is Zig. CI (`no-tooling`) and the
  pre-commit hook both reject any `.py` file.
- **Nothing that builds.** There is no `build.zig` and there should not be one.
- **No game data.** No `regulation.bin`, no param rows, nothing extracted from
  an installation (see `NOTICE`).
- **No engine internals.** Addresses, signatures, hook details and E-series
  scoping docs are the engine's. Docs here say what a player or a mod author
  sees, not how the engine does it.

## Checks

- `make check-stubs`: the committed stubs are what the engine generates.
- `make check-cli-docs`: the committed command reference is what the engine
  generates from its `--help`.
- `make fmt` / `make check-fmt`: format or check every Markdown file with
  Prettier (needs Node; config in `.prettierrc.json`, generated
  `docs/cli.md` excluded).
- CI: every example parses, Markdown is formatted, and no Python or `tools/`
  exists.
- `make hooks` once per clone, to install the pre-commit hook.

## Commits

Conventional prefixes (`feat:`, `fix:`, `docs:`, ...). Code and docs for one
change go in one commit.
