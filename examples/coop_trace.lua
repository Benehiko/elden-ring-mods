-- Example: a co-op debug session. `sdk.trace` + `ui` + `log`.
--
-- Run it on the host AND on every joiner. Each machine shows, in an overlay
-- window, what it believes about the shared world, and writes the same
-- beliefs to the engine log as lines a script can line up across machines:
--
--   * the session: host / joiner / solo, the session manager state, whether
--     the game is sending enemy sync records at all (`send_gate`);
--   * this player and the remote players' bodies: position, HP, ride state,
--     who drives them and their fade (`alpha` <= 0 is "despawned" on screen);
--   * every character near the player with its chr-sync slot: whether this
--     machine owns it, whether its owner's position records arrive and get
--     used (`age`), and the HP its owner last reported (`rec70`);
--   * the multiplayer-area barrier counters and the multiplayer predicates.
--
-- A character's `key` (its FieldInsHandle) names the same enemy on every
-- machine, so `grep 'coop-trace' host.log joiner.log | sort -k<key>` lines
-- them up: the host's row and the joiner's row for one enemy side by side.
--
-- Tags flag what a healthy session should never show (see `classify`):
--   STALE   not ours, alive, and no owner position used for a while: it stands still
--   GHOST   the owner reports it dead (rec70 HP 0) but it is alive here
--   UNREG   its sync slot is not registered: nobody owns it
--   NOTICK  its update selector says it is not being ticked
--   DRIVER  the driver disagrees with ownership (our AI on a remote-owned body, or the reverse)
--   HIDDEN  faded out (alpha <= 0): drawn invisible
--
-- Reuse: copy this file and change `config`, or call `classify` from your
-- own mod. Transitions (appear, vanish, owner/driver/dead/fade/ride changes)
-- are always logged; full snapshots every `snapshot_every` refreshes.
--
-- Insert gives the overlay focus so its controls can be used.

local mod = {
  name = "coop-trace",
  version = "1.0.0",
  run_at = "events",
  permissions = { "trace", "ui", "hooks", "log" },
}

local config = {
  radius = 60,           -- metres: characters shown and logged
  anomalies_only = false, -- the window lists flagged characters only
  max_rows = 40,          -- rows the window draws
  stale_frames = 90,      -- STALE once no owner record was used for this long
  log_snapshots = true,   -- write every character's row periodically
  snapshot_every = 10,    -- in refreshes (the engine refreshes every 30 frames)
  max_events = 40,        -- transition lines per refresh, at most
  show_predicates = false,
}

local RED = { 1.0, 0.4, 0.4 }
local AMBER = { 1.0, 0.8, 0.3 }
local GREEN = { 0.5, 1.0, 0.5 }
local GREY = { 0.7, 0.7, 0.7 }

local function s(v)
  if v == nil then return "-" end
  return tostring(v)
end

local function vec(p)
  if not p then return "-" end
  return string.format("%.1f,%.1f,%.1f", p.x, p.y, p.z)
end

local function hp(c)
  if c.hp == nil then return "-" end
  return string.format("%d/%s", c.hp, s(c.hp_max))
end

