-- Example: a boss fight in stages — the same fight, reset and harder.
--
-- `sdk.bosses.stats(id)` is the boss's NpcParam row: its base HP, the damage
-- it takes from each type (`damage_taken`: below 1 it resists, above 1 it is
-- weak), its status resistances and its resident SpEffects (buffs). Any field
-- can be read with `bosses.stat` and written live with `bosses.set_stat`, at
-- any time — not only at load — and `bosses.reset_stats` puts the row back.
--
-- `bosses.set_immortal(id, true)` holds a body at 1 HP instead of letting it
-- die, and `bosses.set_hp` refills it: together they make stages. Here
-- Margit has three: each time he is brought to 1 HP he is healed to full and
-- takes 20% less damage of every type; in the last stage he can die. When
-- the fight is over his stats are restored.
--
-- Try: change `boss`, `stages` or `harder`; read `stats` before and after.

local mod = {
  name = "boss-phases",
  version = "1.0.0",
  run_at = "events",
  permissions = { "bosses", "hooks", "log" },
}

local boss -- set in setup: sdk.bosses.id.margit_the_fell_omen (10000850)
local stages = 3
local harder = 0.8 -- damage taken multiplier per stage

local stage = 0
local frames = 0
local cuts = { "neutral", "slash", "blow", "thrust", "magic", "fire", "thunder", "dark" }
local fields = {
  neutral = "neutralDamageCutRate", slash = "slashDamageCutRate", blow = "blowDamageCutRate",
  thrust = "thrustDamageCutRate", magic = "magicDamageCutRate", fire = "fireDamageCutRate",
  thunder = "thunderDamageCutRate", dark = "darkDamageCutRate",
}

local function next_stage(sdk, s)
  stage = stage + 1
  local base = sdk.bosses.stats(boss, { default = true })
  for _, k in ipairs(cuts) do
    sdk.bosses.set_stat(boss, fields[k], base.damage_taken[k] * harder ^ (stage - 1))
  end
  sdk.bosses.set_hp(boss, s.hp_max)
  sdk.bosses.set_immortal(boss, stage < stages)
  sdk.log.info(string.format("stage %d of %d: healed to %d, damage taken x%.2f", stage, stages, s.hp_max, harder ^ (stage - 1)))
end

function mod.setup(sdk)
  boss = sdk.bosses.id.margit_the_fell_omen
  sdk.hooks.on(sdk.hooks.event.on_present, function()
    frames = frames + 1
    if frames % 15 ~= 0 then return end
    local s = sdk.bosses.state(boss)
    if not s then return end
    if stage == 0 and sdk.bosses.in_fight() and s.alive then
      next_stage(sdk, s)
    elseif stage > 0 and stage < stages and s.hp <= 1 then
      next_stage(sdk, s)
    elseif stage > 0 and not s.alive then
      sdk.bosses.reset_stats(boss)
      sdk.log.info("defeated in stage " .. stage .. "; stats restored")
      stage = 0
    end
  end)
end

return mod
