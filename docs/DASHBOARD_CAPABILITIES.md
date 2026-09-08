# Dashboard Capabilities Summary

This document summarises all metrics and controls that will be available on the smart home dashboard once each integration is implemented. It serves as the definitive data model for dashboard design.

**Key:**
- 🏠 Local — operates without internet connection
- ☁️ Cloud — requires internet connection
- 📖 Read-only — monitoring only
- ✏️ Read/Write — monitoring and control
- ⚠️ Uncertain — functionality pending further investigation or infrastructure

---

## Dashboard Categories

### 1. Climate Control

| Integration | Local/Cloud | R/W | Capabilities |
|---|---|---|---|
| **Panasonic Heating** (Comfort Cloud) | ☁️ | ✏️ | Power on/off, target temperature, inside/outside temperature, operation mode (Heat/Cool/Auto/Dry/Fan), fan speed, eco mode (Powerful/Quiet), vertical/horizontal swing, Nanoe purification, EcoNavi, iAuto-X, inside cleaning, HVAC action state (Heating/Cooling/Idle/Off), active zone count, per-zone on/off and damper %, per-zone temperature, daily energy (kWh), heating/cooling energy split (kWh), extrapolated live power (W), last updated timestamp |
| **Unisenza Radiators** | 🏠 | ✏️ | Per-room current temperature (×10 °C), per-room setpoint (×10 °C, writable), hold type (Schedule/Permanent/Eco/Off), heating demand (0–100%), online/offline state, device count, poll status |

**Panasonic — C-Bus UserParams:**
```
AC_Power, AC_TargetTemp, AC_InsideTemp, AC_OutsideTemp
AC_Mode, AC_Mode_Text, AC_FanSpeed, AC_FanSpeed_Text
AC_EcoMode, AC_EcoMode_Text, AC_SwingUD, AC_SwingLR
AC_HVACAction, AC_HVACAction_Text, AC_Nanoe, AC_EcoNavi, AC_IAutoX
AC_Zone1_Power … AC_ZoneN_Power, AC_Zone1_Damper … AC_ZoneN_Damper
AC_Zone1_Temp … AC_ZoneN_Temp, AC_ActiveZones
AC_Daily_kWh, AC_Heating_kWh, AC_Cooling_kWh, AC_CurrentPower_W
AC_LastUpdated
```

**Unisenza — C-Bus UserParams (per radiator, e.g. "Romy"):**
```
Romy_CurrentTemp, Romy_Setpoint, Romy_HoldType, Romy_Demand, Romy_Online
Unisenza_Status, Unisenza_LastUpdated, Unisenza_DeviceCount
```

---

### 2. Security

| Integration | Local/Cloud | R/W | Capabilities |
|---|---|---|---|
| **Inception Alarm** | 🏠 | ✏️ | Area arm state (Armed/Disarmed/Armed Away/Stay/Sleep, alarm active, entry/exit delay), door lock/open/closed state, input/zone state (Sealed/Active/Tamper/Isolated), output state (On/Off), live security and access review events (description + who + timestamp), arm/disarm activity feedback (Success/Failed) |

**Control from C-Bus:** Arm Away, Arm Stay, Arm Sleep, Disarm, Lock door, Unlock door, Open door, Timed unlock, Output on/off/toggle/pulse.

**Inception — C-Bus UserParams:**
```
alarmstate, garagedoor, security_zone1 … security_zoneN
cctv_output (and other output params)
last_alarm_event, alarmstate_detail
Debug Logging
```

---

### 3. Energy & Solar

