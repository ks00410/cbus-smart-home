# C-Bus Measurement Application — Integration Assessment

**Application address:** 228  
**Purpose:** Transmit physical measurement values (temperature, power, flow, etc.) across the C-Bus network so they can be displayed on C-Bus touchscreens, logged by C-Bus schedulers, and used as triggers in C-Bus rules — without requiring a third-party visualisation layer.

---

## How it works in Lua

The LogicMachine/5500AC Lua API provides a dedicated function:

```lua
SetCBusMeasurement(network, deviceId, channelId, value, unitCode)
```

| Argument | Type | Notes |
|---|---|---|
| `network` | number | C-Bus network index (0 = first network) |
| `deviceId` | number | Device ID configured in C-Bus Commission software (0–254) |
| `channelId` | number | Channel ID on that device (0–255) |
| `value` | number | The physical measurement value (raw float — no scaling needed) |
| `unitCode` | number | Unit type code (see table below) |

Values are passed as raw Lua numbers. The application handles the encoding for C-Bus transmission — there is no manual ×10 or ×100 scaling needed.

To clear a measurement object (e.g. when a device is offline):

```lua
clearObject("0/228/<deviceId>/<channelId>")
```

### Standard unit codes (app 228)

| Code | Unit | Typical use in this project |
|---|---|---|
| `0x00` | °C | Temperatures |
| `0x01` | Amps | Electrical current |
| `0x07` | Hertz | Frequency |
| `0x08` | Joules | Energy |
| `0x10` | Lux | Light level |
| `0x19` | Pascal | Pressure (hPa = Pa × 100) |
| `0x1A` | % | Percentage (humidity, SOC, etc.) |
| `0x1B` | Watts | Power |
| `0x1C` | Watt-hours | Energy accumulation |
| `0x1D` | m/s | Wind speed (convert from km/h or knots) |
| `0x1E` | mm | Rainfall |

*(Full list: see Schneider SpaceLogic C-Bus Commission software → Measurement Application → Standard Measurement Units)*

---

## When to use the Measurement Application vs. User Parameters

| Criterion | Measurement Application | User Parameters |
|---|---|---|
| **C-Bus touchscreen / panel display** | ✅ Native — panels show measurement values without extra wiring | ❌ Requires custom visualisation binding |
| **C-Bus schedule / rule trigger** | ✅ Can trigger rules on measurement thresholds natively | ⚠️ Possible but not native |
| **C-Bus logging / trending** | ✅ Native — measurement values are automatically logged by compatible C-Bus units | ❌ Not supported |
| **String / text values** | ❌ Numbers only (with unit code) | ✅ Strings supported |
| **Complex state** (mode, label, timestamp) | ❌ Not suited | ✅ Best fit |
| **Arbitrary naming** | ⚠️ Requires Device + Channel ID assignment in Commission software | ✅ Any string name |
| **Script complexity** | Low — one extra function call per value | None |
| **Prerequisite** | Device + Channel must be configured in C-Bus project | No C-Bus project change needed |

**Recommendation:** Use `SetCBusMeasurement` for any **continuous physical measurement** that has a real unit and would benefit from native panel display, logging, or threshold rules. Always keep the User Parameter alongside it for dashboard/string context that measurement can't carry.

---

## Integration-by-integration assessment

### ✅ Recommended: add Measurement Application writes

#### 1. Ecowitt Weather Station

Strong candidate. Temperature, pressure, humidity, rain, wind speed, UV, solar radiation all have direct measurement unit codes. Panels could show real-time weather on any C-Bus screen without a custom widget.

**Suggested device/channel allocation:**

| DeviceId | ChannelId | Param | Unit code |
|---|---|---|---|
| 10 | 0 | Outdoor Temp | 0x00 °C |
| 10 | 1 | Feels Like | 0x00 °C |
| 10 | 2 | Dew Point | 0x00 °C |
| 10 | 3 | Humidity | 0x1A % |
| 10 | 4 | Wind Speed (km/h) | 0x1D m/s (÷3.6) |
| 10 | 5 | Wind Gust (km/h) | 0x1D m/s |
| 10 | 6 | Rain Rate | 0x1E mm |
| 10 | 7 | Rain Today | 0x1E mm |
| 10 | 8 | Pressure | 0x19 Pa (×100) |
| 10 | 9 | Solar Radiation | 0x10 Lux (approx) |
| 10 | 10 | UV Index | no direct code — skip |

