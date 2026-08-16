-- Example: run code every frame, without flooding the log.
--
-- `on_present` fires once per rendered frame — 60+ times a second — so a
-- handler on it must be cheap and must never log unconditionally. The
-- pattern here is the one to copy: count frames, act every Nth.
--
-- This is also the simplest way to prove the engine is live in your game:
-- one line roughly every ten seconds while you play.

local mod = {
  name = "present-ping",
  version = "1.0.0",
  run_at = "events",
  permissions = { "hooks", "log" },
}

local frames = 0

function mod.setup(sdk)
  sdk.hooks.on("on_present", function()
    frames = frames + 1
    if frames % 600 == 0 then
      sdk.log.info(string.format("on_present fired %d times", frames))
    end
  end)
end

return mod