| Integration | Local/Cloud | R/W | Capabilities |
|---|---|---|---|
| **Sigenergy** (Modbus TCP) | 🏠 | ✏️ | Current PV power (W), today's PV generation (kWh), battery SOC (%), battery SOH (%), battery charge/discharge power (W), grid import/export power (W), total house load (W), EMS work mode (Self-Consumption/Backup/Feed-in/ToU), on-grid/off-grid status, daily import/export energy (kWh), derived: self-consumption %, solar fraction % |
| **SolCast** | ☁️ | 📖 | Current period forecast PV generation (kW), today total forecast (kWh), remaining today forecast (kWh), tomorrow total (kWh), peak generation time, peak kW, 10th/90th percentile confidence range, forecast age (hours since last fetch) |
| **Panasonic HVAC energy** | ☁️ | 📖 | Daily HVAC energy (kWh), heating vs cooling split, extrapolated power draw (W) — see Climate Control section |

**Sigenergy — C-Bus UserParams:**
```
Solar_PV_Power_W, Solar_PV_Daily_kWh
Solar_Battery_SOC, Solar_Battery_SOH, Solar_Battery_Power_W
Solar_Grid_Power_W, Solar_Load_Power_W
Solar_EMS_Mode, Solar_OnGrid
Solar_SelfConsumption_Pct, Solar_SolarFraction_Pct
Solar_LastUpdated
```

**SolCast — C-Bus UserParams:**
```
SolCast_Now_kW, SolCast_TodayTotal_kWh, SolCast_TodayRemaining_kWh
SolCast_TomorrowTotal_kWh, SolCast_PeakTime, SolCast_PeakKW
SolCast_Confidence10_kW, SolCast_Confidence90_kW
SolCast_LastFetched, SolCast_ForecastAge_Hrs
```

---

### 4. Weather

| Integration | Local/Cloud | R/W | Capabilities |
|---|---|---|---|
| **Ecowitt Weather Station** | 🏠 | 📖 | Outdoor temperature, humidity, feels like (derived), dew point (derived), wind speed/direction/gust, gust alert, rain rate, daily/weekly/monthly rainfall, pressure (absolute/relative), pressure trend (derived), solar radiation, UV index, plus optional: soil moisture per channel, lightning distance/count, CO₂, PM2.5/PM10 |
| **BOM Weather** | ☁️ | 📖 | Current observations: temperature, apparent temperature, humidity, wind speed/direction/gust, pressure, rain since 9am. 7-day forecast: max/min temp, short text, rain probability, UV category/index, sunrise/sunset. 3-hourly forecast: temperature, feels like, rain probability, wind |

**Ecowitt — C-Bus UserParams:**
```
Weather_OutdoorTemp, Weather_OutdoorHumidity, Weather_FeelsLike, Weather_DewPoint
Weather_WindSpeed, Weather_WindDirection, Weather_WindGust, Weather_GustAlert
Weather_RainRate, Weather_RainDaily, Weather_Pressure, Weather_PressureTrend
Weather_SolarRadiation, Weather_UVIndex, Weather_LastUpdated
Soil1_Moisture … SoilN_Moisture (if sensors fitted)
```

**BOM — C-Bus UserParams:**
```
BOM_CurrentTemp, BOM_FeelsLike, BOM_Humidity, BOM_WindSpeed, BOM_WindDirection
BOM_Forecast_Today, BOM_Forecast_TodayMax, BOM_Forecast_TodayMin
BOM_Forecast_TodayRainPct, BOM_Forecast_Tomorrow, BOM_Forecast_TomorrowMax
BOM_Forecast_UV, BOM_Forecast_Sunrise, BOM_Forecast_Sunset
BOM_LastUpdated
```

---

### 5. Appliances

