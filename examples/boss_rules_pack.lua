-- Example: a mod pack that changes a game rule.
--
-- A mod that lists other mods in `mods` is a mod pack. The pack and its
-- members take precedence over mods loaded on their own: if a standalone mod
-- sets the same rule or param field to a different value, the pack's value
-- is the one that lands, and the standalone mod still loads without that
-- write. Two packs that disagree on a setting are both refused.
--
-- `sdk.rules` holds engine-wide game rules. Setting one needs the "rules"
-- permission, and works only here in the entry point: a rule set from
-- an event handler is an error.
--
-- Try: load it beside `level60.lua` and read the log. Then add a standalone
-- mod that sets `boss_spectate = true` and watch its write be dropped.

local pack = {
  name = "boss-rules-pack",
  version = "1.0.0",
  run_at = "launch",
  permissions = { "rules", "log" },
  mods = { "level60" },
}

function pack.on_launch(sdk)
  -- Default true: a player who dies in a fog-wall boss fight watches a
  -- surviving teammate. False: they respawn at the grace instead.
  sdk.rules.boss_spectate = false
  sdk.log.info("boss fights: a fallen player respawns instead of spectating")
end

return pack
