-- Example: Torrent from a mod. `player` + `ui` + `hooks` + `log`.
--
-- A small window shows how the ride stands (`sdk.player.ride_state()`) and
-- Torrent's health (`sdk.player.steed_hp()`), with a button per action:
-- Mount, Dismount, Revive and Kill. Each calls the game directly; no key is
-- pressed. The player must hold the Spectral Steed Whistle to mount or
-- revive (a character made with `character new ... whistle=on` does), but it
-- need not sit in a quick slot.
--
-- When Torrent dies, the mod revives it three seconds later and puts the
-- player back on. Every change of the ride state is logged, so
-- `ermod-runtime.log` shows the game's own sequence: on_foot -> mounting ->
-- riding -> dismounting -> on_foot. In a co-op session every action returns
-- false, "in_session" for now; solo they work.

local mod = {
  name = "torrent",
  version = "1.0.0",
  run_at = "events",
  permissions = { "player", "ui", "hooks", "log" },
}

local revive_delay = 180

local player = nil
local log = nil
local last = nil
local said = ""
local dead_frames = 0
local remount = false

local function act(name)
  local ok, why = player[name]()
  said = name .. ": " .. (ok and "ok" or why)
  log.info(said)
  return ok
end

local function guard()
  local dead = player.steed_dead()
  if dead then
    dead_frames = dead_frames + 1
    if dead_frames == revive_delay and act("revive") then remount = true end
    return
  end
  dead_frames = 0
  if remount and dead == false and player.ride_state() == player.ride.on_foot then
    remount = false
    act("mount")
  end
end

function mod.setup(sdk)
  player = sdk.player
  log = sdk.log
  sdk.hooks.on(sdk.hooks.event.on_present, function()
    local ride = player.ride_state()
    if ride ~= last then
      log.info("ride: " .. tostring(ride))
      last = ride
    end
    if not player.in_world() then return end
    guard()

    sdk.ui.window("Torrent", function()
      sdk.ui.text("ride: " .. tostring(ride))
      local hp, max = player.steed_hp()
      if hp then
        sdk.ui.text(string.format("Torrent: %d/%d%s", hp, max, player.steed_dead() and " (dead)" or ""))
      else
        sdk.ui.text("Torrent: not loaded")
      end
      if sdk.ui.button("Mount") then act("mount") end
      sdk.ui.same_line()
      if sdk.ui.button("Dismount") then act("dismount") end
      sdk.ui.same_line()
      if sdk.ui.button("Revive") then act("revive") end
      sdk.ui.same_line()
      if sdk.ui.button("Kill") then act("kill_steed") end
      if said ~= "" then sdk.ui.text(said) end
    end, { x = 20, y = 300, once = true, flags = { "auto_size" } })
  end)
end

return mod
