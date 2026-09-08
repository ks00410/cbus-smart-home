require("user.secrets")

-- =============================================================================
-- SECTION 1 — MODULE TABLE
-- =============================================================================

local http = require("socket.http")
local json = require("cjson")

-- Public module table — registered as a global so resident scripts can call
-- ecowitt.Resident_Poll()
local E = {}
ecowitt = E

-- =============================================================================
-- SECTION 2 — CONFIGURATION
-- =============================================================================

-- Local API endpoint on the Ecowitt base station (LAN only, no cloud required).
local API_URL = "http://192.168.1.213/get_livedata_info"

-- C-Bus network index that owns all Ecowitt user params (0 = first/only network).
local CBUS_NETWORK = 0

-- Name of the C-Bus user param used as a debug-logging toggle.
-- Set it to true/1 in the C-Bus project to enable verbose output.
local DEBUG_PARAM = "Debug Logging"

-- Gust speed (knots) at which the GustAlert derived param is set to 1.
-- Default 20 kn (Beaufort 6 boundary) — outdoor furniture and awnings at risk.
local GUST_ALERT_THRESHOLD_KNOTS = 20

-- Window (seconds) used for the pressure trend calculation.
-- The current reading is compared against the oldest reading within this window.
local PRESSURE_HISTORY_SECONDS = 3 * 60 * 60   -- 3 hours

-- =============================================================================
-- SECTION 3 — ID MAPS
-- =============================================================================

-- Maps common_list field ids to param names.
-- Both hex strings ("0x02") and decimal strings some firmware versions emit
-- ("3", "5") are included so every id resolves to a readable name.
local COMMON_ID_MAP = {
  ["0x01"] = "IndoorTemp",
  ["0x02"] = "OutdoorTemp",
  ["0x03"] = "DewPoint",
  ["0x04"] = "WindChill",
  ["0x05"] = "HeatIndex",
  ["0x06"] = "IndoorHumidity",
  ["0x07"] = "OutdoorHumidity",
  ["0x08"] = "AbsBarometric",
  ["0x09"] = "RelBarometric",
  ["0x0A"] = "WindDirection",
  ["0x0B"] = "WindSpeed",
  ["0x0C"] = "GustSpeed",
  ["0x0D"] = "RainEvent",
  ["0x0E"] = "RainRate",
  ["0x0F"] = "RainGain",
  ["0x10"] = "RainDay",
  ["0x11"] = "RainWeek",
  ["0x12"] = "RainMonth",
  ["0x13"] = "RainYear",
  ["0x14"] = "RainTotals",
  ["0x15"] = "Light",
  ["0x16"] = "UV",
  ["0x17"] = "UVI",
  ["0x18"] = "DateTime",
  ["0x19"] = "DayMaxWind",
  ["0x6D"] = "WindDir",
  ["3"]    = "DewPoint",
  ["5"]    = "VPD",
}

local RAIN_ID_MAP = {
  ["0x0d"] = "RainEvent",
  ["0x0e"] = "RainRate",
  ["0x7c"] = "RainHour",
  ["0x10"] = "RainDay",
  ["0x11"] = "RainWeek",
  ["0x12"] = "RainMonth",
  ["0x13"] = "RainYear",
}

local BEAUFORT_DESC = {
  [0]  = "Calm",          [1]  = "Light Air",
  [2]  = "Light Breeze",  [3]  = "Gentle Breeze",
  [4]  = "Mod. Breeze",   [5]  = "Fresh Breeze",
  [6]  = "Strong Breeze", [7]  = "Near Gale",
  [8]  = "Gale",          [9]  = "Strong Gale",
  [10] = "Storm",         [11] = "Violent Storm",
  [12] = "Hurricane",
}

local UV_THRESHOLDS = {
  { 0,          nil, "None"      },
  { 2,           60, "Low"       },
  { 5,           30, "Moderate"  },
  { 7,           15, "High"      },
  { 10,          10, "Very High" },
  { math.huge,    5, "Extreme"   },
}

-- =============================================================================
-- SECTION 4 — MODULE STATE
-- =============================================================================

local _missingParamWarned = {}
local _pressureHistory    = {}

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
      log("ECOWITT: UserParam '" .. name .. "' does not exist on network "
          .. tostring(network) .. " – skipping write")
      _missingParamWarned[key] = true
    end
  end
end

-- =============================================================================
-- SECTION 7 — UTILITY FUNCTIONS
-- =============================================================================

