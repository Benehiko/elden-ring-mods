-- Example: a tool window rather than a game change — `perf` + `ui`.
--
-- Draws frame rate, a rolling frame-time plot and every loaded mod's script
-- cost, including its own. This is what a side application in Lua looks
-- like: read the engine's counters, draw once per frame, never stutter the
-- game.
--
-- Handy while developing your own mod — watch your handler's cost in the
-- table as you hot-reload it.

local mod = {
  name = "perf-monitor",
  version = "1.0.0",
  run_at = "events",
  permissions = { "ui", "perf", "hooks" },
}

local history = {}
local history_len = 120
local pos = 1
local show_mods = true

function mod.setup(sdk)
  sdk.hooks.on("on_present", function()
    local ms = sdk.perf.frame_ms()
    history[pos] = ms
    pos = pos % history_len + 1

    sdk.ui.window("Performance", function()
      sdk.ui.text(string.format("%.1f fps   %.2f ms   frame %d", sdk.perf.fps(), ms, sdk.perf.frame()))
      sdk.ui.plot("##frame_ms", history, { min = 0, max = 33.3, height = 50 })
      show_mods = sdk.ui.checkbox("Show mod cost", show_mods)
      if show_mods then
        sdk.ui.separator()
        for _, m in ipairs(sdk.perf.mods()) do
          sdk.ui.text(string.format("%-16s %6.3f ms avg  %6.3f ms last  %d calls",
            m.name, m.avg_ms, m.last_ms, m.calls))
        end
      end
    end, { x = 20, y = 20, w = 360, h = 0, flags = { "auto_size" } })
  end)
end

return mod
