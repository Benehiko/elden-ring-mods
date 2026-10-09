-- Example: Torrent from a mod. `player` + `ui` + `hooks` + `log`.
--
-- A small window shows how the ride stands (`sdk.player.ride_state()`) and
-- has two buttons: Whistle calls Torrent the way the player does (the
-- Spectral Steed Whistle selected, use pressed), and Dismount gets off.
-- Every change of the ride state is logged, so `ermod-runtime.log` shows
-- the game's own sequence: on_foot -> mounting -> riding -> dismounting ->
-- on_foot.
--
-- The character must hold the whistle (a character made with
-- `character new ... whistle=on` does) and must not stand on a grace, where
-- the game refuses to call Torrent. In a co-op session both calls return
-- false, "in_session" for now; solo they work.

local mod = {
  name = "whistle",
  version = "1.0.0",
  run_at = "events",
  permissions = { "player", "ui", "hooks", "log" },
}

local last = nil
local said = ""

function mod.setup(sdk)
  sdk.hooks.on(sdk.hooks.event.on_present, function()
    local ride = sdk.player.ride_state()
    if ride ~= last then
      sdk.log.info("ride: " .. tostring(ride))
      last = ride
    end

    sdk.ui.window("Torrent", function()
      if not sdk.player.in_world() then
        sdk.ui.text("not in a world")
        return
      end
      sdk.ui.text("ride: " .. tostring(ride))
      if sdk.ui.button("Whistle") then
        local ok, why = sdk.player.whistle()
        said = "whistle: " .. (ok and "pressed" or why)
      end
      sdk.ui.same_line()
      if sdk.ui.button("Dismount") then
        local ok, why = sdk.player.dismount()
        said = "dismount: " .. (ok and "pressed" or why)
      end
      if said ~= "" then sdk.ui.text(said) end
    end, { x = 20, y = 300, once = true, flags = { "auto_size" } })
  end)
end

return mod
