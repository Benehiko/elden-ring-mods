-- Example: a HUD driven by game events. `ui` + `hooks`.
--
-- Shows runes gained and deaths this session, the character's lifetime
-- death count, plus a notice that fades out over the following frames.
-- Nothing here touches the game: it only listens and draws, which makes it a
-- safe first UI mod to modify.
--
-- The lifetime count is the game's own counter, saved with the character:
-- `on_death` carries it as `ev.deaths` (this death included), and
-- `sdk.watch.get(sdk.watch.stat.deaths)` reads it at any time with the
-- "watch" permission. Until the first death here it shows as "?".
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
local deaths_total = nil
local last_gain = 0
local notice, notice_frames = nil, 0

function mod.setup(sdk)
  sdk.hooks.on(sdk.hooks.event.on_rune_gain, function(ev)
    runes_session = runes_session + ev.amount
    last_gain = ev.amount
    notice, notice_frames = string.format("+%d runes", ev.amount), 180
  end)

  sdk.hooks.on(sdk.hooks.event.on_death, function(ev)
    deaths_session = deaths_session + 1
    deaths_total = ev.deaths
    notice, notice_frames = "YOU DIED", 240
  end)

  sdk.hooks.on(sdk.hooks.event.on_present, function()
    sdk.ui.window("##hud", function()
      sdk.ui.text(string.format("Runes this session: %d", runes_session))
      sdk.ui.text(string.format("Deaths this session: %d (all time: %s)", deaths_session, deaths_total and tostring(deaths_total) or "?"))
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
