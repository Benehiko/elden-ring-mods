-- Example: watch the bosses around the player.
--
-- `sdk.bosses.state(id)` is a loaded boss's live HP and position (nil when
-- it is not loaded), `sdk.bosses.player_pos()` is where the player is, and
-- `sdk.bosses.in_fight()` is true from the moment the player passes a boss's
-- fog until the boss dies. The engine refreshes them every 30 frames.
--
-- Positions are in the frame the player's own position is in near the boss,
-- so a distance between the two is meaningful when they are close (the same
-- arena), not across the world. Some bosses wait outside their arena and only
-- come in with the player, so a boss entry carries both: `boss.idle_pos` is
-- where it waits, `boss.arena` where a recorded fight began (inside the fog)
-- and `boss.fight_pos`/`fight_radius` where it fought. `sdk.bosses.fight_entry()`
-- is the current fight's arena. `boss.marker` is the game's own marker, in
-- another frame.
--
-- This is the shape a mod that reacts to a fight takes: here it only logs,
-- once a second, each living boss within 80 m and whether a fight is on.
--
-- Try: walk up to a boss arena, then through the fog, and read the log.

local mod = {
  name = "boss-watch",
  version = "1.0.0",
  run_at = "events",
  permissions = { "bosses", "hooks", "log" },
}

local frames = 0

local function distance(a, b)
  local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function mod.setup(sdk)
  sdk.hooks.on(sdk.hooks.event.on_present, function()
    frames = frames + 1
    if frames % 60 ~= 0 then return end
    local me = sdk.bosses.player_pos()
    if not me then return end
    for _, boss in ipairs(sdk.bosses.all) do
      -- An encounter can be several bodies (a duo, a second phase, Fia's
      -- Champions' waves): `s.bodies` lists every loaded one, and `s.alive`
      -- is true while any of them lives.
      local s = sdk.bosses.state(boss.id)
      if s and s.alive then
        for _, body in ipairs(s.bodies) do
          local d = distance(me, body.pos)
          if body.hp > 0 and d < 80 then
            sdk.log.info(string.format("%s (%d) body %d: %d/%d HP, %.0f m away, %d of %d alive, fight %s",
              boss.display_name ~= "" and boss.display_name or boss.key, boss.id, body.entity, body.hp, body.hp_max, d,
              s.bodies_alive, #s.bodies, sdk.bosses.in_fight() and "ON" or "off"))
          end
        end
      end
    end
  end)
end

return mod
