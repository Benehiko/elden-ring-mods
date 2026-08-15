-- Test fixture: the `params` module, the API that must behave identically
-- offline (patches regulation.bin) and in-game (edits live param tables).
--
-- Exercises: `params.rows` iteration, typed field read, field write, and
-- the field-name validation path (a bogus field must be a hard error). The
-- runtime test harness should assert this mod both applies cleanly and, in
-- a negative variant, rejects an unknown field.

local mod = {
  name = "double-runes",
  version = "1.0.0",
  run_at = "launch",
  permissions = { "params", "log" },
}

function mod.on_launch(sdk)
  local n = 0
  for row in sdk.params.rows("GameAreaParam.param") do
    row.bonusSoul_single = row.bonusSoul_single * 2
    n = n + 1
  end
  sdk.log.info(string.format("doubled rune reward on %d GameAreaParam rows", n))
end

return mod
