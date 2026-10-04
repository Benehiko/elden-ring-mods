-- Example: a co-op debug session. `sdk.trace` + `ui` + `log`.
--
-- Run it on the host AND on every joiner. Each machine sends its own view of
-- the session to the others once a second (the engine does that while a
-- co-op session is up), so one machine -- the host, by default -- is the
-- single place where everything is collected: its overlay shows every
-- peer's view beside its own, and its log holds every machine's rows and
-- every disagreement between them.
--
-- What each machine sees of itself:
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
-- machine, which is what the cross-check matches on.
--
-- Tags flag what a healthy session should never show (see `classify`):
--   STALE   not ours, alive, and no owner position used for a while: it stands still
--   GHOST   the owner reports it dead (rec70 HP 0) but it is alive here
--   UNREG   its sync slot is not registered: nobody owns it
--   NOTICK  its update selector says it is not being ticked
--   DRIVER  the driver disagrees with ownership (our AI on a remote-owned body, or the reverse)
--   HIDDEN  faded out (alpha <= 0): drawn invisible
--
-- The cross-check (see `compare`) names what two machines disagree on for
-- one enemy: dead on one side only, HP apart, both or neither owning it,
-- drawn on one side only.
--
-- Reuse: copy this file and change `config`, or call `mod.classify` /
-- `mod.compare` from your own mod.
--
-- Insert gives the overlay focus so its sections and controls can be used.

local mod = {
  name = "coop-trace",
  version = "1.1.0",
  run_at = "events",
  permissions = { "trace", "ui", "hooks", "log" },
}

local config = {
  radius = 60,            -- metres: characters shown and logged
  max_rows = 40,          -- rows drawn per list
  stale_frames = 90,      -- STALE once no owner record was used for this long
  hp_tolerance = 0.1,     -- the cross-check calls HP apart beyond this share of max
  sort = 1,               -- index into `sorts`
  log_snapshots = true,   -- write every character's row periodically
  snapshot_every = 10,    -- in refreshes (the engine refreshes every 30 frames)
  max_events = 40,        -- transition lines per refresh, at most
  collect = 1,            -- index into `collect_modes`: who logs the peers' views
}

local sorts = { "flagged, then distance", "distance", "HP, lowest first", "key" }
local collect_modes = { "host only", "always", "never" }

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

local function dist(c)
  return c.dist and string.format("%.1f", c.dist) or "-"
end

local function in_session(role)
  return role == "host" or role == "joiner"
end

local function alive(c)
  return c.dead ~= true and (c.hp == nil or c.hp > 0)
end

