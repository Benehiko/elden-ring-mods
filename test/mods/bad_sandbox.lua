-- Negative test fixture: the runtime MUST refuse to run this.
--
-- It declares no permissions yet reaches for `os`/`io` and undeclared SDK
-- modules. Loading it under the sandbox must fail loudly — this fixture
-- exists to prove the sandbox denies, not to be run successfully.

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
