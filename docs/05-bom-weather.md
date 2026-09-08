# Integration Research: BOM Weather (Bureau of Meteorology)

**Integration #:** 5  
**Device / Service:** Australian Bureau of Meteorology — forecast weather data  
**Last Researched:** 2025  

---

## 1. Integration Method

**Cloud API** — BOM provides several data access methods:

### Option A: BOM FTP / HTTP Data Files (Legacy, Free)
BOM publishes machine-readable weather observations and forecasts as XML/JSON files via their public FTP and HTTP servers. Key endpoints:
- `http://www.bom.gov.au/fwo/<product_id>.json` — JSON weather observations for a station
- `ftp://ftp.bom.gov.au/anon/gen/fwo/<product_id>.xml` — forecast XML files

Product IDs are state-specific (e.g. `IDV60901` = Victoria observations, `IDV10450` = Melbourne forecast). These are publicly available, no authentication required, and used widely in open-source Home Assistant BOM integrations.

**Recommended:** Use JSON observations endpoint over HTTP — this is directly consumable from Lua with `socket.http` and `json.decode`.

Example observation URL:
```
http://www.bom.gov.au/fwo/IDV60901.json
```

Example forecast URL:
```
http://www.bom.gov.au/fwo/IDV10450.json
```

### Option B: BOM API (Beta/Commercial — api.weather.bom.gov.au)
BOM launched a developer API at `https://api.weather.bom.gov.au/v1/`. This provides structured forecasts, warnings, and observations. No API key is currently required for basic access. This is the API used by the official BOM app.

Key endpoints:
- `GET /v1/locations/<geohash>/forecasts/daily` — 7-day daily forecast
- `GET /v1/locations/<geohash>/forecasts/3-hourly` — 3-hourly forecast
- `GET /v1/locations/<geohash>/observations` — current observations for nearest station

The `geohash` for a location can be found via:
- `GET /v1/locations?search=<suburb>` — returns geohash and station details

**Recommended approach:** **BOM API v1** (Option B) — structured, JSON, no authentication, and provides clean forecast data (max/min temperature, rain probability, condition icons, UV index, sunrise/sunset). Use `ssl.https` + `ltn12` as per the Panasonic gold-standard HTTPS pattern.

---

## 2. Connectivity Requirement

☁️ **Internet connection required.**  
BOM data is served from BOM's public servers. There is no local copy or offline fallback. If the internet is unavailable, cached values from the last successful poll will remain in User Params until the next successful fetch.

---

## 3. Authentication Method

**No authentication required** for either the legacy FTP/HTTP data files or the current BOM API v1.

The BOM API may introduce authentication in future — monitor for changes. No API key, OAuth, or account registration is currently required.

---

## 4. Polling vs. Event-Driven

**Polling** — low frequency appropriate.

BOM observation data updates every 10–30 minutes depending on the station. Forecast data updates approximately every 6 hours. Recommended polling intervals:
- **Observations:** Every 10 minutes (appropriate for current conditions display)
- **Forecasts:** Every 60 minutes (data does not change more frequently)

A single resident script can fetch both observations and forecast data on the same timer. To avoid unnecessary cloud requests, implement a counter or timestamp check so forecast data is only re-fetched every N cycles (e.g. once per hour if the script runs every 10 minutes).

---

## 5. Available Data / Controllable Parameters

### Read Only (BOM is read-only)

**Current Observations (from nearest station):**

| Metric | Unit | Notes |
|---|---|---|
| Air temperature | °C | |
| Apparent temperature (feels like) | °C | Provided directly by BOM |
| Dew point | °C | |
| Relative humidity | % | |
| Wind speed | km/h | |
| Wind direction | degrees / cardinal | |
| Wind gust | km/h | |
| Atmospheric pressure | hPa | |
| Rain since 9am | mm | |
| Visibility | km | Station dependent |
| Cloud cover | Oktas | Station dependent |

**Daily Forecast (7-day):**

| Metric | Unit | Notes |
|---|---|---|
| Short text forecast | String | e.g. "Mostly sunny" |
| Max temperature | °C | |
| Min temperature | °C | |
| Rain probability | % | |
| Forecast rain amount | String | e.g. "0 to 4 mm" |
| UV category | String | e.g. "Very High" |
| UV max index | Number | |
| Sunrise / Sunset | Time string | |
| Icon descriptor | String | e.g. "mostly_sunny", "rain" |