#### 2. BOM Weather

Useful for the subset of values that have unit codes: temperature, feels like, humidity, wind, rain. Forecast text/icons/sunrise — User Params only.

**Suggested device/channel allocation:**

| DeviceId | ChannelId | Param | Unit code |
|---|---|---|---|
| 11 | 0 | Current Temp | 0x00 °C |
| 11 | 1 | Feels Like | 0x00 °C |
| 11 | 2 | Humidity | 0x1A % |
| 11 | 3 | Wind Speed | 0x1D m/s (÷3.6) |
| 11 | 4 | Wind Gust | 0x1D m/s |
| 11 | 5 | Rain Since 9am | 0x1E mm |
| 11 | 6 | Today Max Temp | 0x00 °C |
| 11 | 7 | Today Min Temp | 0x00 °C |
| 11 | 8 | UV Index | — (no unit code; skip or use dimensionless) |

#### 3. Sigenergy (Solar / Battery / Grid)

Strong candidate. Power (W), energy (kWh), SOC %, SOH % all have clear unit codes. Real-time power flows on a C-Bus panel would be genuinely useful.

**Suggested device/channel allocation:**

| DeviceId | ChannelId | Param | Unit code |
|---|---|---|---|
| 20 | 0 | PV Power | 0x1B W |
| 20 | 1 | Battery Power | 0x1B W |
| 20 | 2 | Grid Power | 0x1B W |
| 20 | 3 | Load Power | 0x1B W |
| 20 | 4 | Battery SOC | 0x1A % |
| 20 | 5 | Battery SOH | 0x1A % |
| 20 | 6 | PV Daily kWh | 0x1C Wh (×1000) |
| 20 | 7 | Self Consumption % | 0x1A % |

#### 4. Panasonic Heating

Moderate candidate. Inside/outside temperatures, current power draw (W) are good fits. Mode, fan speed, zone states — User Params only.

**Suggested device/channel allocation:**

| DeviceId | ChannelId | Param | Unit code |
|---|---|---|---|
| 30 | 0 | Inside Temp | 0x00 °C |
| 30 | 1 | Outside Temp | 0x00 °C |
| 30 | 2 | Target Temp | 0x00 °C |
| 30 | 3 | Current Power W | 0x1B W |
| 30 | 4 | Daily Energy kWh | 0x1C Wh (×1000) |

#### 5. Unisenza Radiators

Useful for per-room temperature display on panels. Setpoint and heating demand also have obvious units.

**Suggested device/channel allocation (one device per radiator):**

| DeviceId | ChannelId | Param | Unit code |
|---|---|---|---|
| 40 + N | 0 | Room Temp (radiator N) | 0x00 °C |
| 40 + N | 1 | Setpoint | 0x00 °C |
| 40 + N | 2 | Heating Demand | 0x1A % |

#### 6. Reclaim Hot Water

Good candidate once implemented. Tank temperature, power, ambient temperature all have clear unit codes.

**Suggested device/channel allocation:**

| DeviceId | ChannelId | Param | Unit code |
|---|---|---|---|
| 50 | 0 | Tank Temp | 0x00 °C |
| 50 | 1 | Ambient Temp | 0x00 °C |
| 50 | 2 | Power | 0x1B W |

#### 7. Shelly Devices

Per-device power and energy where modelling permits. Temperature sensor values.

**Suggested device/channel allocation:**

| DeviceId | ChannelId | Param | Unit code |
|---|---|---|---|
| 60 + N | 0 | Power (device N) | 0x1B W |
| 60 + N | 1 | Energy | 0x1C Wh |
| 70 + N | 0 | Temp sensor N | 0x00 °C |
| 70 + N | 1 | Humidity sensor N | 0x1A % |

---

### ❌ Not recommended

