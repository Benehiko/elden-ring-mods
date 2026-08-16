-- Example: a HUD driven by game events — `ui` + `hooks`.
--
-- Shows runes gained and deaths this session, plus a notice that fades out
-- over the following frames. Nothing here touches the game: it only listens
-- and draws, which makes it a safe first UI mod to modify.
--
-- The window is borderless, input-transparent and positioned once
-- (`no_inputs`, `once`), so it behaves like part of the game's HUD rather
-- than a tool window.

local mod = {
  name = "hud-overlay",
  version = "1.0.0",
  run_at = "events",
  permissions = { "ui", "hooks" },
}

local runes_session = 0
local deaths_session = 0
local last_gain = 0
local notice, notice_frames = nil, 0

function mod.setup(sdk)
  sdk.hooks.on("on_rune_gain", function(ev)
    runes_session = runes_session + ev.amount
    last_gain = ev.amount
    notice, notice_frames = string.format("+%d runes", ev.amount), 180
  end)

  sdk.hooks.on("on_death", function()
    deaths_session = deaths_session + 1
    notice, notice_frames = "YOU DIED", 240
  end)

  sdk.hooks.on("on_present", function()
    sdk.ui.window("##hud", function()
      sdk.ui.text(string.format("Runes this session: %d", runes_session))
      sdk.ui.text(string.format("Deaths this session: %d", deaths_session))
      if last_gain > 0 then
        sdk.ui.text(string.format("Last pickup: +%d", last_gain), { 0.9, 0.8, 0.3 })
      end
      if notice_frames > 0 then
        notice_frames = notice_frames - 1
        local a = math.min(1, notice_frames / 60)
        sdk.ui.text(notice, { 1, 0.3, 0.3, a })
      end
    end, { x = 20, y = 520, once = true, flags = { "no_title", "auto_size", "no_inputs" } })
  end)
end

return mod
