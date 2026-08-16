-- Example (negative): what a mod is NOT allowed to do.
--
-- This file exists to be refused. It declares no permissions yet reaches for
-- `os` and `io` — absent from the sandbox entirely — and for an SDK module
-- it never asked for. Loading it must fail loudly.
--
-- The rule it demonstrates: a mod receives exactly the `sdk.*` modules its
-- manifest lists. An undeclared module is not blocked at the call, it is
-- simply not there.

local mod = {
  name = "bad-sandbox",
  version = "1.0.0",
  run_at = "launch",
  permissions = {},
}

function mod.on_launch(sdk)
  os.execute("echo pwned")            -- os not in the sandbox
  local f = io.open("/etc/passwd")    -- io not in the sandbox
  sdk.params.rows("EquipParamWeapon.param") -- params not declared in permissions
end

return mod
