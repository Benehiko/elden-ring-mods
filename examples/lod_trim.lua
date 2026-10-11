-- Example: trade distant detail for frame time. `params` + `store`.
--
-- Every map object's draw settings live in PartsDrawParam: the distances at
-- which it swaps to a lower-poly model (LOD 0-1 ... 4-5), to a lower texture
-- LOD, to its distant-view model, and where it stops drawing or casting a
-- shadow. Grass has its own LOD ranges in GrassLodRangeParam.
--
--   PARTS_FACTOR  multiplies every finite object distance (1 = vanilla)
--   GRASS_FACTOR  multiplies the grass LOD ranges (1 = vanilla)
--   DRAW_CAP      metres; objects that draw at any distance (9999) stop at it
--   SHADOW_CAP    metres; objects that cast shadows at any distance stop at it
--   (a cap of 0 leaves those objects unlimited)
--   SHADOW_LOD_OFFSET  added to every object's shadowDrawLodOffset: shadows
--                 are drawn from that many coarser LOD levels
--
-- Measured on an Iris Xe laptop at 1280x720, render_scale 0.7, standing at
-- The First Step in daylight (GPU work per frame, megacycles):
--   vanilla                       44-45
--   GRASS_FACTOR 0.3              31-32   (-29%)
--   PARTS_FACTOR 0.3              38-39   (-14%)
--   both 0.3                      26      (-42%), 12.4 -> 18 fps at 13 W
-- The saving is in the G-buffer (opaque geometry) pass: 19.7 ms -> 8.0 ms with
-- both at 0.3, which took the frame from 20.8 to 25.2 fps on AC. Going to 0.1
-- (with SHADOW_LOD_OFFSET 2) cut that pass only to 6.1 ms and gained no fps:
-- by then the game's own CPU work is the limit, and the detail loss grows.
-- DRAW_CAP and SHADOW_CAP gained about 5 % at 13 W; leave them at 0 unless
-- the GPU, not the CPU, is what holds the frame back.
--
-- The game reads these values when it loads an area, so a change shows after
-- the next load (a warp, a death, a grace rest that reloads). Edits
-- hot-reload. A write is never undone on reload, so the mod remembers what it
-- last applied to each table, and one field's value after the write. If that
-- field still holds it, this is a reload: the mod lifts its old caps and
-- rescales by new / old. Otherwise the game loaded vanilla tables again.

local PARTS_FACTOR = 0.3
local GRASS_FACTOR = 0.3
local DRAW_CAP = 0
local SHADOW_CAP = 0
local SHADOW_LOD_OFFSET = 0

local mod = {
  name = "lod-trim",
  version = "0.4.0",
  run_at = "launch",
  permissions = { "params", "store", "log" },
}

local parts_fields = {
  "lv01_BorderDist", "lv12_BorderDist", "lv23_BorderDist", "lv34_BorderDist", "lv45_BorderDist",
  "tex_lv01_BorderDist", "DistantViewModel_BorderDist", "drawDist", "shadowDrawDist",
}
local grass_fields = { "LOD0_range", "LOD1_range", "LOD2_range" }
local unlimited = 9000
local vanilla_unlimited = 9999.0

local function close(a, b)
  return math.abs(a - b) <= 1e-4 * math.max(1.0, math.abs(b))
end

local function scale_rows(sdk, file, fields, k)
  local writes = 0
  if math.abs(k - 1.0) <= 1e-6 then return 0 end
  for row in sdk.params.rows(file) do
    for _, f in ipairs(fields) do
      local v = row[f]
      if v > 0 and v < unlimited then
        row[f] = v * k
        writes = writes + 1
      end
    end
  end
  return writes
end

-- Lift a cap this mod set earlier: every value equal to it goes back to 9999.
local function uncap(sdk, file, field, cap)
  local writes = 0
  if cap <= 0 then return 0 end
  for row in sdk.params.rows(file) do
    if close(row[field], cap) then
      row[field] = vanilla_unlimited
      writes = writes + 1
    end
  end
  return writes
end

