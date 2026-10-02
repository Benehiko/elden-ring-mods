-- Example: change class defaults by name with sdk.items.
--
-- `sdk.items` maps every item, spell, skill and class the game names to its
-- row id (docs/item-inventory.md), and `sdk.items.file` names the param file
-- those ids are rows of. Together with `sdk.params.row` that is "change this
-- default" without looking up a single number.
--
-- Here every class starts with more flasks: CharaInitParam's HpEstMax and
-- MpEstMax are the starting Flask of Crimson Tears and Flask of Cerulean Tears
-- counts. The Wretch also starts with a Flask of Crimson Tears' worth of
-- extra Golden Seeds in its item slot 1, by name.

local mod = {
  name = "class_flasks",
  version = "1.0.0",
  run_at = "launch",
  permissions = { "params", "log" },
}

function mod.on_launch(sdk)
  local classes = sdk.items.classes
  for _, name in ipairs({ "vagabond", "warrior", "hero", "bandit", "astrologer",
                          "prophet", "confessor", "samurai", "prisoner", "wretch" }) do
    local row = sdk.params.row(sdk.items.file.classes, classes[name])
    if row then
      local hp, mp = row.HpEstMax, row.MpEstMax
      row.HpEstMax = 6
      row.MpEstMax = 4
      sdk.log.info(string.format("%s: flasks %d/%d -> %d/%d", name, hp, mp, row.HpEstMax, row.MpEstMax))
    end
  end

  local wretch = sdk.params.row(sdk.items.file.classes, classes.wretch)
  if wretch then
    wretch.item_01 = sdk.items.upgrade_materials.golden_seed
    wretch.itemNum_01 = 3
    sdk.log.info("wretch: starts with 3 Golden Seeds")
  end
end

return mod
