-- Example: an in-game settings screen that remembers — `ui` + `store`.
--
-- Every control writes to the mod's store the moment it changes, so the
-- values survive a relaunch. `store` is the only filesystem access a mod
-- gets; where the file lives is the engine's business, not the mod's.
--
-- Copy this one when your mod needs to be configurable in-game. Press Insert
-- to give the overlay keyboard focus, Insert again to give it back.

local mod = {
  name = "example-settings",
  version = "1.0.0",
  run_at = "events",
  permissions = { "ui", "store", "hooks", "log" },
}

local enabled, volume, name, mode

function mod.setup(sdk)
  enabled = sdk.store.get("enabled", false)
  volume = sdk.store.get("volume", 0.8)
  name = sdk.store.get("name", "Tarnished")
  mode = sdk.store.get("mode", 1)
  sdk.log.info(string.format("settings loaded: enabled=%s volume=%.2f name=%s mode=%d",
    tostring(enabled), volume, name, mode))

  sdk.hooks.on("on_present", function()
    sdk.ui.window("Example Settings", function()
      local v
      v = sdk.ui.checkbox("Enabled", enabled)
      if v ~= enabled then enabled = v; sdk.store.set("enabled", v) end

      v = sdk.ui.slider("Volume", volume, 0, 1)
      if v ~= volume then volume = v; sdk.store.set("volume", v) end

      v = sdk.ui.input("Name", name)
      if v ~= name then name = v; sdk.store.set("name", v) end

      v = sdk.ui.combo("Mode", mode, { "Off", "On", "Auto" })
      if v ~= mode then mode = v; sdk.store.set("mode", v) end

      sdk.ui.separator()
      if sdk.ui.button("Reset to defaults") then
        enabled, volume, name, mode = false, 0.8, "Tarnished", 1
        sdk.store.set("enabled", nil)
        sdk.store.set("volume", nil)
        sdk.store.set("name", nil)
        sdk.store.set("mode", nil)
      end
      sdk.ui.same_line()
      sdk.ui.text(sdk.ui.focused() and "(Insert releases focus)" or "(Insert to edit)")
    end, { x = 20, y = 300, w = 340, h = 0, flags = { "auto_size" } })
  end)
end

return mod