| Integration | Reason |
|---|---|
| **Sonos** | All meaningful data is strings (track, artist, state) or already handled by Audio Application (app 205) which is the correct native mechanism |
| **Inception Alarm** | State is textual (Armed/Disarmed, door open/closed) — no physical measurement units |
| **OpenSprinkler** | Zone active = binary, water level % could fit but isn't worth the C-Bus project overhead for a single value |
| **LG TV** | Power, app, volume — none are physical measurements |
| **Apple TV** | Same |
| **SolCast** | Forecast values (kW) could technically fit but are predictions, not live measurements — User Params are more appropriate |
| **Asko / Gaggenau** | States and programme data are textual; water temp and oven temp are borderline but these are appliances not sensor networks |
| **Ubiquiti UDM** | Presence state = boolean; latency = ms (no code) |
| **BOM forecast strings** | Sunrise, sunset, icon descriptor, short text — strings only |

---

## Implementation notes

1. **C-Bus project prerequisite** — each DeviceId + ChannelId combination must be added to the Measurement Application (app 228) in the SpaceLogic C-Bus Commission software **before** `SetCBusMeasurement` calls will be accepted. If the device/channel doesn't exist in the project, the call silently fails or errors.

2. **Existing scripts need adding, not replacing** — User Parameters should be kept alongside measurement writes. Measurement gives native panel support; User Params give dashboard string flexibility. The two are complementary.

3. **DeviceId allocation** — the table above suggests a grouping (10=Ecowitt, 11=BOM, 20=Sigenergy, 30=Panasonic, 40–49=Unisenza, 50=Reclaim, 60+=Shelly). This is a suggestion — finalise before commissioning since DeviceIds must be configured in the C-Bus project.

4. **Unit code gaps** — there is no unit code for UV Index, Beaufort scale, or rain probability %. These values should stay as User Params only.

5. **Timing** — `SetCBusMeasurement` should be called at the **same cadence** as the User Param writes (i.e. inside the existing Resident_Poll). Do not add a separate measurement timer.

---

## Implementation status

| Integration | Status | DeviceId | Notes |
|---|---|---|---|
| **Ecowitt** | ✅ Implemented | 10 | Ch 0–9: temp, feels like, dew point, humidity, wind (m/s), gust, rain rate, rain today, pressure (Pa), solar |
| **Sigenergy** | ⏳ Pending script | 20 | To be added when the Sigenergy derived-values Lua script is written |
| Others | 🔲 Not yet | — | Panasonic, Unisenza, Reclaim, Shelly — lower priority |

---

## Sigenergy — implementation pattern (for when that script is written)

Add the following to the Sigenergy Lua resident script alongside UserParam writes.
Uses the same `safeMeasure` pattern as Ecowitt. DeviceId = 20.

```lua
-- In CONFIGURATION section:
local MEAS_DEVICE = 20

-- Unit codes
local MEAS_UNIT_WATTS   = 0x1B
local MEAS_UNIT_WH      = 0x1C
local MEAS_UNIT_PERCENT = 0x1A
local MEAS_UNIT_CELSIUS = 0x00

-- In SECTION 6 (C-Bus I/O helpers), add safeMeasure() — same implementation as Ecowitt.

-- In Resident_Poll, after UserParam writes:
safeMeasure(0, pvPowerW,           MEAS_UNIT_WATTS,   dbg)  -- PV Power
safeMeasure(1, batteryPowerW,      MEAS_UNIT_WATTS,   dbg)  -- Battery Power (+charge/-discharge)
safeMeasure(2, gridPowerW,         MEAS_UNIT_WATTS,   dbg)  -- Grid Power (+import/-export)
safeMeasure(3, loadPowerW,         MEAS_UNIT_WATTS,   dbg)  -- House Load
safeMeasure(4, batterySOC,         MEAS_UNIT_PERCENT, dbg)  -- Battery SOC
safeMeasure(5, batterySOH,         MEAS_UNIT_PERCENT, dbg)  -- Battery SOH
safeMeasure(6, pvDailyKwh * 1000,  MEAS_UNIT_WH,      dbg)  -- PV Daily (kWh → Wh)
safeMeasure(7, selfConsumptionPct, MEAS_UNIT_PERCENT, dbg)  -- Self-Consumption %
```

**C-Bus project configuration required:** Add Device 20, Channels 0–7 to the Measurement Application (app 228) before deploying.