local function extractNumber(val)
  if val == nil then return nil end
  local n = tostring(val):match("^%-?%d+%.?%d*")
  return n and tonumber(n) or nil
end

local function appendSortedRows(lines, tbl, prefix)
  local keys = {}
  for k in pairs(tbl) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    lines[#lines + 1] = string.format("  %-22s %s", prefix .. k, tostring(tbl[k]))
  end
end

-- =============================================================================
-- SECTION 8 — DERIVED VALUE FUNCTIONS
-- =============================================================================

local function calcFeelsLike(tempC, humidity, windKnots)
  if tempC == nil then return nil end
  if tempC <= 10 and windKnots ~= nil and windKnots > 0 then
    local windKmh = windKnots * 1.852
    return math.floor(
      (13.12 + 0.6215 * tempC - 11.37 * windKmh^0.16
       + 0.3965 * tempC * windKmh^0.16) * 10 + 0.5
    ) / 10
  elseif tempC >= 27 and humidity ~= nil and humidity >= 40 then
    local T, H = tempC, humidity
    local hi = -8.78469475556
        + 1.61139411    * T
        + 2.33854883889 * H
        - 0.14611605    * T * H
        - 0.01230809850 * T^2
        - 0.01642482778 * H^2
        + 0.00221173    * T^2 * H
        + 0.00072546    * T  * H^2
        - 0.00000358528 * T^2 * H^2
    return math.floor(hi * 10 + 0.5) / 10
  else
    return tempC
  end
end

local function calcComfortZone(tempC, humidity)
  if tempC == nil or humidity == nil then return nil end
  if tempC < 10 then
    return "Cold"
  elseif tempC < 18 then
    return humidity > 70 and "Cool & Humid" or "Cool"
  elseif tempC <= 24 then
    if humidity < 40 then return "Comfortable & Dry"
    elseif humidity <= 60 then return "Comfortable"
    else return "Comfortable & Humid" end
  elseif tempC < 30 then
    return humidity > 65 and "Warm & Humid" or "Warm"
  else
    return humidity > 60 and "Hot & Humid" or "Hot"
  end
end

local function calcBeaufort(windKnots)
  if windKnots == nil then return nil end
  if     windKnots <  1 then return 0
  elseif windKnots <  4 then return 1
  elseif windKnots <  7 then return 2
  elseif windKnots < 11 then return 3
  elseif windKnots < 17 then return 4
  elseif windKnots < 22 then return 5
  elseif windKnots < 28 then return 6
  elseif windKnots < 34 then return 7
  elseif windKnots < 41 then return 8
  elseif windKnots < 48 then return 9
  elseif windKnots < 56 then return 10
  elseif windKnots < 64 then return 11
  else                       return 12 end
end

local function calcGustAlert(gustKnots)
  if gustKnots == nil then return nil end
  return (gustKnots >= GUST_ALERT_THRESHOLD_KNOTS) and 1 or 0
end

local function calcUVBurnTime(uvi)
  if uvi == nil then return nil end
  for _, t in ipairs(UV_THRESHOLDS) do
    if uvi <= t[1] then return t[2] end
  end
end

local function calcUVLabel(uvi)
  if uvi == nil then return nil end
  for _, t in ipairs(UV_THRESHOLDS) do
    if uvi <= t[1] then return t[3] end
  end
end

local function calcDewPointComfort(dewPointC)
  if dewPointC == nil then return nil end
  if dewPointC < 10 then return "Dry"
  elseif dewPointC < 16 then return "Comfortable"
  elseif dewPointC < 18 then return "Slightly Humid"
  elseif dewPointC < 21 then return "Muggy"
  else                       return "Oppressive" end
end

local function calcFrostRisk(tempC, dewPointC)
  if tempC == nil or dewPointC == nil then return nil end
  return (dewPointC <= 0 and (tempC - dewPointC) <= 2) and 1 or 0
end

local function calcCondensationRisk(tempC, dewPointC)
  if tempC == nil or dewPointC == nil then return nil end
  return ((tempC - dewPointC) <= 2) and 1 or 0
end

-- Returns: trend (string "Rising"/"Falling"/"Steady"), rate (signed hPa change)
local function calcPressureTrend(currentHpa)
  if currentHpa == nil then return nil, nil end
  local now    = os.time()
  local cutoff = now - PRESSURE_HISTORY_SECONDS

  _pressureHistory[#_pressureHistory + 1] = { time = now, pressure = currentHpa }

  local trimmed = {}
  for _, entry in ipairs(_pressureHistory) do
    if entry.time >= cutoff then trimmed[#trimmed + 1] = entry end
  end
  _pressureHistory = trimmed

  if #_pressureHistory < 2 then return "Steady", 0 end

  local diff = currentHpa - _pressureHistory[1].pressure
  local trend
  if     diff >  1 then trend = "Rising"
  elseif diff < -1 then trend = "Falling"
  else                   trend = "Steady" end

  local rate = math.floor(diff * 10 + (diff >= 0 and 0.5 or -0.5)) / 10
  return trend, rate
end

local function calcWeatherOutlook(trend, rate)
  if trend == nil or rate == nil then return nil end
  local abs = math.abs(rate)
  if trend == "Steady" then
    return "Settled – current conditions likely to continue"
  elseif trend == "Rising" then
    if abs > 6 then return "Rapidly improving – clear skies soon, watch for frost tonight"
    elseif abs > 3 then return "Improving – clearing and settling within 6 hrs"
    else return "Slowly improving – gradual clearance expected" end
  else
    if abs > 6 then return "Storm likely – significant rain and wind within 6 hrs"
    elseif abs > 3 then return "Deteriorating – rain and wind within 12 hrs"
    else return "Slowly deteriorating – rain possible in 12–24 hrs" end
  end
end

-- =============================================================================
-- SECTION 9 — HTTP FETCH
-- =============================================================================

local function fetchLiveData(dbg)
  local body, code, _, status = http.request(API_URL)
  debuglog("ECOWITT GET " .. API_URL ..
           "\n  code:   " .. tostring(code) ..
           "\n  status: " .. tostring(status), dbg)
  if code ~= 200 then
    log("ECOWITT: HTTP error " .. tostring(code) .. " – " .. tostring(status))
    return nil
  end
  return body
end

-- =============================================================================
-- SECTION 10 — PAYLOAD PARSER
-- =============================================================================

function E.GetEcoWittStatus(dbg)
  local raw = fetchLiveData(dbg)
  if not raw then return nil end
  debuglog("ECOWITT response body: " .. raw, dbg)

  local payload = json.decode(raw)
  if not payload then
    log("ECOWITT: failed to decode JSON response")
    return nil
  end

  local result = { common = {}, rain = {}, soil = {} }

  if payload["common_list"] then
    for _, entry in ipairs(payload["common_list"]) do
      local rawId = tostring(entry["id"] or "")
      local name  = COMMON_ID_MAP[rawId:lower()] or COMMON_ID_MAP[rawId]
      result.common[name or ("id_" .. rawId)] = extractNumber(entry["val"])
    end
  end

  if payload["rain"] then
    for _, entry in ipairs(payload["rain"]) do
      local rawId = tostring(entry["id"] or "")
      local name  = RAIN_ID_MAP[rawId:lower()] or RAIN_ID_MAP[rawId]
      result.rain[name or ("id_" .. rawId)] = extractNumber(entry["val"])
    end
  end

  if payload["ch_soil"] then
    for _, entry in ipairs(payload["ch_soil"]) do
      local ch = tostring(entry["channel"] or "")
      if ch ~= "" then
        result.soil[ch] = extractNumber(entry["humidity"])
      end
    end
  end

  return result
end

-- =============================================================================
-- SECTION 11 — RESIDENT POLL
-- =============================================================================

function E.Resident_Poll()
  local dbg = isDebuggingEnabled()   -- cached once; passed to all helpers

  local status = E.GetEcoWittStatus(dbg)
  if not status then return end

  local nowtext = os.date("%d %b %Y, %H:%M")

  -- ── Raw sensor values ──────────────────────────────────────────────────────
  for name, value in pairs(status.common) do
    safeSetUserParam(CBUS_NETWORK, name, value, dbg)
  end
  for name, value in pairs(status.rain) do
    safeSetUserParam(CBUS_NETWORK, name, value, dbg)
  end

  -- ── Soil moisture (with change-detection timestamp) ────────────────────────
  for ch, value in pairs(status.soil) do
    local paramName    = "Soil" .. ch
    local paramUpdated = "Soil" .. ch .. "_Updated"
    local previous     = tonumber(safeGetUserParam(CBUS_NETWORK, paramName)) or 0
    if (value - previous) > 2 then
      safeSetUserParam(CBUS_NETWORK, paramUpdated, nowtext, dbg)
    end
    safeSetUserParam(CBUS_NETWORK, paramName, value, dbg)
  end

  -- ── Derived values ─────────────────────────────────────────────────────────
  local temp     = status.common["OutdoorTemp"]
  local humidity = status.common["OutdoorHumidity"]
  local dewPoint = status.common["DewPoint"]
  local wind     = status.common["WindSpeed"]
  local gust     = status.common["GustSpeed"]
  local pressure = status.common["RelBarometric"]
  local uvi      = status.common["UVI"]

  local feelsLike       = calcFeelsLike(temp, humidity, wind)
  local comfortZone     = calcComfortZone(temp, humidity)
  local beaufort        = calcBeaufort(wind)
  local beaufortDesc    = beaufort ~= nil and BEAUFORT_DESC[beaufort] or nil
  local gustAlert       = calcGustAlert(gust)
  local uvBurnTime      = calcUVBurnTime(uvi)
  local uvLabel         = calcUVLabel(uvi)
  local dewPointComfort = calcDewPointComfort(dewPoint)
  local frostRisk       = calcFrostRisk(temp, dewPoint)
  local condensRisk     = calcCondensationRisk(temp, dewPoint)
  local pressureTrend, pressureRate = calcPressureTrend(pressure)
  local weatherOutlook  = calcWeatherOutlook(pressureTrend, pressureRate)

  safeSetUserParam(CBUS_NETWORK, "FeelsLike",        feelsLike,      dbg)
  safeSetUserParam(CBUS_NETWORK, "ComfortZone",      comfortZone,    dbg)
  safeSetUserParam(CBUS_NETWORK, "Beaufort",         beaufort,       dbg)
  safeSetUserParam(CBUS_NETWORK, "BeaufortDesc",     beaufortDesc,   dbg)
  safeSetUserParam(CBUS_NETWORK, "GustAlert",        gustAlert,      dbg)
  safeSetUserParam(CBUS_NETWORK, "UVBurnTime",       uvBurnTime,     dbg)
  safeSetUserParam(CBUS_NETWORK, "UVLabel",          uvLabel,        dbg)
  safeSetUserParam(CBUS_NETWORK, "DewPointComfort",  dewPointComfort,dbg)
  safeSetUserParam(CBUS_NETWORK, "FrostRisk",        frostRisk,      dbg)
  safeSetUserParam(CBUS_NETWORK, "CondensationRisk", condensRisk,    dbg)
  safeSetUserParam(CBUS_NETWORK, "PressureTrend",    pressureTrend,  dbg)
  safeSetUserParam(CBUS_NETWORK, "PressureRate",     pressureRate,   dbg)
  safeSetUserParam(CBUS_NETWORK, "WeatherOutlook",   weatherOutlook, dbg)
  safeSetUserParam(CBUS_NETWORK, "LastUpdated",      nowtext,        dbg)

  -- ── Debug table ────────────────────────────────────────────────────────────
  if dbg then
    local SEP   = string.rep("-", 34)
    local lines = {
      "ECOWITT values @ " .. nowtext, SEP,
      string.format("  %-22s %s", "Parameter", "Value"), SEP,
    }

    appendSortedRows(lines, status.common, "")
    appendSortedRows(lines, status.rain,   "")

    local soilFlat = {}
    for ch, v in pairs(status.soil) do soilFlat["Soil" .. ch] = v end
    appendSortedRows(lines, soilFlat, "")

    lines[#lines + 1] = SEP
    lines[#lines + 1] = string.format("  %-22s", "--- Derived ---")
    lines[#lines + 1] = SEP

    local derivedRows = {
      { "FeelsLike",        feelsLike },
      { "ComfortZone",      comfortZone },
      { "Beaufort",         beaufort },
      { "BeaufortDesc",     beaufortDesc },
      { "GustAlert",        gustAlert },
      { "UVBurnTime",       uvBurnTime and (uvBurnTime .. " min") or nil },
      { "UVLabel",          uvLabel },
      { "DewPointComfort",  dewPointComfort },
      { "FrostRisk",        frostRisk },
      { "CondensationRisk", condensRisk },
      { "PressureTrend",    pressureTrend },
      { "PressureRate",     pressureRate and (pressureRate .. " hPa") or nil },
      { "WeatherOutlook",   weatherOutlook },
    }
    for _, row in ipairs(derivedRows) do
      lines[#lines + 1] = string.format("  %-22s %s", row[1], tostring(row[2]))
    end

    lines[#lines + 1] = SEP
    log(table.concat(lines, "\n"))
  end
end
