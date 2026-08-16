-- Example: change a game parameter for every row in a table.
--
-- `sdk.params.rows` iterates a PARAM table; fields are read and written by
-- their real names, typed, and a name the paramdef does not know is a hard
-- error rather than a silent no-op.
--
-- The same code path runs both ways: offline `ermod apply` patches
-- regulation.bin with it, and in the running game it edits the live table.
--
-- Note: `GameAreaParam` has no vendored paramdef yet, so this one loads but
-- does not run offline — read it for the shape, run `level60.lua` instead.

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
