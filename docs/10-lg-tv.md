# Integration Research: LG TV

**Integration #:** 10  
**Device / Service:** LG Smart TV — usage and watch-time metrics capture  
**Last Researched:** 2025  
**Updated:** LG WebOS SSAP is plain WebSocket JSON — direct integration from 5500AC confirmed viable

---

## 1. Integration Method

**Local LAN — LG WebOS SSAP (Simple Service Access Protocol) over WebSocket.**

LG Smart TVs running WebOS (2014+) expose a JSON-over-WebSocket control API on port 3000. This is the same API used by the LG ThinQ app and all community WebOS clients.

**Connection:** `ws://<tv-ip>:3000`  
**Protocol:** JSON messages over plain WebSocket (RFC 6455)

Earlier research incorrectly stated that this was not accessible from the 5500AC without a proxy. With the **LogicMachine `user.websocket` library** (confirmed available from the official KB Casambi integration), the SSAP protocol can be implemented directly in Lua — **no proxy required**.

### SSAP protocol overview

SSAP is a simple request/response and subscription protocol over WebSocket:

**1. Pairing (first connection only)**
```json
// Send:
{ "type": "register", "id": "reg0", "payload": { "forcePairing": false, "pairingType": "PROMPT", "manifest": { "appId": "cbus-integration", "vendorId": "cbus", "clientKey": "" } } }

// TV displays a prompt — user must accept
// Response includes a client key to store for future connections:
{ "type": "registered", "payload": { "client-key": "xxxxxxxx" } }
```

**2. Subsequent connections (using stored client key)**
```json
{ "type": "register", "id": "reg0", "payload": { "client-key": "stored-client-key" } }
// Response: { "type": "registered" } — no prompt shown
```

**3. Sending commands / queries**
```json
// Request:
{ "type": "request", "id": "cmd1", "uri": "ssap://com.webos.service.tvpower/getPowerState" }

// Response:
{ "type": "response", "id": "cmd1", "payload": { "state": "Active" } }
```

**4. Subscribing to state changes**
```json
// Subscribe to foreground app changes:
{ "type": "subscribe", "id": "sub1", "uri": "ssap://com.webos.applicationManager/getForegroundAppInfo" }

// Response comes immediately and again every time the app changes:
{ "type": "response", "id": "sub1", "payload": { "appId": "netflix", "windowId": "" } }
```

The synchronous `user.websocket` library handles this cleanly — connect, send a JSON register message, receive the response, send queries, receive responses, close.

### Integration architecture

```
5500AC (LogicMachine)
  └── lg_tv_poll.lua  (resident script, e.g. 30s)
        └── user.lg_tv → ws://<tv-ip>:3000
              └── user.websocket  (LogicMachine KB Casambi library)
                    └── socket.tcp()  (LuaSocket — plain WS, no SSL)
```

No SSL is required — the SSAP protocol uses plain WebSocket (`ws://`), not WSS. This is the simpler path for `user.websocket`.

### Client key management

The client key returned on first pairing is stored in `user.secrets` and used for all subsequent connections. It persists indefinitely unless the TV's connected devices list is cleared.

One-time pairing requires a user to accept the prompt on the TV. This can be done from any WebSocket client (e.g. browser DevTools or `wscat`) once, saving the returned key before the Lua integration is deployed.

---

## 2. Connectivity Requirement

🏠 **Fully local — no internet connection required.**  
All SSAP communication is directly to the TV on the LAN.

---

## 3. Authentication Method

**Client key** — obtained from a one-time pairing handshake.

Store in `user.secrets`:
```lua
secrets.lg_tv = {
  host       = "192.168.1.xx",
  client_key = "xxxxxxxx"   -- obtained from first-time pairing
}
```

No token refresh or expiry management — the client key is permanent until revoked.

---

## 4. Polling vs. Event-Driven

**Per-poll connect** (simpler, recommended initially):
- Open WebSocket connection on each resident poll cycle (e.g. every 30 seconds)
- Authenticate with stored client key
- Send queries for power state, current app, volume
- Close connection

**Persistent connection with subscriptions** (advanced):
- Keep connection open in module state (`_ws`)
- Subscribe to `getForegroundAppInfo` and volume changes
- Drain receive buffer on each resident poll cycle
- Reconnect on error

**Recommended:** Start with per-poll connect — simpler and easier to debug. The SSAP protocol handles rapid connect/disconnect gracefully.

---

## 5. Available Data / Controllable Parameters

### Read

| SSAP URI | Data | Notes |
|---|---|---|
| `ssap://com.webos.service.tvpower/getPowerState` | Power state | `"Active"` / `"Suspend"` / `"Active Standby"` |
| `ssap://com.webos.applicationManager/getForegroundAppInfo` | Current app ID | e.g. `"netflix"`, `"youtube.leanback.v4"`, `"com.webos.app.livetv"` |
| `ssap://audio/getVolume` | Volume + muted state | `{ "volume": 42, "muted": false }` |
| `ssap://tv/getChannelList` | Channel list | Array of channels |
| `ssap://tv/getCurrentChannel` | Current channel | Name, number |
| `ssap://com.webos.service.update/getCurrentSWInformation` | Firmware version | |
| `ssap://system/getSystemInfo` | Model name, serial | |

### Write (Control)

