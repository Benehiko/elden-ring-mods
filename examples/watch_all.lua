-- Example: watch every game value the engine can read.
--
-- `hooks` reports events (a death, a rune pickup); `watch` reports values: a
-- number the game keeps changed, from what to what. This mod subscribes to
-- every stat in `sdk.watch.stat` and logs each change, and every ~5 seconds
-- logs `sdk.watch.get` for all of them, so a stat that never becomes
-- readable shows up as `nil` instead of as silence.
--
-- Try it: load into a world (every value is nil until you do), level up or
-- pick up runes, take a hit, die. Each shows as one CHANGE line. Raising
-- vigor moves `hp_max` too.
--
-- `pairs` over `sdk.watch.stat` is how a mod learns which stats exist, so
-- this keeps working as the engine adds more.

local mod = {
  name = "watch-all",
  version = "1.0.0",
  run_at = "events",
  permissions = { "watch", "hooks", "log" },
}

local frames = 0

function mod.setup(sdk)
  local names = {}
  for name, _ in pairs(sdk.watch.stat) do
    names[#names + 1] = name
  end
  table.sort(names)
  sdk.log.info("watch-all: stats = " .. table.concat(names, ","))

  for _, name in ipairs(names) do
    sdk.watch.on(sdk.watch.stat[name], function(ch)
      sdk.log.info(string.format("watch-all: CHANGE %s %d -> %d (%+d)", ch.stat, ch.old, ch.new, ch.delta))
    end)
  end

  -- on_present fires every frame: act every 300th, never log every frame.
  sdk.hooks.on(sdk.hooks.event.on_present, function()
    frames = frames + 1
    if frames % 300 == 0 then
      local parts = {}
      for _, name in ipairs(names) do
        local v = sdk.watch.get(sdk.watch.stat[name])
        parts[#parts + 1] = name .. "=" .. (v == nil and "nil" or tostring(v))
      end
      sdk.log.info("watch-all: GET " .. table.concat(parts, " "))
    end
  end)
end

return mod
