-- Example: two events at once, printed as they happen.
--
-- Subscribes to `on_death` and `on_rune_gain` and logs each occurrence, so
-- you can watch the engine's view of the game line up with the screen: pick
-- up runes and one `on_rune_gain` appears with the HUD's delta; die and one
-- `on_death` appears.
--
-- Two death counts, and they are different things:
--   * `event.deaths` (on_death's payload) is the character's lifetime count,
--     the game's own counter, saved with the character. It includes this
--     death. `sdk.watch.get(sdk.watch.stat.deaths)` reads the same counter at
--     any time (with the "watch" permission).
--   * `session` below is this mod's own count since it loaded.
--
-- Useful as a sanity check when an event-driven mod of yours is not firing.

local mod = {
  name = "death-ping",
  version = "1.1.0",
  run_at = "events",
  permissions = { "hooks", "log" },
}

local session = 0

function mod.setup(sdk)
  sdk.hooks.on(sdk.hooks.event.on_death, function(event)
    session = session + 1
    sdk.log.info(string.format("on_death fired (character deaths %d, this session %d)", event.deaths, session))
  end)
  sdk.hooks.on(sdk.hooks.event.on_rune_gain, function(event)
    sdk.log.info(string.format("on_rune_gain fired: +%d", event.amount))
  end)
end

return mod
