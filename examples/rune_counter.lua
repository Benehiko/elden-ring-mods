-- Example: react to something happening in the game.
--
-- An `events` mod gets a `setup` call instead of `on_launch`, and subscribes
-- to named events from there. Handlers receive a typed payload — here the
-- amount of runes picked up.
--
-- State lives in a local upvalue. Each mod runs in its own VM, so this
-- counter is private: no other mod can see or clobber it.

local mod = {
  name = "rune-counter",
  version = "1.0.0",
  run_at = "events",
  permissions = { "hooks", "log" },
}

local total = 0

function mod.setup(sdk)
  sdk.hooks.on("on_rune_gain", function(event)
    total = total + event.amount
    sdk.log.info(string.format("gained %d runes (session total %d)", event.amount, total))
  end)
end

return mod
