-- Example: two events at once, printed as they happen.
--
-- Subscribes to `on_death` and `on_rune_gain` and logs each occurrence, so
-- you can watch the engine's view of the game line up with the screen: pick
-- up runes and one `on_rune_gain` appears with the HUD's delta; die and one
-- `on_death` appears.
--
-- Useful as a sanity check when an event-driven mod of yours is not firing.

local mod = {
  name = "death-ping",
  version = "1.0.0",
  run_at = "events",
  permissions = { "hooks", "log" },
}

local deaths = 0

function mod.setup(sdk)
  sdk.hooks.on("on_death", function()
    deaths = deaths + 1
    sdk.log.info(string.format("on_death fired (session deaths %d)", deaths))
  end)
  sdk.hooks.on("on_rune_gain", function(event)
    sdk.log.info(string.format("on_rune_gain fired: +%d", event.amount))
  end)
end

return mod
