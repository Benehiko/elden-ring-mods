# This repository builds nothing (E15). It publishes the surface a mod author
# writes against: the generated SDK stubs, the worked examples and the docs.
#
# Two things here are produced by the engine and committed, so an author needs
# neither a toolchain nor a checkout of the engine:
#
#   stubs/ermod.lua               `make stubs`      in elden-ring-mods-engine
#   docs/cli.md, docs/cli.html    `make cli-docs`   in elden-ring-mods-engine
#
# What is left here is checking that what is committed is what the engine
# would produce.

ENGINE ?= ../elden-ring-mods-engine

.PHONY: hooks check-stubs check-cli-docs

hooks:
	git config core.hooksPath .githooks
	chmod +x .githooks/pre-commit

# Fails if the committed stubs are not what the engine generates. The engine
# has the binding tables, so it is the authority; this only detects drift.
check-stubs:
	@test -x "$(ENGINE)/zig-out/bin/ermod-engine" || { \
		echo "check-stubs: build the engine first (make -C $(ENGINE) build)" >&2; exit 1; }
	@$(ENGINE)/zig-out/bin/ermod-engine dev stubs /tmp/ermod-stubs-check.lua >/dev/null
	@diff -u stubs/ermod.lua /tmp/ermod-stubs-check.lua && echo "check-stubs: stubs are current"

# Fails if the committed command reference is not what the engine generates
# from its --help. The engine's `zig build test` makes the same check from
# its side.
check-cli-docs:
	@test -f "$(ENGINE)/build.zig" || { \
		echo "check-cli-docs: no engine checkout at $(ENGINE)" >&2; exit 1; }
	@rm -rf /tmp/ermod-cli-check && mkdir -p /tmp/ermod-cli-check
	@cd "$(ENGINE)" && zig build cli-docs -- /tmp/ermod-cli-check 2>/dev/null
	@diff -u docs/cli.md /tmp/ermod-cli-check/cli.md && \
		diff -u docs/cli.html /tmp/ermod-cli-check/cli.html && \
		echo "check-cli-docs: the command reference is current"
