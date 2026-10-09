-- Example: Torrent from a mod. `player` + `ui` + `hooks` + `log`.
--
-- A small window shows how the ride stands (`sdk.player.ride_state()`) and
-- Torrent's health (`sdk.player.steed_hp()`), with buttons:
--
-- - Whistle calls Torrent the way the player does (the Spectral Steed
--   Whistle selected, use pressed); the character must hold the whistle.
-- - Mount calls Torrent through the game's own horse call, no whistle needed.
-- - Dismount gets off.
-- - Revive brings a dead Torrent back beside the player, without a flask.
-- - Kill kills Torrent; a rider falls off.
--
-- Every change of the ride state is logged, so `ermod-runtime.log` shows
-- the game's own sequence: on_foot -> mounting -> riding -> dismounting ->
-- on_foot. The game refuses to call Torrent on a grace. In a co-op session
-- every call returns false, "in_session" for now; solo they work.

local mod = {
  name = "whistle",
  version = "1.1.0",
  run_at = "events",
  permissions = { "player", "ui", "hooks", "log" },
}

local last = nil
local said = ""
local player = nil

local function act(name)
  local ok, why = player[name]()
  said = name .. ": " .. (ok and "ok" or why)
end

function mod.setup(sdk)
  player = sdk.player
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
      local hp, max = sdk.player.steed_hp()
      if hp then
        sdk.ui.text(string.format("Torrent: %d/%d%s", hp, max, sdk.player.steed_dead() and " (dead)" or ""))
      else
        sdk.ui.text("Torrent: not loaded")
      end
      if sdk.ui.button("Whistle") then act("whistle") end
      sdk.ui.same_line()
      if sdk.ui.button("Mount") then act("mount") end
      sdk.ui.same_line()
      if sdk.ui.button("Dismount") then act("dismount") end
      if sdk.ui.button("Revive") then act("revive") end
      sdk.ui.same_line()
      if sdk.ui.button("Kill") then act("kill_steed") end
      if said ~= "" then sdk.ui.text(said) end
    end, { x = 20, y = 300, once = true, flags = { "auto_size" } })
  end)
end

return mod
