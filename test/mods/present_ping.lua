-- Test fixture: the first live `on_present` hook, using only implemented
-- SDK modules (`hooks` + `log`).
--
-- Exercises the E2 step-4 dispatch path end to end: a real in-game frame
-- reaches a Lua handler. `overlay.lua` also targets `on_present`, but it
-- declares `ui`/`perf` (not yet implemented) and so is rejected on load —
-- this fixture is the one that actually runs in-game.
--
-- The handler runs every frame, so it must be cheap and must not log per
-- frame (that would flood the log at 60+ Hz). It counts frames and logs once
-- per ~600 frames (~10 s at 60 fps), proving the hook fires continuously
-- while keeping the log readable.

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
