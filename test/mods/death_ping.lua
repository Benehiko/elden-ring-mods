-- Test fixture: an event mod for the state-driven events.
--
-- Subscribes to both `on_death` and `on_rune_gain` and logs each occurrence,
-- so a live run can confirm the GameDataMan-derived events against what
-- happens on screen: pick up runes → one `on_rune_gain` with the HUD delta;
-- die → one `on_death`. Not embedded in any host test (rune_counter.lua
-- covers the dispatch there); this one exists to be copied into the prefix's
-- mods directory for a live session.

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
