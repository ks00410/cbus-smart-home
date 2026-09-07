# Integration Research: Ecowitt Weather Station

**Integration #:** 4  
**Device / Service:** Ecowitt personal weather station  
**Last Researched:** 2025  

---

## 1. Integration Method

**Local LAN** — two complementary approaches, both available:

### Option A: HTTP Push (Ecowitt Custom Server Protocol)
The Ecowitt gateway/base station can be configured to push data to a custom HTTP endpoint at a user-defined interval (as low as 16 seconds). The data is `POST`ed as `application/x-www-form-urlencoded` key-value pairs to any reachable server on the LAN. The 5500AC can receive this push if it has an HTTP listener, but LogicMachine does not natively expose a custom HTTP endpoint for incoming POST data.

### Option B: HTTP Pull (Ecowitt LAN API)
The Ecowitt gateway also exposes a local HTTP API at `http://<gateway_ip>/get_livedata_info`. A GET request returns a JSON payload with all sensor data. This is the approach used in the gold-standard Ecowitt integration (`ecowitt.lua` referenced in the Inception repository).

**Recommended approach:** **HTTP Pull** (Option B) — matches the resident poll pattern used across all gold-standard integrations and does not require any listener infrastructure on the 5500AC.

**Assessment:** An Ecowitt integration exists in the Inception repository (`ecowitt.lua`). Review that file in a future session to determine if it is gold-standard quality or prototype grade. Based on repository positioning it appears to be a prototype — a new integration script following gold-standard conventions should be authored when ready.

---

## 2. Connectivity Requirement

🏠 **Fully local — no internet connection required.**  
The `/get_livedata_info` API is served directly by the Ecowitt gateway on the LAN. No Ecowitt cloud account or internet access is required for local polling.

> **Note:** The Ecowitt gateway may require an initial Wi-Fi setup via the Ecowitt app (cloud account optional). Once configured and connected to your LAN, all local API polling is independent of cloud services.

---

## 3. Authentication Method

**No authentication required** for the local LAN API. The `GET /get_livedata_info` endpoint returns data without any API key, token, or credentials.

> If Ecowitt cloud API is used as an alternative (not recommended for this integration), an application key and API key are required. The local API is always preferred.

---

## 4. Polling vs. Event-Driven

**Polling** — 60-second resident script interval recommended.

The Ecowitt gateway updates its internal sensor data every 16–60 seconds depending on sensor type and configuration. Polling at 60 seconds is appropriate for weather data and avoids unnecessary load on the gateway. A 30-second interval is also reasonable if more responsive wind gust alerts are desired.

---

## 5. Available Data / Controllable Parameters

### Read Only (Weather Station is read-only)

Sensor availability varies by Ecowitt station model and attached sensors. All values should be treated as potentially absent and handled with `nil` safety.

**Indoor:**

| Metric | Unit | Notes |
|---|---|---|
| Indoor temperature | °C | Indoor console sensor |
| Indoor humidity | % | |

**Outdoor:**

| Metric | Unit | Notes |
|---|---|---|
| Outdoor temperature | °C | |
| Outdoor humidity | % | |
| Feels like temperature (derived) | °C | Heat index / wind chill / apparent temp |
| Dew point (derived) | °C | |

**Wind:**

| Metric | Unit | Notes |
|---|---|---|
| Wind speed | km/h or knots | |
| Wind direction | degrees | 0–360 |
| Wind gust | km/h or knots | |
| Gust alert (derived) | 0/1 | Threshold configurable |

**Rain:**

| Metric | Unit | Notes |
|---|---|---|
| Rain rate | mm/hr | Current rain intensity |
| Daily rainfall | mm | Resets at midnight |
| Weekly rainfall | mm | |
| Monthly rainfall | mm | |
| Total rainfall | mm | Since last reset |

**Solar / UV:**

| Metric | Unit | Notes |
|---|---|---|
| Solar radiation | W/m² | |
| UV index | 0–11+ | |

**Pressure:**

| Metric | Unit | Notes |
|---|---|---|
| Absolute pressure | hPa | Raw barometric |
| Relative pressure | hPa | Sea-level adjusted |
| Pressure trend (derived) | String | Rising / Falling / Steady |
| Pressure trend rate (derived) | hPa | Change over configured window |

