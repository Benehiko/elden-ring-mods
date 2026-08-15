-- Test fixture: the simplest possible launch mod.
--
-- Exercises: manifest parsing, `run_at = "launch"`, the `log` permission,
-- and a single on_launch dispatch. If the runtime can load and run this,
-- the Lua VM + SDK bootstrap works end to end.

local mod = {
  name = "hello-launch",
  version = "1.0.0",
  run_at = "launch",
  permissions = { "log" },
}

function mod.on_launch(sdk)
  sdk.log.info("hello from a launch mod")
end

return mod
