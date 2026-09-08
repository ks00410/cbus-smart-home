# Ecowitt — C-Bus Integration

Local LAN integration for Ecowitt weather stations (GW1000, GW2000, HP2550, etc.)
using the station's built-in local HTTP API. No cloud, no Ecowitt account required.

## Files

| File | Purpose |
|---|---|
| `user_library_ecowitt.lua` | User Library — load as `user.ecowitt` |
| `script_resident_poll.lua` | Resident script — 60-second poll cycle |

## Setup

### 1. Secrets

The Ecowitt cloud credentials (`eco_api`, `eco_app`, `eco_mac`) are referenced in the
library but **not used** — the integration is entirely local. They are retained in
`user.secrets` for future reference only. No `user.secrets` changes are required.

### 2. Station IP

Set `API_URL` in the library to your Ecowitt base station's local IP address:

```lua
local API_URL = "http://192.168.1.213/get_livedata_info"
```

Assign a DHCP reservation for the base station.

### 3. C-Bus User Parameters

Create the following User Parameters on network 0.

**Raw sensor params** (populated automatically from the station — only params present
on your specific model will have values written):
```
IndoorTemp, OutdoorTemp, DewPoint, WindChill, HeatIndex
IndoorHumidity, OutdoorHumidity
AbsBarometric, RelBarometric
WindDirection, WindSpeed, GustSpeed, DayMaxWind
RainEvent, RainRate, RainHour, RainDay, RainWeek, RainMonth, RainYear
Light, UV, UVI
Soil1, Soil2 ... (per soil sensor channel)
Soil1_Updated, Soil2_Updated ... (timestamp of last significant moisture change)
```

**Derived params:**
```
FeelsLike           (Number — wind-chill or heat index adjusted temperature)
ComfortZone         (String — "Comfortable" / "Hot & Humid" / "Cold" etc.)
Beaufort            (Number — 0–12 Beaufort scale)
BeaufortDesc        (String — "Calm" / "Light Breeze" / "Near Gale" etc.)
GustAlert           (Number — 0/1, set when gusts exceed threshold)
UVBurnTime          (Number — minutes to sunburn at current UV, nil at night)
UVLabel             (String — "Low" / "Moderate" / "High" / "Very High" / "Extreme")
DewPointComfort     (String — "Dry" / "Comfortable" / "Muggy" / "Oppressive")
FrostRisk           (Number — 0/1)
CondensationRisk    (Number — 0/1)
PressureTrend       (String — "Rising" / "Falling" / "Steady")
PressureRate        (Number — signed hPa change over 3 hours)
WeatherOutlook      (String — plain-English forecast based on pressure trend)
LastUpdated         (String)
Debug Logging       (Boolean/Number — set to 1 for verbose output)
```

### 4. Scripts

1. Load `user_library_ecowitt.lua` as a User Library named `ecowitt`.
2. Create a Resident script with sleep interval **60 seconds**, paste `script_resident_poll.lua`.

## Notes

- Sensor availability depends on your station model and attached sensors. Missing
  sensors are silently skipped — no errors are logged for absent sensors.
- Soil moisture channels are named `Soil1`, `Soil2` etc. A `_Updated` timestamp
  param is written whenever the reading changes by more than 2 percentage points.
- The `GustAlert` threshold defaults to 20 knots (Beaufort 6). Adjust
  `GUST_ALERT_THRESHOLD_KNOTS` in the library to suit your needs.
- Pressure trend is calculated over a 3-hour rolling window (`PRESSURE_HISTORY_SECONDS`).
  The window resets on script restart.
