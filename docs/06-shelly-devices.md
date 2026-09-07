# Integration Research: Shelly Devices

**Integration #:** 6  
**Device / Service:** Shelly smart switches, relays, and temperature sensors  
**Last Researched:** 2025  

---

## 1. Integration Method

**Local LAN — Shelly REST API (Gen 1 and Gen 2/3/Plus/Pro).**

Shelly devices expose a local HTTP REST API on their IP address. Two API generations exist:

### Gen 1 API (Shelly 1, Shelly 2, Shelly Plug, Shelly H&T, etc.)
- `GET /status` — full device status (all outputs, inputs, temperature, energy, etc.)
- `GET /relay/0` — relay state
- `GET /relay/0?turn=on` — turn relay on (control via GET parameters)
- `GET /relay/0?turn=off`

### Gen 2 / Gen 2+ API (Shelly Plus 1, Shelly Pro, Shelly Mini, etc.)
- Uses **Shelly RPC** (Remote Procedure Call) via HTTP POST or WebSocket
- `POST /rpc/Shelly.GetStatus` — full device status
- `POST /rpc/Switch.Set` — control relay: `{ "id": 0, "on": true }`
- `POST /rpc/Temperature.GetStatus` — temperature sensor readings (Shelly Plus Add-on)
- `POST /rpc/Input.GetStatus` — digital input state

**Recommended approach:** Poll using `GET /status` (Gen 1) or `POST /rpc/Shelly.GetStatus` (Gen 2) per device. Control via `GET /relay/0?turn=on/off` (Gen 1) or `POST /rpc/Switch.Set` (Gen 2).

For a fleet of Shelly devices, the resident script should iterate over a configured device list, polling each one. A shared `fetchShelly(ip, gen)` helper handles both API generations.

---

## 2. Connectivity Requirement

🏠 **Fully local — no internet connection required.**  
All Shelly API communication is directly over the LAN. Shelly cloud and the Shelly app are not used. Shelly devices should be configured with **cloud disabled** in their settings to prevent unexpected firmware updates or traffic.

> **Note:** Shelly devices can optionally be used via the Shelly cloud API, but this is explicitly not recommended — local LAN is faster, more reliable, and does not depend on cloud availability.

---

## 3. Authentication Method

**Optional** — Shelly devices support optional HTTP authentication (username/password), configurable per device. By default, many Shelly devices have no authentication enabled.

If authentication is enabled:
- Gen 1: HTTP Basic Auth via URL (`http://user:pass@ip/status`)
- Gen 2: HTTP Digest Auth via standard Authorization header, or via RPC `auth` parameter

Credentials stored in `user.secrets`:
```lua
secrets.shelly = {
  username = "admin",    -- or nil if no auth
  password = "password"  -- or nil if no auth
}
```

---

## 4. Polling vs. Event-Driven

**Polling preferred for C-Bus integration** — 15–30 second resident poll interval.

Shelly also supports **MQTT** (publish to broker on state change) and **HTTP webhooks** (POST to URL on state change), which provide near-instantaneous event delivery. However, these require additional infrastructure (MQTT broker or HTTP listener) not available natively on the 5500AC.

For the C-Bus 5500AC integration, polling is the appropriate approach. A 15-second interval is fast enough for light switch state feedback and energy monitoring without excessive network load.

> **Note on Shelly acting as input:** If Shelly devices are wired to physical light switches (detached switch mode), the physical switch state is reflected in the `/status` response within seconds. Polling at 15s means the C-Bus dashboard may show a 0–15 second lag when a physical button is pressed — acceptable for monitoring purposes.

---

## 5. Available Data / Controllable Parameters

### Read (per device)

**Shelly Relay / Switch (Gen 1 & Gen 2):**

| Metric | Notes |
|---|---|
| Relay output state | true/false — current on/off state |
| Input state | true/false — physical button/switch state |
| Power consumption | Watts (if power metering model) |
| Energy consumption | Wh (cumulative) |
| Voltage | V (metering models) |
| Current | A (metering models) |
| Overtemperature flag | bool |
| Wi-Fi signal (RSSI) | dBm |
| Uptime | seconds |

**Shelly H&T / Temperature Sensor (Gen 1):**

| Metric | Notes |
|---|---|
| Temperature | °C |
| Humidity | % |
| Battery level | % |
| Last wake time | |

**Shelly Plus Add-on / DS18B20 Temperature (Gen 2):**

