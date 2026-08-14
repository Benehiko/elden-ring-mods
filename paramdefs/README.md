# Vendored paramdefs

PARAMDEF XML files from [soulsmods/Paramdex](https://github.com/soulsmods/Paramdex)
(`ER/Defs/`), fetched from `master` on 2026-08-14.

These describe the field layout of param rows, which is not stored in the game
files themselves. `tools/gen_paramdef.py` turns them into the Zig field tables in
`src/generated/paramdefs.zig`; run `make paramdefs` after changing anything here.

Only the params we actually read or edit are vendored:

| File | Param type | Row size |
| --- | --- | --- |
| `CharaInitParam.xml` | `CHARACTER_INIT_PARAM` | 320 |
| `ItemLotParam.xml` | `ITEMLOT_PARAM_ST` | 152 |
| `EquipParamWeapon.xml` | `EQUIP_PARAM_WEAPON_ST` | 664 |
| `EquipParamProtector.xml` | `EQUIP_PARAM_PROTECTOR_ST` | 416 |
| `EquipParamGoods.xml` | `EQUIP_PARAM_GOODS_ST` | 176 |

The computed row sizes are checked against the shipped game data at runtime
(`ermod selftest`), so a paramdef that drifts from the installed game version is
caught rather than silently corrupting rows.
