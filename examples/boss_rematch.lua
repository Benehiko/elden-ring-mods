-- Example: fight bosses again, harder.
--
-- `sdk.bosses` lists every boss the game pays a clear for, base game and
-- Shadow of the Erdtree, and revives any of them by clearing its defeat
-- flag. A revived boss is back the next time its map loads: rest at a
-- grace, warp, or die. Its one-off drop does not come back; its runes do.
--
-- A revive asked for here waits until a world is loaded, then lands. It
-- needs the "bosses" permission. Pair it with `sdk.params` to make the
-- rematch harder (see level60.lua for how a param write looks).
--
-- Try: change the list below, or call sdk.bosses.revive_all({ dlc = false })
-- to bring back every base-game boss at once. See docs/boss-revive.md.

local mod = {
  name = "boss_rematch",
  version = "1.0.0",
  run_at = "launch",
  permissions = { "bosses", "log" },
}

-- Margit, the Fell Omen, and Godrick the Grafted. Bosses are named by
-- `sdk.bosses.id.<name>`, or by their row id / defeat flag.
local rematch

function mod.on_launch(sdk)
  rematch = { sdk.bosses.id.margit_the_fell_omen, sdk.bosses.id.godrick_the_grafted }
  for _, id in ipairs(rematch) do
    local boss = sdk.bosses.find(id)
    local queued = sdk.bosses.revive(id)
    sdk.log.info(string.format("boss %d in %s: revive %s", boss.flag, boss.map,
      queued and "queued" or "unavailable"))
  end

  local dlc = 0
  for _, boss in ipairs(sdk.bosses.all) do
    if boss.dlc then dlc = dlc + 1 end
  end
  sdk.log.info(string.format("%d bosses known, %d of them in the DLC", #sdk.bosses.all, dlc))
end

return mod