| Integration | Local/Cloud | R/W | Capabilities |
|---|---|---|---|
| **Asko Washing Machine** (ConnectLife) | ☁️ | ✏️ | Machine state (standby/running/pause/program_finished), current programme phase (prewash/wash/rinsing/spinning/finished), selected programme name, time remaining (min), current water temperature (°C), door open, wash finished flag, filter/detergent warnings, error codes, weekly energy (kWh) + water (litres) via `energyConsumptionCurve` — *Protocol fully known: Gigya SSO → HijuConn OAuth2 → signed gateway. ⚠️ RSA PKCS1v15 signing on LM is the implementation gate.* |
| **Gaggenau Oven** (Home Connect Local) | 🏠 ⚠️ | ✏️ | Operation state (Inactive/Ready/Run/Finished/Error), door state (Closed/Open), current cavity temperature, active programme, time remaining, preheat complete, alarm elapsed, remote control active flag, child lock, oven light ⚠️ *WebSocket direct from 5500AC using LM `user.websocket` library. One-time profile download required. PSK/TLS mode support TBD. Remote start requires physical user authorisation.* |
| **Gaggenau Cooktop** (Home Connect Local) | 🏠 ⚠️ | ✏️ | Operation state, local control active, child lock ⚠️ *WebSocket direct from 5500AC. One-time profile download required.* |
| **Reclaim Hot Water** | ☁️ | ✏️ | Tank water temperature (°C), ambient temperature (°C), outlet/inlet temperatures (°C), power (W), current (A), pump/compressor active, boost mode active, operating mode (Mode 1–8 incl. PV Connectivity), compressor speed (RPM), total hours/starts — *Protocol fully known: AWS IoT Core MQTT + Modbus register map. ⚠️ Needs Lua MQTT client on 5500AC confirmed.* |

**Washing Machine — C-Bus UserParams:**
```
Asko_DeviceStatus, Asko_ProgramPhase, Asko_SelectedProgram
Asko_TimeRemaining, Asko_WaterTemp, Asko_DoorOpen
Asko_WashFinished, Asko_FilterWarning, Asko_DetergentWarning
Asko_EnergyKwh, Asko_WaterLitres, Asko_LastUpdated
```

**Oven — C-Bus UserParams:**
```
Oven_OperationState, Oven_DoorState, Oven_CurrentTemp
Oven_Program, Oven_TimeRemaining, Oven_PreheatDone, Oven_AlarmElapsed, Oven_RemoteAllowed
Oven_LastUpdated

Cooktop_OperationState, Cooktop_LastUpdated
```

**Hot Water — C-Bus UserParams:**
```
ReclaimHW_TankTemp, ReclaimHW_AmbientTemp, ReclaimHW_OutletTemp
ReclaimHW_Power, ReclaimHW_PumpActive, ReclaimHW_BoostActive
ReclaimHW_Mode, ReclaimHW_CompSpeed, ReclaimHW_Hours, ReclaimHW_LastUpdated
```

---

### 6. Entertainment

| Integration | Local/Cloud | R/W | Capabilities |
|---|---|---|---|
| **Sonos** | 🏠 | ✏️ | Per-room playback state (Playing/Paused/Idle), per-room volume (0–100), per-room muted state, now-playing track title and artist, streaming service name, active rooms count |
| **LG TV** | 🏠 | ✏️ | Power state (Active/Standby), current app (Netflix/YouTube/Live TV/HDMI etc.), volume (0–100), muted state, on-duration (derived). Full control: power off, input switch, volume, launch app, play/pause. Via WebSocket SSAP direct from 5500AC — one-time TV pairing required. |
| **Apple TV** | 🏠 ⚠️ | ✏️ ⚠️ | Power state, current app, playback state (Playing/Paused/Idle), media title, media type ⚠️ *MRP protocol is custom binary (not WebSocket) — pyatv proxy service on LAN device still required* |

**Sonos — C-Bus UserParams:**
```
Sonos_Lounge_State, Sonos_Lounge_Volume, Sonos_Lounge_Track, Sonos_Lounge_Service
Sonos_Kitchen_State, Sonos_Kitchen_Volume
Sonos_ActiveRooms, Sonos_LastUpdated
```

**LG TV — C-Bus UserParams:**
```
LG_TV_Power, LG_TV_App, LG_TV_Volume, LG_TV_Muted, LG_TV_OnDuration, LG_TV_LastUpdated
```

