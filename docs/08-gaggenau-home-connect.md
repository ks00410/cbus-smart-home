# Integration Research: Gaggenau Oven and Cooktop (Home Connect — Local)

**Integration #:** 8  
**Device / Service:** Gaggenau oven and cooktop via BSH Home Connect — **local LAN WebSocket**  
**Last Researched:** 2025  
**Updated:** Local LAN approach confirmed via `chris-mc1/homeconnect_local_hass` and `homeconnect-websocket` Python library

---

## 1. Integration Method

**Local LAN — Home Connect WebSocket protocol (TLS/PSK or AES).**

BSH appliances (Gaggenau, Bosch, Siemens, Neff) communicate over the local network using a **WebSocket-based protocol** with per-appliance encryption. This is confirmed by the open-source Home Assistant integration [`homeconnect_local_hass`](https://github.com/chris-mc1/homeconnect_local_hass) and the underlying Python library [`homeconnect-websocket`](https://pypi.org/project/homeconnect-websocket/) (v1.5.4 as of August 2026).

### Protocol details

- **Transport:** WebSocket (ws://)
- **Encryption:** Two modes depending on appliance generation:
  - **TLS mode** (newer appliances): TLS with a device-specific PSK (Pre-Shared Key)
  - **AES mode** (older appliances): AES-CBC with a device-specific key and IV
- **Encryption credentials:** Retrieved once from the Home Connect cloud via the [Home Connect Profile Downloader](https://github.com/bruestel/homeconnect-profile-downloader) tool — downloads a ZIP containing each appliance's `DeviceDescription.xml`, `FeatureMapping.xml`, encryption key, and IV
- **Discovery:** Appliances advertise themselves via **mDNS/Zeroconf** on the LAN (the HA integration includes a zeroconf discovery step)
- **Connection:** Persistent WebSocket connection to `ws://<appliance-ip>/`; reconnects automatically on drop

### Why this cannot be implemented directly in Lua

WebSocket is not available as a native library on the C-Bus 5500AC (LogicMachine) Lua environment. The `homeconnect-websocket` protocol also involves TLS with PSK negotiation — not standard HTTPS. This cannot be reproduced in plain Lua.

### Recommended approach: Local HTTP Proxy

Run a lightweight Python proxy service on a LAN device (NAS, Raspberry Pi, or similar always-on host) that:
1. Uses `homeconnect-websocket` to maintain a persistent WebSocket connection to each appliance
2. Exposes a simple HTTP REST endpoint (e.g. `GET /oven/status`, `POST /oven/command`) for the 5500AC to poll
3. Caches the latest appliance state received via the persistent WebSocket connection

The 5500AC uses `socket.http` to poll the proxy — **identical pattern to the Shelly and OpenSprinkler integrations**. The proxy handles all WebSocket complexity.

This approach:
- Is **fully local** — no cloud API calls at runtime
- Is **fast** — WebSocket state updates from the appliance arrive in real time; proxy caches them
- Is **maintainable** — the `homeconnect-websocket` library is actively maintained on PyPI

---

## 2. Connectivity Requirement

🏠 **Fully local at runtime — no internet connection required.**

One-time setup steps that do require internet:
1. Create a Home Connect account and connect appliances via the Home Connect app (once only)
2. Run the [Home Connect Profile Downloader](https://github.com/bruestel/homeconnect-profile-downloader) to extract appliance profiles (once only, or when re-keying)

After the profiles are downloaded and the proxy is running, **no internet or cloud access is needed** for ongoing operation.

---

## 3. Authentication Method

**Per-appliance PSK or AES key** — static hardware credentials.

Each appliance has a unique encryption key and (for AES mode) an IV, embedded in its firmware and extractable via the Home Connect Profile Downloader. These credentials are:
- Downloaded once using the Profile Downloader tool (requires a Home Connect cloud account login, but only once)
- Stored in the proxy service configuration
- Used directly by `homeconnect-websocket` to authenticate the WebSocket connection

No ongoing token refresh, OAuth2, or cloud API interaction is required at runtime.

Credentials stored in proxy config (not on the 5500AC):
```json
{
  "oven": {
    "host": "192.168.1.xx",
    "psk": "base64-encoded-psk",
    "ha_id": "Gaggenau-Oven-XXXXXXXXXXXX",
    "device_description": "path/to/DeviceDescription.xml",
    "feature_mapping": "path/to/FeatureMapping.xml"
  }
}
```

---

## 4. Polling vs. Event-Driven

**Effectively event-driven** — same pattern as Inception long-poll.

The WebSocket connection delivers appliance state updates in real time as they occur (door opened, programme started, temperature reached, etc.). The proxy caches the latest state and the 5500AC polls the proxy HTTP endpoint at a regular interval (e.g. 30 seconds) to retrieve the cached state.

For the proxy itself, no polling is needed — it receives push updates from the appliance continuously over the persistent WebSocket.

---

## 5. Available Data / Controllable Parameters

Based on the entity descriptions in [`cooking.py`](https://github.com/chris-mc1/homeconnect_local_hass/blob/main/custom_components/homeconnect_ws/entity_descriptions/cooking.py) and the `homeconnect-websocket` library.

### Oven

**Read:**

| Entity Key | Notes |
|---|---|
| `BSH.Common.Status.OperationState` | Inactive / Ready / Run / Pause / ActionRequired / Finished / Error |
| `BSH.Common.Status.DoorState` | Closed / Open / Locked |
| `BSH.Common.Status.RemoteControlActive` | Boolean — must be true for remote commands |
| `BSH.Common.Status.RemoteControlStartAllowed` | Boolean |
| `Cooking.Oven.Status.Cavity.N.CurrentTemperature` | °C — current cavity temperature (per cavity) |
| `Cooking.Oven.Status.Cavity.N.WaterTankEmpty` | Boolean |
| `Cooking.Oven.Event.Cavity.N.AlarmClockElapsed` | Boolean — alarm clock finished |
| `Cooking.Oven.Event.Cavity.N.PreheatFinished` | Boolean |
| `BSH.Common.Root.ActiveProgram` | Currently running programme key |
| `BSH.Common.Option.RemainingProgramTime` | Seconds remaining |
| `BSH.Common.Option.Duration` | Programme duration in seconds |
| `BSH.Common.Option.StartInRelative` | Delayed start offset (seconds) |

**Write (Control — requires `RemoteControlActive = true`):**

| Action | Entity Key |
|---|---|
| Start programme | `BSH.Common.Root.ActiveProgram` with options |
| Stop programme | `BSH.Common.Root.ActiveProgram` → delete |
| Set alarm clock | `Cooking.Oven.Setting.Cavity.N.AlarmClock` |
| Set child lock | `BSH.Common.Setting.ChildLock` |
| Set oven light | `Cooking.Oven.Setting.Cavity.N.Light` |

### Cooktop

**Read:**

| Entity Key | Notes |
|---|---|
| `BSH.Common.Status.OperationState` | Inactive / Run / Error |
| `BSH.Common.Status.LocalControlActive` | User actively using cooktop |
| Per-zone heating level | Zone-specific entities from FeatureMapping |

**Write:**

| Action | Notes |
|---|---|
| Child lock | `BSH.Common.Setting.ChildLock` |

---

## 6. Estimated Implementation Difficulty

**Proxy service development:** 🟡 **Easy to Medium**
- `homeconnect-websocket` is pip-installable and well-documented
- Proxy is a simple Python `asyncio` HTTP server wrapping the WebSocket client
- One-time profile download setup is required

**C-Bus Lua client:** ✅ **Easy**
- Standard `socket.http` polling against the proxy endpoint
- Same pattern as Shelly / OpenSprinkler

**Profile download setup:** 🟡 **Easy** (once)
- Requires a Home Connect account with appliances registered
- [Home Connect Profile Downloader](https://github.com/bruestel/homeconnect-profile-downloader) does the extraction

**Overall (proxy approach):** 🟠 **Medium** — infrastructure to set up, but the core protocol library exists and is production-grade.

---

## 7. Known Limitations and Risks

- **Proxy infrastructure required** — a separate always-on LAN device must run the Python proxy. The same host used for the Apple TV pyatv proxy can serve double duty.
- **Profile re-download on re-keying** — if BSH ever rotates appliance keys (unlikely but possible), the profile must be re-downloaded. The Profile Downloader tool needs to be re-run, but this is a one-time action.
- **Remote control safety gate** — the oven only accepts remote programme start commands when the user has physically pressed the "Remote Start" button on the appliance. This is a deliberate safety feature and cannot be bypassed. Monitoring (temperature, door state, programme state) works without this gate.
- **`RemoteControlActive` check required** — any control command should first verify that `RemoteControlActive` is true; otherwise the command will be rejected by the appliance.
- **WebSocket reconnection** — the proxy must implement reconnection logic (already provided by the `homeconnect-websocket` library's `ConnectionState.RECONNECTING` callback).
- **mDNS vs static IP** — the appliance advertises via mDNS. If no mDNS resolver is available on the proxy host, configure a static IP for the appliance and set it explicitly in the proxy config.
- **AES vs TLS mode** — older Gaggenau models may use AES mode. Confirm the `connectionType` field in the downloaded profile JSON (`"TLS"` or `"AES"`). The `homeconnect-websocket` library supports both.

---

## 8. Recommended C-Bus Group Address Strategy

User Parameters via the proxy HTTP endpoint.

Suggested naming convention:

```
Oven_OperationState   (String — "Inactive" / "Ready" / "Run" / "Finished" / "Error")
Oven_DoorState        (String — "Closed" / "Open")
Oven_CurrentTemp      (Number, °C — cavity temperature)
Oven_Program          (String — active programme name)
Oven_TimeRemaining    (Number — seconds)
Oven_PreheatDone      (Number — 0/1)
Oven_AlarmElapsed     (Number — 0/1)
Oven_RemoteAllowed    (Number — 0/1)
Oven_LastUpdated      (String)

Cooktop_OperationState (String — "Inactive" / "Run")
Cooktop_LastUpdated    (String)
```

---

## 9. Dependencies on Gold-Standard Patterns

| Pattern | Source | Applicability |
|---|---|---|
| `socket.http` local LAN polling | Inception, Unisenza | Polling the proxy endpoint |
| `safeSetUserParam` | All gold-standard | Required |
| `isDebuggingEnabled` cached per poll | All gold-standard | Required |
| `_missingParamWarned` | All gold-standard | Required |
| Proxy architecture | Apple TV (pyatv) | Same pattern — one proxy host, multiple integrations |

---

## Action Required

1. **Download appliance profiles** — install [Home Connect Profile Downloader](https://github.com/bruestel/homeconnect-profile-downloader), log in with Home Connect account, download ZIP profiles for oven and cooktop. Select "openHAB" as target format.
2. **Set up proxy host** — confirm an always-on LAN device (NAS, Pi, etc.) is available. This can be shared with the Apple TV pyatv proxy.
3. **Install `homeconnect-websocket`** — `pip install homeconnect-websocket` on the proxy host.
4. **Write proxy service** — Python asyncio HTTP server wrapping `homeconnect_websocket.HomeAppliance`. Expose `GET /oven/status` and `GET /cooktop/status` endpoints returning JSON.
5. **Write C-Bus Lua integration script** in a future session — standard `socket.http` poll of the proxy endpoint.

---

## Reference

- Home Connect Local HA integration: https://github.com/chris-mc1/homeconnect_local_hass
- homeconnect-websocket Python library: https://pypi.org/project/homeconnect-websocket/
- Home Connect Profile Downloader: https://github.com/bruestel/homeconnect-profile-downloader
- BSH Home Connect developer portal: https://developer.home-connect.com
