# This repository builds nothing (E15). It publishes the surface a mod author
# writes against: the generated SDK stubs, the worked examples, and the
# Paramdex PARAMDEF XML the engine's field tables come from.
#
# Both generated artefacts are produced by the engine and committed here, so
# an author needs neither a toolchain nor a checkout of the engine:
#
#   stubs/ermod.lua        `make stubs`     in elden-ring-mods-engine
#   the engine's paramdefs `make paramdefs` in elden-ring-mods-engine
#
# What is left here is checking that what is committed is what the engine
# would produce.

ENGINE ?= ../elden-ring-mods-engine

.PHONY: hooks check-stubs

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