**Apple TV — C-Bus UserParams:**
```
AppleTV_Power, AppleTV_App, AppleTV_PlayState, AppleTV_MediaTitle, AppleTV_LastUpdated
```

---

### 7. Presence

| Integration | Local/Cloud | R/W | Capabilities |
|---|---|---|---|
| **Ubiquiti Dream Machine** | 🏠 | 📖 | Per-person home/away state, last seen timestamp, connected AP (rough location), RSSI, WAN internet status (Up/Down), WAN latency (ms), connected client count, network subsystem health |

**Presence — C-Bus UserParams:**
```
Person_Kyle_Home, Person_Kyle_LastSeen
Person_[Name]_Home, Person_[Name]_LastSeen  (one set per tracked person)
Network_WAN_Status, Network_WAN_Latency, Network_Client_Count
Network_LastUpdated
```

---

### 8. Irrigation

| Integration | Local/Cloud | R/W | Capabilities |
|---|---|---|---|
| **OpenSprinkler** | 🏠 | ✏️ | Water level / weather adjustment (%), rain sensor state, rain delay (seconds), per-zone active state (0/1), last programme run description (zone, duration, time), manual zone run/stop |

**OpenSprinkler — C-Bus UserParams:**
```
Irrigation_WaterLevel, Irrigation_RainSensor, Irrigation_RainDelay
Irrigation_Zone1_Active … Irrigation_ZoneN_Active
Irrigation_LastRun, Irrigation_LastUpdated
```

---

### 9. Lighting & Switches

| Integration | Local/Cloud | R/W | Capabilities |
|---|---|---|---|
| **Shelly Devices** | 🏠 | ✏️ | Per-device relay on/off state, physical input/button state, power consumption (W), energy consumption (Wh), voltage (V), current (A) — for power metering models. Per temperature sensor: temperature (°C), humidity (%), battery level |

**Shelly — C-Bus UserParams:**
```
Shelly_[Name]_Power, Shelly_[Name]_Watts, Shelly_[Name]_Energy_Wh
Shelly_TempSensor[N]_Temp, Shelly_TempSensor[N]_Humid
Shelly_LastUpdated
```

---

## Integration Status Summary

| # | Integration | Category | Local/Cloud | R/W | Difficulty | Status |
|---|---|---|---|---|---|---|
| 1 | Panasonic Heating | Climate | ☁️ | ✏️ | ✅ Already implemented | Production-ready |
| 2 | Unisenza Radiators | Climate | 🏠 | ✏️ | ✅ Already implemented | Production-ready |
| 3 | Inception Alarm | Security | 🏠 | ✏️ | ✅ Already implemented | Production-ready |
| 4 | Ecowitt Weather | Weather | 🏠 | 📖 | Easy | Prototype exists — needs rewrite |
| 5 | BOM Weather | Weather | ☁️ | 📖 | Easy | Not yet implemented |
| 6 | Shelly Devices | Lighting | 🏠 | ✏️ | Easy–Medium | Not yet implemented |
| 7 | Asko Washing Machine | Appliances | ☁️ | ✏️ | Hard | Protocol fully known (Gigya → HijuConn OAuth2 + RSA-signed gateway + 003.yaml property map). ⚠️ RSA signing on LM is the implementation gate |
| 8 | Gaggenau Home Connect (Local) | Appliances | 🏠 ⚠️ | ✏️ | Medium | Not yet implemented — profile download + WebSocket message format mapping needed |
| 9 | Ubiquiti UDM | Presence | 🏠 | 📖 | Medium | Not yet implemented |
| 10 | LG TV | Entertainment | 🏠 | ✏️ | Easy–Medium | Not yet implemented — WebSocket SSAP direct from 5500AC, one-time pairing required |
| 11 | Apple TV | Entertainment | 🏠 ⚠️ | ✏️ | Medium (proxy) | Not yet implemented — proxy required |
| 12 | Sonos | Entertainment | 🏠 | ✏️ | Easy–Medium | Prototype exists — needs rewrite |
| 13 | OpenSprinkler | Irrigation | 🏠 | ✏️ | Easy | Prototype exists — needs rewrite |
| 14 | Reclaim Hot Water | Appliances | ☁️ | ✏️ | Medium | Protocol + transport fully resolved. `mosquitto` binding with `tls_set` confirmed on LM. One-time cert issuance only pre-requisite |
| 15 | Sigenergy | Energy | 🏠 | ✏️ | Medium | Modbus profile complete — LM config needed |
| 16 | SolCast | Energy | ☁️ | 📖 | Easy | Not yet implemented |