**Soil / Additional Sensors (optional, model-dependent):**

| Metric | Unit | Notes |
|---|---|---|
| Soil moisture channels 1–N | % | Ecowitt WH51 sensors |
| Soil temperature channels | °C | |
| Leaf wetness | % | |
| Lightning strike count | count | WH57 sensor |
| Lightning distance | km | |
| CO₂ concentration | ppm | WH45 indoor air quality sensor |
| PM2.5 / PM10 air quality | μg/m³ | |

---

## 6. Estimated Implementation Difficulty

🟡 **Easy** — the Ecowitt local API is well-documented, returns clean JSON, requires no authentication, and follows a simple request/response pattern identical to OpenSprinkler and Unisenza.

A full gold-standard script can be written in a single session, modelling the sensor map and derived value functions on the gold-standard skill patterns (pressure trend with rolling window, feels-like calculation, gust alert threshold, etc.).

---

## 7. Known Limitations and Risks

- **Prototype reference exists** — `ecowitt.lua` in the Inception repository is available as a reference but may not follow gold-standard quality conventions. Review carefully before reuse.
- **Sensor availability varies** — not all metrics are available on all Ecowitt models. The script must handle absent fields gracefully with nil safety throughout.
- **Unit string stripping** — the Ecowitt API includes unit strings in values (e.g. `"46%"`, `"1.94 knots"`). The `extractNumber()` utility function from the gold-standard skill handles this.
- **Gateway IP stability** — assign a DHCP reservation for the gateway to prevent IP changes.
- **Midnight rain reset** — `daily_rainfall` resets at local midnight; derived values using daily totals should account for this.
- **No write capability** — weather station is read-only.

---

## 8. Recommended C-Bus Group Address Strategy

All weather data stored as User Parameters on network 0. Temperature and pressure values stored as integers ×10 where decimal precision is needed.

Suggested naming convention:

```
Weather_OutdoorTemp       (Number, ×10 — e.g. 214 = 21.4°C)
Weather_OutdoorHumidity   (Number, %)
Weather_FeelsLike         (Number, ×10 — derived)
Weather_DewPoint          (Number, ×10 — derived)
Weather_WindSpeed         (Number, ×10 knots or km/h)
Weather_WindDirection     (Number, degrees)
Weather_WindGust          (Number, ×10)
Weather_GustAlert         (Number, 0/1)
Weather_RainRate          (Number, ×10 mm/hr)
Weather_RainDaily         (Number, ×10 mm)
Weather_Pressure          (Number, ×10 hPa)
Weather_PressureTrend     (String — "Rising Rapidly" etc.)
Weather_SolarRadiation    (Number, W/m²)
Weather_UVIndex           (Number, ×10)
Weather_LastUpdated       (String)
Soil1_Moisture            (Number, %)
Soil2_Moisture            (Number, %)
... (per soil sensor channel)
```

---

## 9. Dependencies on Gold-Standard Patterns

| Pattern | Source | Applicability |
|---|---|---|
| `socket.http` local LAN polling | Inception, Unisenza | Direct |
| `extractNumber()` unit string stripping | Ecowitt skill / gold-standard | Required — API values include unit strings |
| `safeSetUserParam` | All gold-standard | Required |
| `isDebuggingEnabled` cached per poll | All gold-standard | Required |
| `_missingParamWarned` | All gold-standard | Required |
| Derived value functions section | Panasonic gold-standard | Pressure trend (rolling window + `_prefixed` module state), feels-like, dew point |
| ID map with unknown ID fallback | Ecowitt gold-standard skill | Sensor discovery with graceful unknown handling |
| Debug aligned table output | Ecowitt gold-standard skill | `appendSortedRows()` pattern |

---

## Action Required

1. **Confirm Ecowitt model** — determine which sensors are attached (soil, lightning, CO₂, etc.) to plan the full parameter list.
2. **Review existing `ecowitt.lua`** in the Inception repository — assess quality and decide whether to refactor or rewrite to gold-standard.
3. **Write gold-standard integration script** in a future session — the research here is sufficient to proceed directly to implementation.
4. **Confirm gateway IP** and assign DHCP reservation.
