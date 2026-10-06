-- Example: every watchable stat on screen — `watch` + `ui`.
--
-- `watch_all.lua` logs each stat; this one draws them instead, as a small
-- HUD: level, runes, deaths, HP, the eight attributes and, in co-op, the
-- distance to the nearest teammate. A stat that just changed shows its
-- change beside it, green up or red down, fading out over a few seconds.
--
-- Two halves of `sdk.watch` at work: `watch.get` reads a value now, cheap
-- enough for every frame, and `watch.on` says what changed and by how much,
-- which is what the highlight needs. Every value is nil until a character
-- is in the world (the title screen, a loading screen); it shows as "-"
-- rather than disappearing, so the window does not jump about.
--
-- Try it: pick up runes, take a hit, level up at a grace. Each change
-- lights up its own line. Nothing here touches the game: it only reads and
-- draws.

local mod = {
  name = "stats-overlay",
  version = "1.0.0",
  run_at = "events",
  permissions = { "watch", "ui", "hooks" },
}

-- What to show, in order: the stat's name in `sdk.watch.stat`, and its
-- label. A `false` row draws a separator.
local rows = {
  { "level", "Level" },
  { "runes", "Runes" },
  { "deaths", "Deaths" },
  false,
  { "hp", "HP" },
  { "hp_max", "HP max" },
  false,
  { "vigor", "Vigor" },
  { "mind", "Mind" },
  { "endurance", "Endurance" },
  { "strength", "Strength" },
  { "dexterity", "Dexterity" },
  { "intelligence", "Intelligence" },
  { "faith", "Faith" },
  { "arcane", "Arcane" },
}

local highlight_frames = 240 -- about four seconds at 60 fps
local recent = {} -- stat name -> { delta = n, frames = left }

function mod.setup(sdk)
  for _, row in ipairs(rows) do
    if row then
      sdk.watch.on(sdk.watch.stat[row[1]], function(ch)
        recent[ch.stat] = { delta = ch.delta, frames = highlight_frames }
      end)
    end
  end

  sdk.hooks.on(sdk.hooks.event.on_present, function()
    sdk.ui.window("##stats", function()
      for _, row in ipairs(rows) do
        if not row then
          sdk.ui.separator()
        else
          local name, label = row[1], row[2]
          local v = sdk.watch.get(sdk.watch.stat[name])
          sdk.ui.text(string.format("%-13s %s", label, v == nil and "-" or tostring(v)))
          local r = recent[name]
          if r and r.frames > 0 then
            r.frames = r.frames - 1
            local a = math.min(1, r.frames / 60)
            local color = r.delta >= 0 and { 0.4, 0.9, 0.4, a } or { 1, 0.35, 0.35, a }
            sdk.ui.same_line()
            sdk.ui.text(string.format("%+d", r.delta), color)
          end
        end
      end

      -- Only in co-op: the distance is nil when there is no other player.
      local d = sdk.watch.get(sdk.watch.stat.coop_distance)
      if d ~= nil then
        sdk.ui.separator()
        sdk.ui.text(string.format("%-13s %d m", "Nearest ally", d))
      end
    end, { x = 20, y = 140, anchor = "top_left", once = true, flags = { "no_title", "auto_size", "no_inputs" } })
  end)
end

return mod