---

## Recommended Implementation Order

Based on difficulty, value, and dependencies:

### Phase 1 — Quick Wins (existing foundations to upgrade)
1. **Ecowitt** — rewrite `ecowitt.lua` to gold-standard → high daily value
2. **OpenSprinkler** — rewrite `OS_UserLibrary.lua` to gold-standard + extend to all zones
3. **Sonos** — rewrite `Sonos_UserLibrary.lua` to gold-standard

### Phase 2 — New Local Integrations (no cloud, no infrastructure)
4. **BOM Weather** — simple HTTPS GET, no auth, high dashboard value
5. **Shelly Devices** — inventory required first; then straightforward implementation
6. **Ubiquiti UDM** — presence detection; high automation value

### Phase 3 — Energy (LM Modbus config + derived Lua)
7. **Sigenergy** — configure LogicMachine Modbus TCP module; write derived values Lua script
8. **SolCast** — simple API key auth; couple with Sigenergy for self-consumption planning

### Phase 4 — Cloud Appliances (OAuth2 + token management)
9. **Gaggenau Home Connect** — developer account + OAuth2 helper; well-documented API
10. **Asko Washing Machine** — protocol + property map fully known; RSA signing gate must be resolved first (on-device `crypto`/`ffi` or thin proxy)

### Phase 5 — Infrastructure-Dependent (proxy services)
11. **Apple TV** — requires pyatv proxy service
12. **LG TV** — ping-only first; proxy if richer data needed

### Phase 6 — Research-Dependent (pending investigation)
13. **Reclaim Hot Water** — protocol + transport fully resolved; can be implemented now (one-time cert issuance required first)

---

## Cloud Dependency Register

| Integration | Cloud Required | Fallback if Cloud Unavailable |
|---|---|---|
| Panasonic Heating | Yes — always | None — no local API |
| Unisenza Radiators | No | N/A |
| Inception Alarm | No | N/A |
| Ecowitt | No | N/A |
| BOM Weather | Yes — always | None — cached values remain stale |
| Shelly Devices | No | N/A |
| Asko Washing Machine | Yes — always | None |
| Gaggenau Home Connect (Local) | No (runtime) | N/A — fully local once profiles downloaded |
| Ubiquiti UDM | No | N/A |
| LG TV (ping) | No | N/A |
| Apple TV (proxy) | No | N/A |
| Sonos | No | N/A |
| OpenSprinkler | No | N/A |
| Reclaim Hot Water | Yes — AWS IoT Core MQTT | None — no local LAN fallback |
| Sigenergy | No | N/A |
| SolCast | Yes — always | Cached forecast remains (data ages) |

---

## Notes

- **Dashboard layout design** is a separate future task — this document defines the data model only, not the visual layout.
- Temperature values stored as integers ×10 in all C-Bus UserParams to preserve decimal precision.
- All timestamps stored as formatted strings (e.g. `"05 Jun 2025, 14:32"`).
- All "uncertain" (⚠️) capabilities require additional investigation before implementation commitments can be made.
- C-Bus UserParam names above are suggestions — review and adjust naming conventions before implementation to ensure consistency across the full dashboard.
