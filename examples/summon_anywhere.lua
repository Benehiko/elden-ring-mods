-- Example: spirit ashes work anywhere, not only beside a Rebirth Monument.
--
-- A game rule, so the manifest names the rule as its permission and sets it
-- from the entry point. One spirit is out at a time and it stays with the
-- player; inside a summoning pool nothing changes. See
-- docs/e16/summon-anywhere.md for how it works.

local mod = {
  name = "summon_anywhere",
  version = "1.0.0",
  run_at = "launch",
  permissions = { "spirit_summon_anywhere", "log" },
}

function mod.on_launch(sdk)
  sdk.rules.spirit_summon_anywhere = true
  sdk.log.info("summon_anywhere: spirit ashes usable outside summoning pools")
end

return mod
