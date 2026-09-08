require("user.secrets")

-- =============================================================================
-- SECTION 1 — MODULE TABLE
-- =============================================================================

local https  = require("ssl.https")
local http   = require("socket.http")
local ltn12  = require("ltn12")
local json   = require("json")

-- Public module table — registered as a global so resident/event scripts can
-- call sonos.Resident_Poll() and sonos.Play() / Pause() / SetVolume() etc.
local S = {}
sonos = S

-- =============================================================================
-- SECTION 2 — CONFIGURATION
-- =============================================================================

-- One speaker IP per household is sufficient for discovery.
-- The integration will discover all groups and players automatically.
-- Assign DHCP reservations for all Sonos speakers so IPs never change.
local DISCOVERY_IPS = {
  "192.168.1.52",
  "192.168.1.80",
  "192.168.1.93",
  "192.168.1.133",
  "192.168.1.72",
}

-- Sonos Local Control API base port (HTTPS).
local SONOS_PORT = 1443

-- C-Bus network index that owns all Sonos user params (0 = first/only network).
local CBUS_NETWORK = 0

-- Name of the C-Bus user param used as a debug-logging toggle.
local DEBUG_PARAM = "Debug Logging"

-- =============================================================================
-- SECTION 3 — ID MAPS
-- =============================================================================

-- Map Sonos playback state strings to short display strings.
local PLAYBACK_STATE_MAP = {
  PLAYBACK_STATE_PLAYING  = "Playing",
  PLAYBACK_STATE_PAUSED   = "Paused",
  PLAYBACK_STATE_IDLE     = "Idle",
  PLAYBACK_STATE_BUFFERING = "Buffering",
}

-- =============================================================================
-- SECTION 4 — MODULE STATE
-- =============================================================================

local _missingParamWarned = {}

-- Cached discovery results.  Populated on first successful discovery and
-- refreshed when a request returns an error suggesting stale IDs.
-- Structure:
--   _householdId  (string)  — e.g. "Sonos_hhid_XXX"
--   _groups       (table)   — array of { id, name, playerIds, coordinatorId }
--   _players      (table)   — map of playerId → { name, ip }
--   _baseUrl      (string)  — e.g. "https://192.168.1.52:1443"
local _householdId = nil
local _groups      = nil
local _players     = nil
local _baseUrl     = nil

-- =============================================================================
-- SECTION 5 — LOGGING HELPERS
-- =============================================================================

local function isDebuggingEnabled()
  local ok, val = pcall(GetUserParam, 0, DEBUG_PARAM)
  return ok and toboolean(val) or false
end

local function debuglog(str, dbg)
  if dbg then log(str) end
end

-- =============================================================================
-- SECTION 6 — C-BUS I/O HELPERS
-- =============================================================================

local function safeGetUserParam(network, name)
  local ok, val = pcall(GetUserParam, network, name)
  return ok and val or nil
end

local function safeSetUserParam(network, name, value, dbg)
  if value == nil then return end
  local ok = pcall(SetUserParam, network, name, value)
  if not ok then
    local key = tostring(network) .. ":" .. name
    if dbg or not _missingParamWarned[key] then
      log("SONOS: UserParam '" .. name .. "' does not exist on network "
          .. tostring(network) .. " – skipping write")
      _missingParamWarned[key] = true
    end
  end
end

-- =============================================================================
-- SECTION 7 — UTILITY FUNCTIONS
-- =============================================================================

-- Sanitise a Sonos room name into a valid C-Bus param name component.
-- Replaces spaces and special characters with underscores.
local function sanitiseName(name)
  return (name or ""):gsub("[^%w]", "_"):gsub("_+", "_"):gsub("^_", ""):gsub("_$", "")
end

-- Build a "Now Playing" track string from metadata fields.
local function formatTrack(artist, title)
  if artist and artist ~= "" and title and title ~= "" then
    return title .. " – " .. artist
  elseif title and title ~= "" then
    return title
  elseif artist and artist ~= "" then
    return artist
  end
  return nil
end

-- =============================================================================
-- SECTION 8 — (no derived value functions required for this integration)
-- =============================================================================

-- =============================================================================
-- SECTION 9 — HTTP FETCH
-- =============================================================================

