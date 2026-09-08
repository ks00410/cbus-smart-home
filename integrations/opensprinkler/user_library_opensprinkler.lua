require("user.secrets")

-- =============================================================================
-- SECTION 1 — MODULE TABLE
-- =============================================================================

local http = require("socket.http")
local json = require("json")

-- Public module table — registered as a global so resident/event scripts can
-- call sprinkler.Resident_Poll() and sprinkler.RunZone() / StopZone().
local S = {}
sprinkler = S

-- =============================================================================
-- SECTION 2 — CONFIGURATION
-- =============================================================================

-- IP address of the OpenSprinkler device.
-- Assign a DHCP reservation so this never changes.
local OS_HOST = secrets.opensprinkler.host

-- MD5 hash of the device password, pre-computed and stored in user.secrets.
-- See README for how to generate this value.
local OS_PW_MD5 = secrets.opensprinkler.password_md5

-- C-Bus network index that owns all OpenSprinkler user params (0 = first/only).
local CBUS_NETWORK = 0

-- Name of the C-Bus user param used as a debug-logging toggle.
local DEBUG_PARAM = "Debug Logging"

-- =============================================================================
-- SECTION 3 — ID MAPS
-- =============================================================================

-- Endpoint paths (appended to http://<host>/)
local EP_OPTIONS  = "jo"   -- system options (water level, firmware, etc.)
local EP_VARS     = "jc"   -- controller variables (last run, rain sensor, etc.)
local EP_STATUS   = "js"   -- station on/off status + remaining time
local EP_STATIONS = "jn"   -- station names and configuration
local EP_CONTROL  = "cm"   -- manual station run/stop

-- =============================================================================
-- SECTION 4 — MODULE STATE
-- =============================================================================

local _missingParamWarned = {}

-- Zone names discovered from /jn — cached after first successful fetch so
-- subsequent polls do not re-fetch names if the controller is unreachable.
local _zoneNames = nil

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
      log("SPRINKLER: UserParam '" .. name .. "' does not exist on network "
          .. tostring(network) .. " – skipping write")
      _missingParamWarned[key] = true
    end
  end
end

-- =============================================================================
-- SECTION 7 — UTILITY FUNCTIONS
-- =============================================================================

-- Build a URL with the password param and optional extra query params.
-- extra is a table of key=value pairs appended after the password, e.g.
-- { sid = 2, en = 1, t = 300 }
local function buildUrl(endpoint, extra)
  local url = "http://" .. OS_HOST .. "/" .. endpoint .. "?pw=" .. OS_PW_MD5
  if extra then
    for k, v in pairs(extra) do
      url = url .. "&" .. tostring(k) .. "=" .. tostring(v)
    end
  end
  return url
end

-- Format a last-run record [station_idx, program_idx, duration_sec, end_epoch]
-- into a human-readable string. Station index is 0-based in the API.
local function formatLastRun(lrun, zoneNames)
  if type(lrun) ~= "table" or #lrun < 4 then return nil end
  local stationIdx = lrun[1]   -- 0-based
  local durationSec = lrun[3]
  local endEpoch    = lrun[4]

  if durationSec == 0 then return "No recent run" end

  local zoneName
  if zoneNames and zoneNames[stationIdx + 1] then
    zoneName = zoneNames[stationIdx + 1]
  else
    zoneName = "Zone " .. tostring(stationIdx + 1)
  end

  local mins = math.floor(durationSec / 60)
  local secs = durationSec % 60
  local duration
  if mins > 0 and secs > 0 then
    duration = mins .. "m " .. secs .. "s"
  elseif mins > 0 then
    duration = mins .. " min"
  else
    duration = secs .. " sec"
  end

  local endTime = os.date("%H:%M", endEpoch)
  return zoneName .. " ran for " .. duration .. ", ended " .. endTime
end

-- =============================================================================
-- SECTION 8 — (no derived value functions required for this integration)
-- =============================================================================

-- =============================================================================
-- SECTION 9 — HTTP FETCH
-- =============================================================================

-- Fetch an API endpoint and return the decoded JSON table, or nil on failure.
local function fetchJson(endpoint, extra, dbg)
  local url = buildUrl(endpoint, extra)
  debuglog("SPRINKLER GET " .. url, dbg)
  local body, code = http.request(url)
  if code ~= 200 then
    log("SPRINKLER: HTTP error " .. tostring(code) .. " on /" .. endpoint)
    return nil
  end
  local t = json.decode(body)
  if not t then
    log("SPRINKLER: JSON decode failed on /" .. endpoint)
    return nil
  end
  return t
end

-- =============================================================================
-- SECTION 10 — PAYLOAD PARSERS
-- =============================================================================

-- Fetch and return a table of zone names (1-based) from /jn.
-- Returns cached value if already fetched this session.
function S.GetZoneNames(dbg)
  if _zoneNames then return _zoneNames end

  local t = fetchJson(EP_STATIONS, nil, dbg)
  if not t or type(t["snames"]) ~= "table" then
    log("SPRINKLER: could not fetch zone names from /jn")
    return nil
  end

  _zoneNames = t["snames"]   -- array of strings, 1-based
  debuglog("SPRINKLER: discovered " .. #_zoneNames .. " zones", dbg)
  return _zoneNames
end

-- Fetch system options. Returns { waterLevel, firmwareVersion }.
function S.GetSystemOptions(dbg)
  local t = fetchJson(EP_OPTIONS, nil, dbg)
  if not t then return nil end
  return {
    waterLevel       = t["wl"],
    firmwareVersion  = t["fwv"],
  }
end

-- Fetch controller variables. Returns { rainSensor, rainDelay, lastRun }.
function S.GetControllerVars(dbg)
  local t = fetchJson(EP_VARS, nil, dbg)
  if not t then return nil end
  return {
    rainSensor  = t["rs"],
    rainDelay   = t["rdst"],
    lastRun     = t["lrun"],
  }
end

-- Fetch station status. Returns { active (array of 0/1), remaining (array of seconds) }.
function S.GetStationStatus(dbg)
  local t = fetchJson(EP_STATUS, nil, dbg)
  if not t then return nil end
  return {
    active    = t["sn"],    -- array: 1=running, 0=off (0-based station index)
    remaining = t["ps"],    -- array of [program, remaining_seconds] pairs
  }
end

-- =============================================================================
-- SECTION 11 — RESIDENT POLL
-- =============================================================================

function S.Resident_Poll()
  local dbg = isDebuggingEnabled()   -- cached once; passed to all helpers

  -- ── Zone names (cached) ────────────────────────────────────────────────────
  local zoneNames = S.GetZoneNames(dbg)

  -- ── System options ─────────────────────────────────────────────────────────
  local opts = S.GetSystemOptions(dbg)
  if opts then
    safeSetUserParam(CBUS_NETWORK, "Irrigation_WaterLevel", opts.waterLevel, dbg)
  end

  -- ── Controller variables ───────────────────────────────────────────────────
  local vars = S.GetControllerVars(dbg)
  if vars then
    safeSetUserParam(CBUS_NETWORK, "Irrigation_RainSensor", vars.rainSensor, dbg)
    safeSetUserParam(CBUS_NETWORK, "Irrigation_RainDelay",  vars.rainDelay,  dbg)

    local lastRunStr = formatLastRun(vars.lastRun, zoneNames)
    safeSetUserParam(CBUS_NETWORK, "Irrigation_LastRun", lastRunStr, dbg)
  end

  -- ── Station status (all zones) ─────────────────────────────────────────────
  local stn = S.GetStationStatus(dbg)
  if stn and type(stn.active) == "table" then
    for i, active in ipairs(stn.active) do
      -- Build param name from discovered zone name or fallback to Zone_N
      local zoneName
      if zoneNames and zoneNames[i] and zoneNames[i] ~= "" then
        -- Replace spaces with underscores for valid param names
        zoneName = zoneNames[i]:gsub("%s+", "_")
      else
        zoneName = "Zone_" .. tostring(i)
      end
      safeSetUserParam(CBUS_NETWORK, "Irrigation_" .. zoneName .. "_Active", active, dbg)

      -- Remaining run time for this zone (seconds), from ps array
      local remainingSec = 0
      if type(stn.remaining) == "table" and stn.remaining[i] then
        local ps = stn.remaining[i]
        if type(ps) == "table" and ps[2] then
          remainingSec = ps[2]
        end
      end
      safeSetUserParam(CBUS_NETWORK, "Irrigation_" .. zoneName .. "_Remaining", remainingSec, dbg)
    end
  end

  -- ── Timestamp ──────────────────────────────────────────────────────────────
  local nowtext = os.date("%d %b %Y, %H:%M")
  safeSetUserParam(CBUS_NETWORK, "Irrigation_LastUpdated", nowtext, dbg)

  -- ── Debug table ────────────────────────────────────────────────────────────
  if dbg and opts and vars and stn then
    local lines = {
      "SPRINKLER poll @ " .. nowtext,
      string.rep("-", 34),
      string.format("  %-28s %s", "Water Level",   tostring(opts.waterLevel) .. "%"),
      string.format("  %-28s %s", "Rain Sensor",   tostring(vars.rainSensor)),
      string.format("  %-28s %s", "Rain Delay",    tostring(vars.rainDelay) .. "s"),
      string.format("  %-28s %s", "Last Run",      tostring(formatLastRun(vars.lastRun, zoneNames))),
      string.rep("-", 34),
    }
    if type(stn.active) == "table" then
      for i, active in ipairs(stn.active) do
        local name = (zoneNames and zoneNames[i]) or ("Zone " .. i)
        lines[#lines + 1] = string.format("  %-28s %s", name, active == 1 and "RUNNING" or "off")
      end
    end
    lines[#lines + 1] = string.rep("-", 34)
    log(table.concat(lines, "\n"))
  end
end

-- =============================================================================
-- CONTROL FUNCTIONS (called from event scripts)
-- =============================================================================

-- Run a zone by 1-based zone number for the given duration in seconds.
-- e.g. sprinkler.RunZone(2, 300) — run zone 2 for 5 minutes.
function S.RunZone(zoneNumber, durationSeconds)
  local sid = zoneNumber - 1   -- API is 0-based
  local url = buildUrl(EP_CONTROL, { sid = sid, en = 1, t = durationSeconds })
  local body, code = http.request(url)
  if code ~= 200 then
    log("SPRINKLER: RunZone HTTP error " .. tostring(code))
    return false
  end
  local t = json.decode(body or "")
  if t and t["result"] == 1 then
    log("SPRINKLER: Zone " .. zoneNumber .. " started for " .. durationSeconds .. "s")
    return true
  else
    log("SPRINKLER: RunZone failed – " .. tostring(body))
    return false
  end
end

-- Stop a zone by 1-based zone number.
function S.StopZone(zoneNumber)
  local sid = zoneNumber - 1
  local url = buildUrl(EP_CONTROL, { sid = sid, en = 0 })
  local body, code = http.request(url)
  if code ~= 200 then
    log("SPRINKLER: StopZone HTTP error " .. tostring(code))
    return false
  end
  log("SPRINKLER: Zone " .. zoneNumber .. " stopped")
  return true
end

-- Stop all zones immediately.
function S.StopAll()
  -- sid=0, en=0 with t=0 stops the master and all stations
  local url = buildUrl(EP_CONTROL, { sid = 0, en = 0, t = 0 })
  http.request(url)
  log("SPRINKLER: All zones stopped")
end