-- The tags for one character, as a list. `role` is the session's.
local function classify(c, role, cfg)
  local tags = {}
  local sy = c.sync
  if in_session(role) and sy then
    if sy.registered == false then tags[#tags + 1] = "UNREG" end
    if sy.owned == false and alive(c) and (sy.pop_age == nil or sy.pop_age > cfg.stale_frames) then
      tags[#tags + 1] = "STALE"
    end
    if sy.owned == false and alive(c) and sy.rec70_hp == 0 then tags[#tags + 1] = "GHOST" end
    local net = c.manipulator == "NetAIManipulator"
    local ai = c.manipulator == "ComManipulator"
    if (sy.owned == true and net) or (sy.owned == false and ai) then tags[#tags + 1] = "DRIVER" end
  end
  if alive(c) and c.update ~= nil and c.update ~= 0 then tags[#tags + 1] = "NOTICK" end
  if c.alpha ~= nil and c.alpha <= 0 then tags[#tags + 1] = "HIDDEN" end
  return tags
end
mod.classify = classify

-- What this machine (`here`) and a peer (`there`) disagree on for one
-- character, as a list of short phrases.
local function compare(here, there, cfg)
  local diffs = {}
  local dh, dt = not alive(here), not alive(there)
  if dh ~= dt then diffs[#diffs + 1] = dh and "dead here, alive there" or "alive here, dead there" end
  if here.hp and there.hp and not dh and not dt then
    local max = math.max(here.hp_max or 1, there.hp_max or 1, 1)
    if math.abs(here.hp - there.hp) > max * cfg.hp_tolerance then
      diffs[#diffs + 1] = string.format("hp %d here, %d there", here.hp, there.hp)
    end
  end
  local oh = here.sync and here.sync.owned
  local ot = there.sync and there.sync.owned
  if oh ~= nil and ot ~= nil and not dh and not dt then
    if oh and ot then diffs[#diffs + 1] = "both own it" end
    if not oh and not ot then diffs[#diffs + 1] = "nobody owns it" end
  end
  local hh = here.alpha ~= nil and here.alpha <= 0
  local ht = there.alpha ~= nil and there.alpha <= 0
  if hh ~= ht then diffs[#diffs + 1] = hh and "hidden here, drawn there" or "drawn here, hidden there" end
  return diffs
end
mod.compare = compare

-- One character's state, as one log row.
local function row(c, tags)
  local sy = c.sync or {}
  return string.format(
    "%s %s e=%s d=%s pos=%s hp=%s dead=%s own=%s reg=%s drv=%s upd=%s ll=%s/%s age=%s rec70=%s flags=%s alpha=%s ride=%s tags=%s",
    c.key, c.class ~= "" and c.class or "?", s(c.entity), dist(c),
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

-- `items` is a list of { c = chr, tags = {...} }; sorted in place.
local function sort_items(items, how)
  local function d(x) return x.c.dist or math.huge end
  local comparators = {
    function(a, b)
      if (#a.tags > 0) ~= (#b.tags > 0) then return #a.tags > 0 end
      return d(a) < d(b)
    end,
    function(a, b) return d(a) < d(b) end,
    function(a, b)
      local ha, hb = a.c.hp or math.huge, b.c.hp or math.huge
      if ha ~= hb then return ha < hb end
      return d(a) < d(b)
    end,
    function(a, b) return a.c.key < b.c.key end,
  }
  table.sort(items, comparators[how] or comparators[1])
end

local last_gen = -1
local refreshes = 0
local prev = {}       -- key -> { sig, dist, kind }: this machine's characters and players
local prev_diff = {}  -- "<peer>/<key>" -> the diffs last logged
local prev_role = nil
local view = { session = nil, player = nil, peers = {}, items = {}, flagged = 0, barriers = nil, remotes = {} }

local function prefix(session)
  return string.format("[%s f=%d]", session.role, session.frame)
end

local function collecting(role)
  if config.collect == 2 then return true end
  if config.collect == 3 then return false end
  return role == "host"
end

-- The peers' views, each with its own tags and its cross-check against ours.
local function refresh_remotes(sdk, session, by_key, p, log_rows)
  view.remotes = {}
  local collect = collecting(session.role)
  for _, r in ipairs(sdk.trace.remotes()) do
    local entry = { r = r, items = {}, flagged = 0, diffs = {}, only_there = 0 }
    for _, c in ipairs(r.chrs) do
      local tags = classify(c, r.session.role, config)
      if #tags > 0 then entry.flagged = entry.flagged + 1 end
      entry.items[#entry.items + 1] = { c = c, tags = tags }
      local mine = by_key[c.key]
      if mine then
        local d = compare(mine, c, config)
        if #d > 0 then entry.diffs[#entry.diffs + 1] = { key = c.key, diffs = d, here = mine, there = c } end
        local k = string.format("%d/%s", r.id, c.key)
        local text = table.concat(d, ", ")
        if collect and (prev_diff[k] or "") ~= text then
          if text ~= "" then
            sdk.log.info(string.format("%s diff %s peer %d (%s): %s", p, c.key, r.id, r.session.role, text))
          elseif prev_diff[k] then
            sdk.log.info(string.format("%s agree %s peer %d (%s)", p, c.key, r.id, r.session.role))
          end
          prev_diff[k] = text ~= "" and text or nil
        end
      else
        entry.only_there = entry.only_there + 1
      end
    end
    sort_items(entry.items, config.sort)
    view.remotes[#view.remotes + 1] = entry
    if collect and log_rows then
      local rp = string.format("%s remote %d [%s f=%d age=%s]", p, r.id, r.session.role, r.session.frame, s(r.age))
      if r.player then sdk.log.info(rp .. " row self " .. row(r.player, classify(r.player, r.session.role, config))) end
      for _, c in ipairs(r.peers) do sdk.log.info(rp .. " row peer " .. row(c, classify(c, r.session.role, config))) end
      for _, it in ipairs(entry.items) do sdk.log.info(rp .. " row chr " .. row(it.c, it.tags)) end
    end
  end
end

local function refresh(sdk)
  local session = sdk.trace.session()
  view.session = session
  view.player = sdk.trace.player()
  view.peers = sdk.trace.peers()
  view.barriers = sdk.trace.barriers()
  view.items = {}
  view.flagged = 0
  refreshes = refreshes + 1
  if not session.in_world then
    prev = {}
    view.remotes = {}
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
  local by_key = {}
  for _, c in ipairs(sdk.trace.chrs(config.radius)) do
    local tags = classify(c, session.role, config)
    if #tags > 0 then view.flagged = view.flagged + 1 end
    view.items[#view.items + 1] = { c = c, tags = tags }
    by_key[c.key] = c
    note("chr", c, tags)
  end
  sort_items(view.items, config.sort)

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

  local snapshot = config.log_snapshots and refreshes % config.snapshot_every == 0
  if snapshot then
    sdk.log.info(string.format("%s snapshot: %d chrs within %dm (%d walked), %d flagged, %d peers",
      p, #view.items, config.radius, session.chrs_seen, view.flagged, #view.peers))
    if view.player then sdk.log.info(p .. " row self " .. row(view.player, classify(view.player, session.role, config))) end
    for _, c in ipairs(view.peers) do sdk.log.info(p .. " row peer " .. row(c, classify(c, session.role, config))) end
    for _, it in ipairs(view.items) do sdk.log.info(p .. " row chr " .. row(it.c, it.tags)) end
    local b = view.barriers
    sdk.log.info(string.format("%s barriers area_cleared=%d warp_back_refused=%d block_solo_forced=%d",
      p, b.area_cleared, b.warp_back_refused, b.block_solo_forced))
  end
  refresh_remotes(sdk, session, by_key, p, snapshot)
end

-- ── drawing ───────────────────────────────────────────────────────────

local function chr_line(ui, it)
  local c, sy = it.c, it.c.sync or {}
  ui.text(string.format("%s %5s m  hp %-11s own %-5s drv %-17s age %-5s rec70 %-6s %s",
    c.key, dist(c), hp(c), s(sy.owned), c.manipulator, s(sy.pop_age), s(sy.rec70_hp), table.concat(it.tags, " ")),
    #it.tags > 0 and RED or nil)
end

local function player_line(ui, label, c)
  local hidden = c.alpha ~= nil and c.alpha <= 0
  ui.text(string.format("%-4s %s d=%s pos %s hp %s ride %s alpha %s drv %s ll %s/%s",
    label, c.key, dist(c), vec(c.pos), hp(c), s(c.ride_state),
    c.alpha and string.format("%.2f", c.alpha) or "-", c.manipulator, s(c.load_level), s(c.load_request)),
    hidden and RED or nil)
end

-- `items` split into a flagged node and a healthy node; `id` keeps labels unique.
local function chr_lists(ui, items, flagged, id)
  ui.tree(string.format("Flagged (%d)###f%s", flagged, id), function()
    local shown = 0
    for _, it in ipairs(items) do
      if #it.tags > 0 and shown < config.max_rows then
        shown = shown + 1
        chr_line(ui, it)
      end
    end
    if flagged == 0 then ui.text("none", GREY) end
  end, true)
  ui.tree(string.format("Healthy (%d)###h%s", #items - flagged, id), function()
    local shown = 0
    for _, it in ipairs(items) do
      if #it.tags == 0 and shown < config.max_rows then
        shown = shown + 1
        chr_line(ui, it)
      end
    end
  end, false)
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

    if ui.collapsing("Session", true) then
      local role_color = in_session(session.role) and GREEN or AMBER
      ui.text(string.format("role %s   mgr %s/%s   phase %s   send %s   area %s   f=%d",
        session.role, s(session.mgr_state), s(session.mgr_sub), s(session.phase_byte),
        session.send_gate and "OPEN" or "closed", s(session.area), session.frame), role_color)
      ui.text(string.format("collecting peers' views: %s (%d peer view(s) arrived)",
        collecting(session.role) and "yes" or "no", #view.remotes), GREY)
    end

    if ui.collapsing(string.format("Players (%d remote)###players", #view.peers), true) then
      if view.player then player_line(ui, "me", view.player) end
      if #view.peers == 0 then ui.text("no remote player bodies", GREY) end
      for _, c in ipairs(view.peers) do player_line(ui, "peer", c) end
    end

    if ui.collapsing(string.format("Characters (%d within %dm, %d flagged)###chrs", #view.items, config.radius, view.flagged), true) then
      config.radius = ui.slider_int("Radius (m)", config.radius, 5, 300)
      config.sort = ui.combo("Sort", config.sort, sorts)
      ui.text(string.format("%d walked this refresh", session.chrs_seen), GREY)
      chr_lists(ui, view.items, view.flagged, "local")
    end

    if ui.collapsing(string.format("Remote views (%d)###remotes", #view.remotes), session.role == "host") then
      if #view.remotes == 0 then
        ui.text("no peer has sent its view yet (each machine needs this mod and the engine's co-op session)", GREY)
      end
      for _, e in ipairs(view.remotes) do
        local r = e.r
        local label = string.format("peer %d: %s, %d chrs, %d flagged, %d disagree, age %s f###peer%d",
          r.id, r.session.role, #r.chrs, e.flagged, #e.diffs, s(r.age), r.id)
        ui.tree(label, function()
          ui.text(string.format("its session: mgr %s/%s phase %s send %s f=%d",
            s(r.session.mgr_state), s(r.session.mgr_sub), s(r.session.phase_byte),
            r.session.send_gate and "OPEN" or "closed", r.session.frame))
          if r.player then player_line(ui, "self", r.player) end
          for _, c in ipairs(r.peers) do player_line(ui, "sees", c) end
          ui.tree(string.format("Disagreements (%d)###d%d", #e.diffs, r.id), function()
            if #e.diffs == 0 then ui.text("none among the characters both machines have", GREY) end
            for i, d in ipairs(e.diffs) do
              if i > config.max_rows then break end
              ui.text(string.format("%s %s m here: %s", d.key, dist(d.here), table.concat(d.diffs, ", ")), RED)
            end
          end, true)
          ui.text(string.format("%d of its characters are not within %dm here", e.only_there, config.radius), GREY)
          chr_lists(ui, e.items, e.flagged, tostring(r.id))
        end, true)
      end
    end

    if ui.collapsing("Barriers", false) then
      local b = view.barriers
      ui.text(string.format("area cleared %d, warp-back refused %d, blocks forced solo %d",
        b.area_cleared, b.warp_back_refused, b.block_solo_forced))
      for _, pr in ipairs(b.predicates) do
        if pr.calls > 0 then ui.text(string.format("  %-14s %d asked, %d true", pr.name, pr.calls, pr.trues)) end
      end
    end

    if ui.collapsing("Logging", false) then
      config.log_snapshots = ui.checkbox("Log snapshots", config.log_snapshots)
      ui.same_line()
      if ui.button("Snapshot now") then refreshes = config.snapshot_every - 1; last_gen = -1 end
      config.collect = ui.combo("Log peers' views", config.collect, collect_modes)
    end
  end, { anchor = "top_left", x = 20, y = 260, w = 820, h = 600 })
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