| SSAP URI | Action | Notes |
|---|---|---|
| `ssap://system/turnOff` | Power off | Sends TV to standby |
| `ssap://tv/switchInput` | Change input source | `{ "inputId": "HDMI_1" }` |
| `ssap://audio/setVolume` | Set volume | `{ "volume": 30 }` |
| `ssap://audio/setMute` | Mute/unmute | `{ "mute": true }` |
| `ssap://system.launcher/launch` | Launch app | `{ "id": "netflix" }` |
| `ssap://system.launcher/close` | Close current app | |
| `ssap://media.controls/play` | Play | |
| `ssap://media.controls/pause` | Pause | |
| `ssap://media.controls/rewind` | Rewind | |
| `ssap://media.controls/fastForward` | Fast forward | |
| `ssap://com.webos.service.tvpower/powerOff` | Hard power off | |
| `ssap://com.webos.applicationManager/getForegroundAppInfo` | (subscribe) | Real-time app changes |

---

## 6. Estimated Implementation Difficulty

🟡 **Easy to Medium** — material downgrade from the previous "Very Hard (proxy)" assessment.

| Component | Difficulty | Notes |
|---|---|---|
| `user.websocket` library | ✅ Done | Already available from Casambi KB example |
| SSAP JSON protocol | ✅ Easy | Simple JSON request/response — no binary framing |
| Client key pairing (one-time) | ✅ Easy | One `wscat` or browser DevTools session |
| `user.secrets` key storage | ✅ Easy | Same pattern as all gold-standard integrations |
| App ID → display name mapping | 🟡 Easy | Static lookup table for known apps |
| Per-poll resident script | ✅ Easy | Same Unisenza pattern |
| Event script for control | ✅ Easy | Same Panasonic pattern |

The main task is writing the `user.lg_tv` library with SSAP command helpers and app ID mapping.

---

## 7. Known Limitations and Risks

- **One-time pairing required** — the TV must be physically accessible and powered on for the initial pairing. A WebSocket client (browser DevTools, `wscat`, or any WS tool) is used to perform pairing once and save the client key.
- **TV must be on for WebSocket connection** — SSAP is not accessible when the TV is in deep standby (hard off). Quick Start or network standby must be enabled in TV settings for the WebSocket port to remain reachable. Test this on the specific TV model.
- **App ID mapping** — app IDs are internal strings (e.g. `"youtube.leanback.v4"`) that must be mapped to human-readable names. A static lookup table covers the common apps; unknown IDs are logged as-is.
- **WebOS version variation** — available SSAP URIs vary between WebOS versions (1.x through 24.x). Test the specific TV model for supported URIs.
- **Plain WebSocket, no SSL** — SSAP uses `ws://` not `wss://`. This is by design and avoids any LuaSec PSK/cert complications.
- **Model-specific features** — some SSAP URIs (e.g. picture settings, sound output) are model-dependent. Stick to the core URIs documented above for maximum compatibility.

---

## 8. Recommended C-Bus Group Address Strategy

User Parameters via direct `user.lg_tv` calls from the resident script.

Suggested naming convention:

```
LG_TV_Power          (String — "Active" / "Standby")
LG_TV_App            (String — "Netflix" / "YouTube" / "Live TV" / "HDMI 1" etc.)
LG_TV_Volume         (Number — 0–100)
LG_TV_Muted          (Number — 0/1)
LG_TV_OnDuration     (Number — minutes TV has been continuously on — derived)
LG_TV_LastUpdated    (String)
```

---

## 9. Dependencies on Gold-Standard Patterns

| Pattern | Source | Applicability |
|---|---|---|
| `user.websocket` library | LogicMachine KB (Casambi) | Use directly — plain WS, no SSL |
| Library + thin resident script | Unisenza gold-standard | `user.lg_tv` + `script_resident_poll.lua` |
| `user.secrets` for client key | All gold-standard | Store `client_key` and `host` |
| `safeSetUserParam` | All gold-standard | Required |
| `isDebuggingEnabled` cached per poll | All gold-standard | Required |
| `_missingParamWarned` | All gold-standard | Required |
| Module state for duration tracking | Panasonic `_energyState` pattern | `_tv_on_since` timestamp |
| ID map with unknown ID fallback | Ecowitt/Inception pattern | App ID → display name lookup table |
| Event script for control | Panasonic gold-standard | TV control commands from C-Bus events |

---

## Action Required

1. **Assign DHCP reservation** for the TV to ensure IP stability.
2. **Enable Quick Start / network standby** on the TV so the WebSocket port remains reachable when in standby.
3. **Perform one-time SSAP pairing** — use a WebSocket client (e.g. browser DevTools → WS, or `wscat -c ws://<tv-ip>:3000`) to send the register message and save the returned `client-key` to `user.secrets`.
4. **Build app ID lookup table** — turn on the TV and query `getForegroundAppInfo` whilst opening common apps to capture the app IDs for Netflix, YouTube, Apple TV, Disney+, Live TV, HDMI inputs, etc.
5. **Write integration script** in a future session — `user.lg_tv` library + thin resident + optional event script for control.

---

## Reference

- LG WebOS SSAP protocol overview: https://webostv.developer.lge.com/develop/app-developer-guide/connection-guide
- LG WebOS service list: https://webostv.developer.lge.com/api/web-api/service-api-overview
- aiopylgtv (Python client — good SSAP reference): https://github.com/bendavid/aiopylgtv
- Home Assistant WebOS TV integration: https://github.com/home-assistant/core/tree/dev/homeassistant/components/webostv
