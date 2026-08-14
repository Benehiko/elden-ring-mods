GAME ?= $(HOME)/.local/share/Steam/steamapps/common/ELDEN RING/Game
MODS ?= level60 class-gear

.PHONY: hooks build test selftest apply paramdefs clean

hooks:
	git config core.hooksPath .githooks
	chmod +x .githooks/pre-commit

build:
	zig build

test:
	zig build test

# Golden checks against the real install (needs the game; not run in CI).
selftest: build
	./zig-out/bin/ermod selftest "$(GAME)/regulation.bin"
	./zig-out/bin/ermod verify-ids "$(GAME)/regulation.bin"

# Produce mod/regulation.bin for Mod Engine 2. Never writes to the game dir.
apply: build
	mkdir -p mod
	./zig-out/bin/ermod apply "$(GAME)/regulation.bin" mod/regulation.bin $(MODS)

# Regenerate the Zig field tables from the vendored Paramdex XML.
paramdefs:
	python3 tools/gen_paramdef.py paramdefs src/generated/paramdefs.zig \
		CharaInitParam ItemLotParam EquipParamWeapon EquipParamProtector EquipParamGoods
	zig fmt src/generated/paramdefs.zig

clean:
	rm -rf .zig-cache zig-out build_out
