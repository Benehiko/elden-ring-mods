-- Reference mod: every starting class begins at level 60.
--
-- The Lua port of the open repo's `level60` (mods/level60.zig): the same
-- intent, expressed through the `params` SDK module. Offline that module
-- will patch regulation.bin; in-game it edits the live CharaInitParam table,
-- and the character-creation screen shows level 60 for every class.
--
-- Elden Ring derives the displayed level from the stat total: the eight base
-- stats sum to `soulLv + 79`. Setting `soulLv` alone desynchronises the
-- character sheet from the rune cost curve, so each class gets an explicit
-- stat spread summing to 139 (= 60 + 79) that keeps its vanilla identity
-- (see the open repo's docs/classes.md).
--
-- Exercises: `params.row`, typed field read (the vanilla level is logged
-- before it changes) and field write, `run_at = "launch"`.

local mod = {
  name = "level60",
  version = "1.0.0",
  run_at = "launch",
  permissions = { "params", "log" },
}

local target_level = 60

-- row, name, vit, wil, end, str, dex, mag, fai, luc — each sums to 139.
local classes = {
  { 3000, "Vagabond",   30, 13, 22, 29, 20,  9,  9,  7 },
  { 3001, "Warrior",    23, 16, 23, 14, 36, 10,  8,  9 },
  { 3002, "Hero",       30,  9, 24, 37, 13,  7,  8, 11 },
  { 3003, "Bandit",     23, 15, 19, 13, 30,  9,  8, 22 },
  { 3004, "Astrologer", 20, 26, 16,  8, 15, 38,  7,  9 },
  { 3005, "Prophet",    21, 24, 15, 14, 10,  7, 38, 10 },
  { 3006, "Confessor",  21, 20, 16, 18, 18,  9, 28,  9 },
  { 3007, "Samurai",    24, 14, 25, 20, 31,  9,  8,  8 },
  { 3008, "Prisoner",   22, 18, 17, 14, 25, 28,  6,  9 },
  { 3009, "Wretch",     22, 18, 18, 18, 18, 18, 14, 13 },
}

local fields = { "baseVit", "baseWil", "baseEnd", "baseStr", "baseDex", "baseMag", "baseFai", "baseLuc" }

function mod.on_launch(sdk)
  local done = 0
  for _, class in ipairs(classes) do
    local row = sdk.params.row("CharaInitParam", class[1])
    if row == nil then
      sdk.log.warn(string.format("CharaInitParam row %d (%s) missing", class[1], class[2]))
    else
      local before = row.soulLv
      row.soulLv = target_level
      for i, field in ipairs(fields) do
        row[field] = class[i + 2]
      end
      sdk.log.info(string.format("%s: level %d -> %d", class[2], before, row.soulLv))
      done = done + 1
    end
  end
  sdk.log.info(string.format("level60 applied to %d/%d classes", done, #classes))
end

return mod