local function shift(sdk, file, field, delta)
  local writes = 0
  if delta == 0 then return 0 end
  for row in sdk.params.rows(file) do
    local v = row[field] + delta
    if v > 7 then v = 7 end
    if v < -8 then v = -8 end
    row[field] = v
    writes = writes + 1
  end
  return writes
end

local function cap(sdk, file, field, limit)
  local writes = 0
  if limit <= 0 then return 0 end
  for row in sdk.params.rows(file) do
    if row[field] >= unlimited then
      row[field] = limit
      writes = writes + 1
    end
  end
  return writes
end

-- The first finite field of the first row that has one: the value this mod
-- checks to tell a hot reload (it still holds what we wrote) from a fresh
-- launch (the game loaded vanilla tables again).
local function reference(sdk, file, fields)
  for row in sdk.params.rows(file) do
    for _, f in ipairs(fields) do
      local v = row[f]
      if v > 0 and v < unlimited then return row.id, f, v end
    end
  end
  return nil
end

local function still_ours(sdk, key, file)
  local rid, rf, rv = sdk.store.get(key .. "_ref_id", nil), sdk.store.get(key .. "_ref_field", nil), sdk.store.get(key .. "_ref_value", nil)
  if not (rid and rf and rv) then return false end
  local row = sdk.params.row(file, rid)
  return row ~= nil and close(row[rf], rv)
end

local function remember(sdk, key, file, fields)
  local id, f, v = reference(sdk, file, fields)
  sdk.store.set(key .. "_ref_id", id)
  sdk.store.set(key .. "_ref_field", f)
  sdk.store.set(key .. "_ref_value", v)
end

function mod.on_launch(sdk)
  sdk.store.set("applied", nil)
  local parts = sdk.params.file.PartsDrawParam
  local grass = sdk.params.file.GrassLodRangeParam

  local ours = still_ours(sdk, "parts_applied", parts)
  local was = ours and sdk.store.get("parts_applied", 1.0) or 1.0
  local dwas = ours and sdk.store.get("draw_cap_applied", 0) or 0
  local swas = ours and sdk.store.get("shadow_cap_applied", 0) or 0
  local owas = ours and sdk.store.get("shadow_lod_applied", 0) or 0
  local lifted = uncap(sdk, parts, "drawDist", dwas) + uncap(sdk, parts, "shadowDrawDist", swas)
  local pw = scale_rows(sdk, parts, parts_fields, PARTS_FACTOR / was)
  local dw = cap(sdk, parts, "drawDist", DRAW_CAP)
  local sw = cap(sdk, parts, "shadowDrawDist", SHADOW_CAP)
  local ow = shift(sdk, parts, "shadowDrawLodOffset", SHADOW_LOD_OFFSET - owas)
  sdk.store.set("shadow_lod_applied", SHADOW_LOD_OFFSET)
  sdk.store.set("parts_applied", PARTS_FACTOR)
  sdk.store.set("draw_cap_applied", DRAW_CAP)
  sdk.store.set("shadow_cap_applied", SHADOW_CAP)
  remember(sdk, "parts_applied", parts, parts_fields)

  local gours = still_ours(sdk, "grass_applied", grass)
  local gwas = gours and sdk.store.get("grass_applied", 1.0) or 1.0
  local gw = scale_rows(sdk, grass, grass_fields, GRASS_FACTOR / gwas)
  sdk.store.set("grass_applied", GRASS_FACTOR)
  remember(sdk, "grass_applied", grass, grass_fields)

  sdk.log.info(string.format(
    "lod-trim: objects %.2f -> %.2f (%d writes), draw cap %g -> %g (%d), shadow cap %g -> %g (%d), %d caps lifted, shadow LOD offset %+d -> %+d (%d); grass %.2f -> %.2f (%d writes)",
    was, PARTS_FACTOR, pw, dwas, DRAW_CAP, dw, swas, SHADOW_CAP, sw, lifted, owas, SHADOW_LOD_OFFSET, ow, gwas, GRASS_FACTOR, gw))
end

return mod