| Metric | Notes |
|---|---|
| Temperature (per sensor channel) | °C |
| Humidity (if fitted) | % |

**Shelly i4 / Input device (Gen 2):**

| Metric | Notes |
|---|---|
| Input channels 0–3 state | true/false |

### Write (Control)

| Action | Gen 1 | Gen 2 |
|---|---|---|
| Turn relay on | `GET /relay/0?turn=on` | `POST /rpc/Switch.Set {"id":0,"on":true}` |
| Turn relay off | `GET /relay/0?turn=off` | `POST /rpc/Switch.Set {"id":0,"on":false}` |
| Toggle relay | `GET /relay/0?turn=toggle` | `POST /rpc/Switch.Toggle {"id":0}` |
| Timed on | `GET /relay/0?turn=on&timer=30` | `POST /rpc/Switch.Set {"id":0,"on":true,"toggle_after":30}` |
| Reset energy counter | (model dependent) | `POST /rpc/Switch.ResetCounters` |

---

## 6. Estimated Implementation Difficulty

🟡 **Easy to Medium.**

- **Easy** for a homogeneous fleet (all Gen 1 or all Gen 2).
- **Medium** for a mixed fleet requiring both API patterns with a unified driver.

The main complexity is managing a list of configured Shelly devices (IP, name, generation, type) and iterating over them cleanly. The API itself is straightforward JSON. A config table approach (device list array) follows the gold-standard pattern neatly.

---

## 7. Known Limitations and Risks

- **Mixed Gen 1/Gen 2 fleet** — API patterns differ significantly between generations. A single driver must handle both, or two separate scripts are needed.
- **IP assignment** — each Shelly device needs a stable IP. Assign DHCP reservations for all devices.
- **No authentication by default** — on a trusted LAN this is acceptable, but should be noted for security-conscious deployments.
- **Energy meter accuracy** — power metering on Shelly devices is approximate (±1–2%), suitable for dashboard display but not billing-grade.
- **Gen 2 HTTPS** — Shelly Gen 2 devices support HTTPS but use self-signed certificates. Using plain HTTP (port 80) on a trusted LAN is simpler and avoids certificate validation issues.
- **Firmware updates** — Shelly devices update their firmware automatically if cloud is enabled. Disable cloud and auto-update to ensure API compatibility over time.
- **H&T battery operation** — the Shelly H&T is battery-operated and sleeps between readings. It cannot be polled on demand; it pushes data to a configured endpoint or MQTT broker when it wakes. For C-Bus integration, the most recent push value could be cached in a UserParam via a webhook listener, or the device could be polled via HTTP if awake (it remains awake briefly after each push).

---

## 8. Recommended C-Bus Group Address Strategy

User Parameters per device, using the device name as a prefix.

Suggested naming convention (with a `Shelly_` prefix to avoid collisions):

```
Shelly_Kitchen_Power      (Number — relay state: 0=off, 1=on)
Shelly_Kitchen_Watts      (Number)
Shelly_Kitchen_Energy_Wh  (Number)
Shelly_Garage_Power       (Number)
Shelly_Laundry_Power      (Number)
Shelly_TempSensor1_Temp   (Number, ×10)
Shelly_TempSensor1_Humid  (Number, %)
Shelly_LastUpdated        (String)
```

For physical switch inputs that need to trigger C-Bus scenes, use a C-Bus Group Address write from the event script rather than a UserParam.

---

## 9. Dependencies on Gold-Standard Patterns

| Pattern | Source | Applicability |
|---|---|---|
| `socket.http` local LAN polling | Inception, Unisenza | Direct |
| Device list iteration config table | Panasonic (zone map) | Adapt for multi-device list |
| `safeSetUserParam` | All gold-standard | Required |
| `isDebuggingEnabled` cached per poll | All gold-standard | Required |
| `_missingParamWarned` | All gold-standard | Required |
| `extractNumber()` | Ecowitt skill | For parsing any numeric strings |
| Event script for control | Panasonic `script_event_control.lua` | Pattern for relay control event scripts |

---

## Action Required

1. **Inventory all Shelly devices** — list device name, model, generation (Gen 1 or Gen 2), IP address, and what it controls/monitors.
2. **Assign DHCP reservations** for all Shelly devices.
3. **Decide on authentication** — enable or disable per device consistently.
4. **Design config table** — define the device list structure in the resident script configuration (name, ip, generation, type).
5. **Write integration script** in a future session — this research is sufficient to proceed.
