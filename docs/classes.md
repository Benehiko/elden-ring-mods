# Starting classes

`CharaInitParam` rows **3000–3009** are the ten playable starting classes. Values
below were read out of the shipped `regulation.bin` with `ermod show`, not copied
from a wiki.

## Level formula

The eight base stats always sum to `soulLv + 79`. Every vanilla row satisfies this,
including the Wretch (all stats 10, sum 80, level 1). Setting `soulLv` without
adjusting the stats to match desynchronises the character sheet from the rune cost
curve, so any level mod must change both.

## Vanilla stats

| Row | Class | Lv | Vig | Mind | End | Str | Dex | Int | Fai | Arc |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 3000 | Vagabond | 9 | 15 | 10 | 11 | 14 | 13 | 9 | 9 | 7 |
| 3001 | Warrior | 8 | 11 | 12 | 11 | 10 | 16 | 10 | 8 | 9 |
| 3002 | Hero | 7 | 14 | 9 | 12 | 16 | 9 | 7 | 8 | 11 |
| 3003 | Bandit | 5 | 10 | 11 | 10 | 9 | 13 | 9 | 8 | 14 |
| 3004 | Astrologer | 6 | 9 | 15 | 9 | 8 | 12 | 16 | 7 | 9 |
| 3005 | Prophet | 7 | 10 | 14 | 8 | 11 | 10 | 7 | 16 | 10 |
| 3006 | Confessor | 10 | 10 | 13 | 10 | 12 | 12 | 9 | 14 | 9 |
| 3007 | Samurai | 9 | 12 | 11 | 13 | 12 | 15 | 9 | 8 | 8 |
| 3008 | Prisoner | 9 | 11 | 12 | 11 | 11 | 14 | 14 | 6 | 9 |
| 3009 | Wretch | 1 | 10 | 10 | 10 | 10 | 10 | 10 | 10 | 10 |

Note the paramdef field names use the older Dark Souls vocabulary: `baseVit` is
Vigor, `baseWil` is Mind, `baseMag` is Intelligence, `baseLuc` is Arcane.

## Vanilla equipment

| Row | Class | Right | Left | Armour set |
| --- | --- | --- | --- | --- |
| 3000 | Vagabond | 2000000 | 31330000 | 6600xx |
| 3001 | Warrior | 7140000 | 7140000 | 6700xx |
| 3002 | Hero | 14000000 | 31230000 | 7300xx |
| 3003 | Bandit | 1090000 | 30000000 | mixed |
| 3004 | Astrologer | 33130000 | 30080000 | 6300xx |
| 3005 | Prophet | 16000000 | 34000000 | 6200xx, no gauntlets |
| 3006 | Confessor | 2020000 | 31300000 | 8800xx |
| 3007 | Samurai | 9000000 | 41000000 | 8700xx |
| 3008 | Prisoner | 5000000 | 33000000 | 8900xx, no gauntlets |
| 3009 | Wretch | 11010000 | none | none |

## Equipment ID conventions

Weapon IDs are `base * 10000 + upgrade level`, but **only the base rows exist** in
`EquipParamWeapon`; reinforcement is applied at runtime through
`ReinforceParamWeapon`. Writing an upgraded ID such as `2000006` references a row
that is not in the table and the weapon fails to equip. Mods must use base IDs.

`ermod verify-ids` checks every ID referenced by the mods against the game's own
`EquipParamWeapon`, `EquipParamProtector` and `EquipParamGoods` tables.