-- Make an HTTPS GET or POST request to the Sonos Local API.
-- baseUrl  — e.g. "https://192.168.1.52:1443"
-- path     — e.g. "/api/v1/households"
-- method   — "GET" or "POST" (default GET)
-- body     — string body for POST (optional)
-- Returns: decoded JSON table or nil, HTTP response code
local function apiRequest(baseUrl, path, method, body, dbg)
  method = method or "GET"
  local url = baseUrl .. path

  local responseBody = {}
  local reqHeaders = {
    ["Content-Type"]  = "application/json",
    ["Accept"]        = "application/json",
  }
  if body then
    reqHeaders["Content-Length"] = tostring(#body)
  end

  local ok, code, _, status = https.request({
    url     = url,
    method  = method,
    headers = reqHeaders,
    source  = body and ltn12.source.string(body) or nil,
    sink    = ltn12.sink.table(responseBody),
    verify  = "none",   -- Sonos uses a self-signed cert on the LAN
  })

  local responseStr = table.concat(responseBody)
  debuglog("SONOS " .. method .. " " .. url ..
           "\n  code: " .. tostring(code) ..
           "\n  body: " .. tostring(responseStr):sub(1, 200), dbg)

  if not ok or (type(code) == "number" and code >= 400) then
    -- 404 often means stale group/household IDs — signal caller to re-discover
    return nil, code
  end

  if responseStr == "" then return {}, code end

  local t = json.decode(responseStr)
  if not t then
    log("SONOS: JSON decode failed for " .. path)
    return nil, code
  end
  return t, code
end

-- =============================================================================
-- SECTION 10 — PAYLOAD PARSERS / DISCOVERY
-- =============================================================================

-- Try each discovery IP until we get a valid household ID.
-- Populates _householdId, _baseUrl, _groups, _players.
-- Returns true on success, false on failure.
function S.Discover(dbg)
  debuglog("SONOS: starting discovery", dbg)

  for _, ip in ipairs(DISCOVERY_IPS) do
    local base = "https://" .. ip .. ":" .. SONOS_PORT
    local t, code = apiRequest(base, "/api/v1/households", "GET", nil, dbg)

    if t and type(t.households) == "table" and #t.households > 0 then
      _householdId = t.households[1].id
      _baseUrl     = base
      debuglog("SONOS: household " .. _householdId .. " via " .. ip, dbg)

      -- Fetch groups and players
      local gdata, _ = apiRequest(base,
        "/api/v1/households/" .. _householdId .. "/groups",
        "GET", nil, dbg)

      if gdata then
        _groups  = gdata.groups  or {}
        _players = {}
        if type(gdata.players) == "table" then
          for _, player in ipairs(gdata.players) do
            -- Player websocket URL gives us its IP; fall back to discovery IP
            local playerIp = ip
            if player.websocketUrl then
              playerIp = player.websocketUrl:match("wss?://([^:/]+)") or ip
            end
            _players[player.id] = { name = player.name, ip = playerIp }
          end
        end
        debuglog("SONOS: found " .. #_groups .. " groups", dbg)
        return true
      end
    end
  end

  log("SONOS: discovery failed — no reachable Sonos speakers found")
  _householdId = nil
  _baseUrl     = nil
  _groups      = nil
  _players     = nil
  return false
end

-- Fetch playback state for one group. Returns table or nil.
local function fetchGroupPlayback(groupId, dbg)
  local path = "/api/v1/households/" .. _householdId
               .. "/groups/" .. groupId .. "/playback"
  local t, code = apiRequest(_baseUrl, path, "GET", nil, dbg)
  if not t then return nil, code end
  return t, code
end

-- Fetch now-playing metadata for one group. Returns table or nil.
local function fetchGroupMetadata(groupId, dbg)
  local path = "/api/v1/households/" .. _householdId
               .. "/groups/" .. groupId .. "/playbackMetadata"
  local t, code = apiRequest(_baseUrl, path, "GET", nil, dbg)
  if not t then return nil, code end
  return t, code
end

-- =============================================================================
-- SECTION 11 — RESIDENT POLL
-- =============================================================================

function S.Resident_Poll()
  local dbg = isDebuggingEnabled()   -- cached once; passed to all helpers

  -- ── Discover if not yet discovered (or re-discover on stale cache) ─────────
  if not _householdId or not _groups then
    if not S.Discover(dbg) then
      safeSetUserParam(CBUS_NETWORK, "Sonos_Status", "Offline", dbg)
      return
    end
  end

  local nowtext     = os.date("%d %b %Y, %H:%M")
  local activeRooms = 0
  local staleIds    = false

  -- ── Per-group poll ─────────────────────────────────────────────────────────
  for _, group in ipairs(_groups) do
    local groupName = sanitiseName(group.name or "Unknown")
    local prefix    = "Sonos_" .. groupName

    -- Playback state
    local pb, pbCode = fetchGroupPlayback(group.id, dbg)
    if pb == nil and pbCode == 404 then
      staleIds = true
      break
    end

    if pb then
      local stateRaw = pb.playbackState or ""
      local state    = PLAYBACK_STATE_MAP[stateRaw] or stateRaw
      local volume   = pb.volume
      local muted    = pb.muted and 1 or 0

      if state == "Playing" then activeRooms = activeRooms + 1 end

      safeSetUserParam(CBUS_NETWORK, prefix .. "_State",  state,  dbg)
      safeSetUserParam(CBUS_NETWORK, prefix .. "_Volume", volume, dbg)
      safeSetUserParam(CBUS_NETWORK, prefix .. "_Muted",  muted,  dbg)
    end

    -- Now-playing metadata
    local meta, _ = fetchGroupMetadata(group.id, dbg)
    if meta and meta.currentItem then
      local track   = meta.currentItem.track or {}
      local artist  = track.artist  or (meta.currentItem.artist)  or ""
      local title   = track.name    or (meta.currentItem.name)    or ""
      local service = (meta.streamInfo and meta.streamInfo.name)
                   or (meta.container and meta.container.service and meta.container.service.name)
                   or ""

      safeSetUserParam(CBUS_NETWORK, prefix .. "_Track",   formatTrack(artist, title), dbg)
      safeSetUserParam(CBUS_NETWORK, prefix .. "_Service", service ~= "" and service or nil, dbg)
    end
  end

  -- ── Re-discover on stale group IDs ─────────────────────────────────────────
  if staleIds then
    debuglog("SONOS: stale group IDs, re-discovering", dbg)
    _householdId = nil
    _groups      = nil
    if S.Discover(dbg) then
      -- Retry will happen on next poll cycle — avoid double-fetching this cycle
    end
    return
  end

  -- ── Summary params ─────────────────────────────────────────────────────────
  safeSetUserParam(CBUS_NETWORK, "Sonos_ActiveRooms", activeRooms, dbg)
  safeSetUserParam(CBUS_NETWORK, "Sonos_LastUpdated", nowtext,     dbg)
  safeSetUserParam(CBUS_NETWORK, "Sonos_Status",      "Online",    dbg)

  debuglog("SONOS: poll complete — " .. activeRooms .. " room(s) playing", dbg)
end

-- =============================================================================
-- CONTROL FUNCTIONS (called from event scripts)
-- =============================================================================

-- Internal: ensure discovery has been run.
local function ensureDiscovered(dbg)
  if not _householdId or not _groups then
    return S.Discover(dbg)
  end
  return true
end

-- Internal: find a group by sanitised room name (case-insensitive prefix match).
local function findGroup(roomName)
  if not _groups then return nil end
  local target = sanitiseName(roomName):lower()
  for _, g in ipairs(_groups) do
    if sanitiseName(g.name or ""):lower() == target then
      return g
    end
  end
  return nil
end

-- Internal: send a playback command POST to a group.
local function groupCommand(groupId, command, body, dbg)
  local path = "/api/v1/households/" .. _householdId
               .. "/groups/" .. groupId .. "/playback/" .. command
  local t, code = apiRequest(_baseUrl, path, "POST",
                              body and json.encode(body) or "{}", dbg)
  return t ~= nil
end

-- Play/resume the named room.
function S.Play(roomName)
  local dbg = isDebuggingEnabled()
  if not ensureDiscovered(dbg) then return false end
  local g = findGroup(roomName)
  if not g then log("SONOS: room not found: " .. tostring(roomName)); return false end
  return groupCommand(g.id, "play", nil, dbg)
end

-- Pause the named room.
function S.Pause(roomName)
  local dbg = isDebuggingEnabled()
  if not ensureDiscovered(dbg) then return false end
  local g = findGroup(roomName)
  if not g then log("SONOS: room not found: " .. tostring(roomName)); return false end
  return groupCommand(g.id, "pause", nil, dbg)
end

-- Skip to next track in the named room.
function S.Next(roomName)
  local dbg = isDebuggingEnabled()
  if not ensureDiscovered(dbg) then return false end
  local g = findGroup(roomName)
  if not g then log("SONOS: room not found: " .. tostring(roomName)); return false end
  return groupCommand(g.id, "skipToNextTrack", nil, dbg)
end

-- Set volume (0–100) for the named room.
function S.SetVolume(roomName, volume)
  local dbg = isDebuggingEnabled()
  if not ensureDiscovered(dbg) then return false end
  local g = findGroup(roomName)
  if not g then log("SONOS: room not found: " .. tostring(roomName)); return false end
  local path = "/api/v1/households/" .. _householdId
               .. "/groups/" .. g.id .. "/volume"
  local t, _ = apiRequest(_baseUrl, path, "POST",
                           json.encode({ volume = tonumber(volume) }), dbg)
  return t ~= nil
end

-- Mute/unmute the named room. muted = true or false.
function S.SetMute(roomName, muted)
  local dbg = isDebuggingEnabled()
  if not ensureDiscovered(dbg) then return false end
  local g = findGroup(roomName)
  if not g then log("SONOS: room not found: " .. tostring(roomName)); return false end
  local path = "/api/v1/households/" .. _householdId
               .. "/groups/" .. g.id .. "/volume"
  local t, _ = apiRequest(_baseUrl, path, "POST",
                           json.encode({ muted = muted == true }), dbg)
  return t ~= nil
end
