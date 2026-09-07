# Integration Research: OpenSprinkler

**Integration #:** 13  
**Device / Service:** OpenSprinkler irrigation controller  
**Last Researched:** 2025  

---

## 1. Integration Method

**Local LAN — OpenSprinkler HTTP REST API.**

OpenSprinkler (hardware and firmware by Ray Wang) exposes a comprehensive REST API over HTTP on its local IP address (default port 80). This API is well-documented at [opensprinkler.com/support/api](https://opensprinkler.com/support/api/).

**Base URL:** `http://<opensprinkler-ip>/`

**Key endpoints:**
- `GET /jo` — system options (water level/weather adjustment %, firmware version, etc.)
- `GET /jc` — controller variables (last run program, last run duration, etc.)
- `GET /js` — station status (which zones are currently on/off, remaining time)
- `GET /jp` — programme data (all configured programmes)
- `GET /jn` — stations (all zone names and configurations)
- `POST /cm?pw=<md5(password)>&sid=<station>&en=<0/1>&t=<duration>` — manually run a station for duration seconds, or turn off

All requests require the password as an MD5 hash in the query string: `pw=<md5(password)>`.

A prototype implementation exists in `Cbus-OpenSprinkler` (`OS_UserLibrary.lua`). That script covers water level, 3-zone status, and last run — but is acknowledged as a non-comprehensive release. A full gold-standard implementation would extend coverage.

---

## 2. Connectivity Requirement

🏠 **Fully local — no internet connection required.**  
All API communication is directly to the OpenSprinkler device on the LAN. OpenSprinkler does have optional cloud connectivity for weather-based adjustment (pulling rain/ET data from a weather service), but the API integration does not require cloud access.

---

## 3. Authentication Method

**MD5 password hash in query string.**

All API requests include `pw=<md5(password)>` as a URL parameter. The password is the OpenSprinkler device password (default: `opendoor`).

MD5 hashing in Lua: the 5500AC's LogicMachine environment includes an `md5` function or it can be computed via `require("md5")` or using the `crypto` module. Alternatively, a precomputed MD5 string can be hardcoded (acceptable if the password is static).

Credentials in `user.secrets`:
```lua
secrets.opensprinkler = {
  host     = "192.168.1.119",
  password = "your-password",   -- or store the MD5 hash directly
  password_md5 = "md5hash"      -- precomputed for use in requests
}
```

---

## 4. Polling vs. Event-Driven

**Polling** — 60-second resident script interval.

The OpenSprinkler API is request/response only — no push or webhook support. A 60-second interval is appropriate for irrigation monitoring. Zone status changes (a programme starting) will be reflected within one poll cycle.

---

## 5. Available Data / Controllable Parameters

### Read

**System:**

| Metric | Endpoint | Notes |
|---|---|---|
| Water level (weather adjustment %) | `/jo` — `wl` | 100% = full, 0% = disabled |
| Firmware version | `/jo` — `fwv` | |
| System uptime | `/jc` — `devt` | Seconds |
| Rain sensor state | `/jc` — `rs` | 0/1 |
| Rain delay active | `/jc` — `rdst` | Seconds remaining, 0=inactive |

**Station Status (per zone):**

| Metric | Endpoint | Notes |
|---|---|---|
| Zone on/off | `/js` — `sn` array | 1=running, 0=off |
| Remaining time | `/js` — station array | Seconds remaining for running zone |

**Last Programme Run:**

| Metric | Endpoint | Notes |
|---|---|---|
| Last station run | `/jc` — `lrun` | `[station, program, duration, endtime]` |
| Duration | `/jc` — `lrun[2]` | Seconds |

**Programme Data:**

| Metric | Notes |
|---|---|
| Programme names and schedules | Full programme config — complex nested structure |
| Next run time | Derived from programme data |

### Write (Control)

| Action | Notes |
|---|---|
| Run zone for N seconds | `GET /cm?pw=<md5pw>&sid=<zone_id>&en=1&t=<seconds>` |
| Stop zone | `GET /cm?pw=<md5pw>&sid=<zone_id>&en=0` |
| Enable/disable a programme | `GET /mp?pw=<md5pw>&pid=<prog_id>&...` |
| Set rain delay | `GET /cv?pw=<md5pw>&rd=<hours>` |
| Change water level | `GET /cv?pw=<md5pw>&wl=<percent>` |

---

## 6. Estimated Implementation Difficulty

🟡 **Easy.**

The API is well-documented, uses plain HTTP, and requires only MD5 password handling. The prototype `OS_UserLibrary.lua` already demonstrates the pattern — a gold-standard rewrite extending to all zones, programme monitoring, and manual control is straightforward.

The existing prototype covers only 3 zones via hardcoded parameter names. The gold-standard version should:
- Discover zone count from `GET /jn`
- Iterate over all zones dynamically
- Support manual zone run/stop from event scripts
- Include last programme run with formatted string

---

## 7. Known Limitations and Risks

- **MD5 in query string** — the MD5 password hash is sent in the URL and can be sniffed on an unencrypted LAN. Acceptable for a trusted LAN; not suitable for internet-exposed deployments.
- **MD5 computation** — a pure-Lua MD5 implementation or a system library must be available on the 5500AC. Verify availability or precompute the hash.
- **Prototype reference** — `OS_UserLibrary.lua` is acknowledged as prototype-grade. The gold-standard rewrite should be comprehensive and follow full gold-standard conventions.
- **Zone count** — the prototype hardcodes 3 zones. The gold-standard version should dynamically discover zone count to support installations with more zones.
- **Programme complexity** — full programme data parsing (schedule times, days of week, etc.) is complex. Initial implementation should focus on zone status and manual control; programme display can be added later.

---

## 8. Recommended C-Bus Group Address Strategy

User Parameters per zone plus global system params.

Suggested naming convention:

```
Irrigation_WaterLevel     (Number — weather adjustment %, 0–200)
Irrigation_RainSensor     (Number — 0/1)
Irrigation_RainDelay      (Number — seconds remaining)
Irrigation_Zone1_Active   (Number — 0/1)
Irrigation_Zone2_Active   (Number — 0/1)
Irrigation_Zone3_Active   (Number — 0/1)
... (per zone — dynamically named from zone names in controller)
Irrigation_LastRun        (String — "Zone 2 ran for 12 minutes, ended 08:45")
Irrigation_LastUpdated    (String)
```

For manual zone control from the dashboard:
- Write `1` to `Irrigation_Zone1_Run` → event script calls zone run API
- Write `0` to `Irrigation_Zone1_Run` → event script stops zone

---

## 9. Dependencies on Gold-Standard Patterns

| Pattern | Source | Applicability |
|---|---|---|
| `socket.http` local LAN polling | All local gold-standard | Direct |
| `safeSetUserParam` | All gold-standard | Required |
| `isDebuggingEnabled` cached per poll | All gold-standard | Required |
| `_missingParamWarned` | All gold-standard | Required |
| Dynamic zone discovery | Inception entity discovery | Adapt for zone names from `/jn` |
| Event script control pattern | Panasonic `script_event_control.lua` | Zone run/stop commands |
| `user.secrets` for password | All gold-standard | Required |

---

## Action Required

1. **Confirm zone count** on the OpenSprinkler installation.
2. **Obtain OpenSprinkler IP and password** — confirm DHCP reservation is in place.
3. **Verify MD5 library availability** on the 5500AC firmware version.
4. **Write gold-standard integration script** in a future session — this research plus the prototype reference is sufficient to proceed.
