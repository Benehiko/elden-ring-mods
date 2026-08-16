-- Example: the smallest mod that does anything.
--
-- Start here. A mod is one Lua file that returns a table: a manifest (name,
-- version, when to run, which SDK modules it needs) plus the entry point for
-- that `run_at`. A `launch` mod runs once, before the world exists.
--
-- Try it: drop this file in your mods directory and look for the line in the
-- engine log.

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