**3-Hourly Forecast:**

| Metric | Unit | Notes |
|---|---|---|
| Temperature | °C | |
| Feels like | °C | |
| Rain probability | % | |
| Wind speed | km/h | |
| Wind direction | degrees | |
| Humidity | % | |

---

## 6. Estimated Implementation Difficulty

🟡 **Easy** — BOM API v1 returns clean, well-structured JSON. The pattern is a simple HTTPS GET with `ssl.https` + `ltn12`, identical to the Panasonic authentication calls minus the auth headers.

The primary complexity is selecting the correct geohash for the location and parsing the nested JSON structure. 7-day forecast requires iterating over a forecast array — straightforward.

---

## 7. Known Limitations and Risks

- **Unofficial API** — the BOM API v1 (`api.weather.bom.gov.au`) is publicly accessible but not formally documented with a developer agreement. BOM may introduce authentication, rate limits, or restructure endpoints without notice.
- **Legacy FTP endpoint availability** — BOM has signalled intent to retire legacy FTP/HTTP data files. The API v1 is the more future-proof option.
- **Geohash required** — the API v1 requires a location geohash rather than a station code. The geohash must be discovered once (via the search endpoint or a geohash tool) and hardcoded in the configuration.
- **Nearest station** — observations are from the nearest weather station, which may be several kilometres from the home. Ecowitt provides hyper-local data; BOM provides a broader regional picture and UV/forecast data.
- **Rate limits** — BOM does not publish rate limits for the API. Polling more frequently than every 10 minutes is not recommended.
- **Internet dependency** — if BOM is unavailable, cached values remain stale. Implement a `LastUpdated` timestamp so the dashboard can indicate data age.
- **HTTPS on 5500AC** — requires `ssl.https` + `ltn12`, which are available on 5500AC firmware.

---

## 8. Recommended C-Bus Group Address Strategy

Forecast and observation data stored as User Parameters. Decimal values stored as native Float parameters. String forecasts stored as String params.

Suggested naming convention:

```
BOM_CurrentTemp          (Float, °C)
BOM_FeelsLike            (Float, °C)
BOM_Humidity             (Number, %)
BOM_WindSpeed            (Number, km/h)
BOM_WindDirection        (Number, degrees)
BOM_WindGust             (Number, km/h)
BOM_Pressure             (Float, hPa)
BOM_RainSince9am         (Float, mm)
BOM_Forecast_Today       (String — "Mostly Sunny")
BOM_Forecast_TodayMax    (Number, °C)
BOM_Forecast_TodayMin    (Number, °C)
BOM_Forecast_TodayRainPct (Number, %)
BOM_Forecast_Tomorrow    (String)
BOM_Forecast_TomorrowMax (Number, °C)
BOM_Forecast_TomorrowMin (Number, °C)
BOM_Forecast_UV          (String — "Very High")
BOM_Forecast_Sunrise     (String — "06:42")
BOM_Forecast_Sunset      (String — "20:15")
BOM_LastUpdated          (String — timestamp)
```

---

## 9. Dependencies on Gold-Standard Patterns

| Pattern | Source | Applicability |
|---|---|---|
| `ssl.https` + `ltn12` HTTPS GET | Panasonic gold-standard | Required — BOM API uses HTTPS |
| `safeSetUserParam` | All gold-standard | Required |
| `isDebuggingEnabled` cached per poll | All gold-standard | Required |
| `_missingParamWarned` | All gold-standard | Required |
| `extractNumber()` | Ecowitt skill | Useful for parsing numeric strings |
| Config table with network, prefix, debug | All gold-standard | Standard resident script pattern |

---

## Action Required

1. **Determine location geohash** — use `GET https://api.weather.bom.gov.au/v1/locations?search=<suburb>` once to find the correct geohash for the home location. Hardcode in script configuration.
2. **Confirm nearest observation station** — check the `observations` endpoint to verify the station distance and suitability.
3. **Decide polling split** — observations every 10 minutes, forecast refresh every 60 minutes (can be managed with a poll counter in module state).
4. **Write integration script** in a future session — the research here is sufficient to proceed.
