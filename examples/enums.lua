-- Example: name game things by enum, not by string.
--
-- Every game property a mod names has an enum on the SDK:
--
--   sdk.hooks.event   the events `hooks.on` subscribes to    (on_death, ...)
--   sdk.watch.stat    the values `watch.on`/`watch.get` read (hp, runes, ...)
--   sdk.params.file   the files `params.row`/`rows` open     (CharaInitParam, ...)
--
-- The type stubs declare each one as a LuaLS `---@enum`, so the editor
-- completes the names and flags one that does not exist. In the game, a name
-- that does not exist is an error on the line that indexes it, which is a
-- better place to learn about a typo than a handler that never fires. Each
-- value is the name itself, so `ch.stat == sdk.watch.stat.deaths` compares as
-- expected and plain strings still work.
--
-- Try it: load it and read the log. Then die once: the `on_death` handler and
-- the `deaths` watcher both fire, subscribed through their enums. For
-- `sdk.params.file` in a mod that changes the game, see `level60.lua`.

local mod = {
  name = "enums",
  version = "1.0.0",
  run_at = "events",
  permissions = { "hooks", "watch", "params", "log" },
}

-- `pairs` over an enum is how a mod learns which names exist, so this keeps
-- working as the engine adds more.
local function names(enum)
  local out = {}
  for name, _ in pairs(enum) do out[#out + 1] = name end
  table.sort(out)
  return table.concat(out, ",")
end

function mod.setup(sdk)
  sdk.log.info("enums: hooks.event = " .. names(sdk.hooks.event))
  sdk.log.info("enums: watch.stat = " .. names(sdk.watch.stat))
  sdk.log.info("enums: params.file = " .. names(sdk.params.file))

  -- A typo is an error where it is written. pcall only to show the message;
  -- a real mod lets it fail.
  local ok, err = pcall(function() return sdk.hooks.event.on_deth end)
  sdk.log.info("enums: typo refused=" .. tostring(not ok) .. " (" .. tostring(err) .. ")")

  sdk.hooks.on(sdk.hooks.event.on_death, function()
    sdk.log.info("enums: on_death fired")
  end)

  sdk.watch.on(sdk.watch.stat.deaths, function(ch)
    if ch.stat == sdk.watch.stat.deaths then
      sdk.log.info(string.format("enums: deaths %d -> %d", ch.old, ch.new))
    end
  end)
end

return mod