-- The tags for one character, as a list. `role` is the session's.
local function classify(c, role, cfg)
  local tags = {}
  local in_session = role == "host" or role == "joiner"
  local alive = c.dead ~= true and (c.hp == nil or c.hp > 0)
  local sy = c.sync
  if in_session and sy then
    if sy.registered == false then tags[#tags + 1] = "UNREG" end
    if sy.owned == false and alive and (sy.pop_age == nil or sy.pop_age > cfg.stale_frames) then
      tags[#tags + 1] = "STALE"
    end
    if sy.owned == false and alive and sy.rec70_hp == 0 then tags[#tags + 1] = "GHOST" end
    local net = c.manipulator == "NetAIManipulator"
    local ai = c.manipulator == "ComManipulator"
    if (sy.owned == true and net) or (sy.owned == false and ai) then tags[#tags + 1] = "DRIVER" end
  end
  if alive and c.update ~= nil and c.update ~= 0 then tags[#tags + 1] = "NOTICK" end
  if c.alpha ~= nil and c.alpha <= 0 then tags[#tags + 1] = "HIDDEN" end
  return tags
end
mod.classify = classify

-- One character's state, as one log/overlay row.
local function row(c, tags)
  local sy = c.sync or {}
  return string.format(
    "%s %s e=%s d=%s pos=%s hp=%s dead=%s own=%s reg=%s drv=%s upd=%s ll=%s/%s age=%s rec70=%s flags=%s alpha=%s ride=%s tags=%s",
    c.key, c.class ~= "" and c.class or "?", s(c.entity), c.dist and string.format("%.1f", c.dist) or "-",
    vec(c.pos), hp(c), s(c.dead), s(sy.owned), s(sy.registered), c.manipulator ~= "" and c.manipulator or "-",
    s(c.update), s(c.load_level), s(c.load_request), s(sy.pop_age), s(sy.rec70_hp),
    sy.flags and string.format("0x%x", sy.flags) or "-", c.alpha and string.format("%.2f", c.alpha) or "-",
    s(c.ride_state), #tags > 0 and table.concat(tags, ",") or "-")
end

-- What a transition is measured on: a change in any of these is a line.
local function signature(c, tags)
  local sy = c.sync or {}
  return table.concat({
    s(sy.owned), s(sy.registered), c.manipulator, s(c.dead),
    (c.alpha ~= nil and c.alpha <= 0) and "hidden" or "shown", s(c.ride_state), table.concat(tags, ","),
  }, "|")
end

local last_gen = -1
local refreshes = 0
local prev = {}       -- key -> { sig, dist }, characters and peers
local prev_role = nil
local view = { session = nil, player = nil, peers = {}, chrs = {}, tags = {}, barriers = nil, flagged = 0 }

local function prefix(session)
  return string.format("[%s f=%d]", session.role, session.frame)
end

local function refresh(sdk)
  local session = sdk.trace.session()
  view.session = session
  view.player = sdk.trace.player()
  view.peers = sdk.trace.peers()
  view.chrs = sdk.trace.chrs(config.radius)
  view.barriers = sdk.trace.barriers()
  view.tags = {}
  view.flagged = 0
  refreshes = refreshes + 1
  if not session.in_world then
    prev = {}
    return
  end
  local p = prefix(session)

  if session.role ~= prev_role then
    sdk.log.info(string.format("%s session role %s -> %s mgr=%s/%s phase=%s send_gate=%s fabricated=%s area=%s",
      p, s(prev_role), session.role, s(session.mgr_state), s(session.mgr_sub), s(session.phase_byte),
      s(session.send_gate), s(session.fabricated), s(session.area)))
    prev_role = session.role
  end

  local now = {}
  local events = 0
  local function note(kind, c, tags)
    local sig = signature(c, tags)
    now[c.key] = { sig = sig, dist = c.dist or 0, kind = kind }
    local was = prev[c.key]
    if events >= config.max_events then return end
    if not was then
      events = events + 1
      sdk.log.info(string.format("%s appear %s %s", p, kind, row(c, tags)))
    elseif was.sig ~= sig then
      events = events + 1
      sdk.log.info(string.format("%s change %s %s (was %s)", p, kind, row(c, tags), was.sig))
    end
  end

  if view.player then note("self", view.player, classify(view.player, session.role, config)) end
  for _, c in ipairs(view.peers) do note("peer", c, classify(c, session.role, config)) end
  for i, c in ipairs(view.chrs) do
    local tags = classify(c, session.role, config)
    view.tags[i] = tags
    if #tags > 0 then view.flagged = view.flagged + 1 end
    note("chr", c, tags)
  end

  -- Gone since the last refresh. A character that left only by walking out
  -- of the radius is not worth a line; one that vanished well inside it is
  -- the "despawn" this tool exists to catch.
  for key, was in pairs(prev) do
    if not now[key] and events < config.max_events and (was.kind ~= "chr" or was.dist < config.radius * 0.8) then
      events = events + 1
      sdk.log.info(string.format("%s vanish %s %s at d=%.1f (was %s)", p, was.kind, key, was.dist, was.sig))
    end
  end
  prev = now

  if config.log_snapshots and refreshes % config.snapshot_every == 0 then
    sdk.log.info(string.format("%s snapshot: %d chrs within %dm (%d walked), %d flagged, %d peers",
      p, #view.chrs, config.radius, session.chrs_seen, view.flagged, #view.peers))
    if view.player then sdk.log.info(p .. " row self " .. row(view.player, classify(view.player, session.role, config))) end
    for _, c in ipairs(view.peers) do sdk.log.info(p .. " row peer " .. row(c, classify(c, session.role, config))) end
    for i, c in ipairs(view.chrs) do sdk.log.info(p .. " row chr " .. row(c, view.tags[i])) end
    local b = view.barriers
    sdk.log.info(string.format("%s barriers area_cleared=%d warp_back_refused=%d block_solo_forced=%d",
      p, b.area_cleared, b.warp_back_refused, b.block_solo_forced))
  end
end

local function draw(sdk)
  local ui = sdk.ui
  local session = view.session
  if not session then return end
  ui.window("Co-op trace", function()
    if not session.in_world then
      ui.text("not in a world (or a game build the trace cannot read)", GREY)
      return
    end
    local role_color = (session.role == "host" or session.role == "joiner") and GREEN or AMBER
    ui.text(string.format("role %s   mgr %s/%s   phase %s   send %s   area %s   f=%d",
      session.role, s(session.mgr_state), s(session.mgr_sub), s(session.phase_byte),
      session.send_gate and "OPEN" or "closed", s(session.area), session.frame), role_color)

    local me = view.player
    if me then
      ui.text(string.format("me   %s pos %s hp %s ride %s drv %s", me.key, vec(me.pos), hp(me), s(me.ride_state), me.manipulator))
    end
    if #view.peers == 0 then
      ui.text("no remote player bodies", GREY)
    end
    for _, c in ipairs(view.peers) do
      local hidden = c.alpha ~= nil and c.alpha <= 0
      ui.text(string.format("peer %s d=%s hp %s ride %s alpha %s drv %s ll %s/%s",
        c.key, c.dist and string.format("%.1f", c.dist) or "-", hp(c), s(c.ride_state),
        c.alpha and string.format("%.2f", c.alpha) or "-", c.manipulator, s(c.load_level), s(c.load_request)),
        hidden and RED or nil)
    end

    local b = view.barriers
    ui.text(string.format("barriers: area cleared %d, warp-back refused %d, blocks forced solo %d",
      b.area_cleared, b.warp_back_refused, b.block_solo_forced))
    config.show_predicates = ui.checkbox("Multiplayer predicates", config.show_predicates)
    if config.show_predicates then
      for _, pr in ipairs(b.predicates) do
        if pr.calls > 0 then ui.text(string.format("  %-14s %d asked, %d true", pr.name, pr.calls, pr.trues)) end
      end
    end

    ui.separator()
    config.radius = ui.slider_int("Radius (m)", config.radius, 5, 300)
    config.anomalies_only = ui.checkbox("Flagged only", config.anomalies_only)
    ui.same_line()
    config.log_snapshots = ui.checkbox("Log snapshots", config.log_snapshots)
    ui.same_line()
    if ui.button("Snapshot now") then refreshes = config.snapshot_every - 1; last_gen = -1 end
    ui.text(string.format("%d characters within %dm (%d walked), %d flagged",
      #view.chrs, config.radius, session.chrs_seen, view.flagged))

    local shown = 0
    for i, c in ipairs(view.chrs) do
      local tags = view.tags[i] or {}
      if shown >= config.max_rows then break end
      if not config.anomalies_only or #tags > 0 then
        shown = shown + 1
        local sy = c.sync or {}
        ui.text(string.format("%s %5s m  hp %-11s own %-5s drv %-17s age %-5s rec70 %-6s %s",
          c.key, c.dist and string.format("%.1f", c.dist) or "-", hp(c), s(sy.owned),
          c.manipulator, s(sy.pop_age), s(sy.rec70_hp), table.concat(tags, " ")),
          #tags > 0 and RED or nil)
      end
    end
  end, { anchor = "top_left", x = 20, y = 260, w = 760, h = 560 })
end

function mod.setup(sdk)
  sdk.hooks.on(sdk.hooks.event.on_present, function()
    local gen = sdk.trace.generation()
    if gen ~= last_gen then
      last_gen = gen
      refresh(sdk)
    end
    draw(sdk)
  end)
end

return mod
