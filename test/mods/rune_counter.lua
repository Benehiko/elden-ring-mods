-- Test fixture: an event mod that reacts to a hook.
--
-- Exercises: `run_at = "events"`, the `hooks` permission, subscribing to a
-- named event, and reading a typed event payload. State kept in an upvalue
-- proves per-mod VM isolation (this counter must not leak into other mods).

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
