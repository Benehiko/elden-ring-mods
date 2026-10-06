-- Example: decide this player's share of co-op runes with `sdk.coop`.
--
-- In an engine co-op session every player gets the full runes of every
-- enemy any player kills, and of every boss, however far apart they stand.
-- That is the default and needs no mod. This mod changes it for the player
-- whose machine runs it: near a teammate, full runes; far from everyone, a
-- quarter of enemy runes and half of boss runes. The host can be treated
-- differently from a joiner with `coop.is_host()`.
--
-- The rates are this machine's own. Another player's runes are decided by
-- the mods on their machine, so a group that wants one rule for everyone
-- runs the same mod on every machine.
--
-- Try it: host or join a session, walk away from your teammate and read
-- the log, then let them kill something and compare the runes you each get.
-- `sdk.watch.stat.coop_distance` reports the same distance in whole metres,
-- as a watchable value.

local mod = {
  name = "coop-runes",
  version = "1.0.0",
  run_at = "events",
  permissions = { "coop", "hooks", "watch", "log" },
}

local NEAR = 100 -- metres
local FAR_ENEMY, FAR_BOSS = 0.25, 0.5

function mod.setup(sdk)
  local coop = sdk.coop
  local near = nil -- unknown until the first frame in a session

  sdk.hooks.on(sdk.hooks.event.on_present, function()
    if not coop.active() then return end
    local d = coop.get_distance()
    -- Nobody loaded nearby (another map, a load) counts as far.
    local now_near = d ~= nil and d <= NEAR
    if now_near == near then return end
    near = now_near
    if near then
      coop.set_rune_rates({ enemy = 1, boss = 1 })
    else
      coop.set_rune_rates({ enemy = FAR_ENEMY, boss = FAR_BOSS })
    end
    local r = coop.rune_rates()
    sdk.log.info(string.format("%s, %s: enemy runes x%.2f, boss runes x%.2f",
      coop.is_host() and "host" or "joiner",
      d and string.format("nearest player %.0f m", d) or "no player nearby",
      r.enemy, r.boss))
  end)

  sdk.watch.on(sdk.watch.stat.coop_distance, function(ch)
    if math.abs(ch.delta) >= 50 then
      sdk.log.info(string.format("nearest player now %d m away", ch.new))
    end
  end)
end

return mod
