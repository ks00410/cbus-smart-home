# Integration Research: LG TV

**Integration #:** 10  
**Device / Service:** LG Smart TV — usage and watch-time metrics capture  
**Last Researched:** 2025  

---

## 1. Integration Method

**Local LAN — LG WebOS TV REST API (LG Connect Apps / SSAP protocol).**

LG Smart TVs running WebOS (2014+) expose a WebSocket-based control API called **SSAP** (Simple Service Access Protocol) on port 3000. This API is used by the LG ThinQ app and is available over the local network.

**Connection:** WebSocket to `ws://<tv-ip>:3000`  
**Protocol:** JSON messages over WebSocket

This is **not** a REST API and not directly accessible via Lua's `socket.http`. Lua on the 5500AC does not have a native WebSocket client library. Options:

### Option A: LG ThinQ Cloud API
LG's cloud API (`openapi.thinq1.com` / `thinq2-kr.lgthinq.com`) can be used to query TV status and send some commands. However:
- Authentication is complex (requires app client tokens and country-specific endpoints)
- Cloud-dependent
- Not well-documented for TVs specifically
- More commonly used for white goods (washing machines, fridges)

### Option B: LG WebOS REST via `webosTVcontrol` or equivalent HTTP polling
Some LG WebOS TVs also respond to basic HTTP requests on port 8080 for status queries in older firmware. This is unreliable across models.

### Option C: Network Presence + Power State Inference
The simplest and most reliable approach: **detect TV presence via network ping or ARP**. When the TV is on, it maintains a network connection and responds to ping. When off (standby), it typically does not respond (unless Wake-on-LAN is enabled).

- Ping `<tv-ip>` — if response received, TV is on; no response, TV is off.
- Lua `os.execute("ping -c1 -W1 <ip> > /dev/null 2>&1")` returns exit code 0 if up, non-zero if down.
- This provides a reliable **power on/off state** without requiring WebSocket.

### Option D: WebSocket via Intermediate Proxy
An intermediate service (e.g. a small Python script or Node.js server running on a Raspberry Pi or NAS on the LAN) can bridge WebSocket to HTTP REST, allowing the 5500AC to use standard HTTP polling against the proxy. This adds infrastructure complexity but enables full LG API access.

**Recommended approach (pragmatic):** Start with **Option C (network presence / ping)** for power state. If richer data (current app, volume, input) is needed, implement **Option D (proxy bridge)** in a later phase.

---

## 2. Connectivity Requirement

🏠 **Fully local — no internet connection required** for network ping approach.  
☁️ **Internet required** for LG ThinQ cloud API approach.

The network ping approach requires only that the TV and the 5500AC are on the same LAN.

---

## 3. Authentication Method

**WebSocket API (if used):** First connection to the TV requires a **pairing handshake** — the TV displays a prompt asking the user to accept or deny the connection request. Once accepted, a **client key** is returned and stored. Subsequent connections use this client key to skip the pairing prompt.

**Network ping approach:** No authentication required.

---

## 4. Polling vs. Event-Driven

**Polling** — 60-second resident script interval.

For power state via ping: a 30–60 second ping poll is appropriate for a "is the TV on?" indicator. False negatives may occur briefly when the TV is in standby but the network interface is still active.

---

## 5. Available Data / Controllable Parameters

### Via Network Ping (Recommended for initial implementation)

| Metric | Notes |
|---|---|
| TV power state | 0=off/standby, 1=on (network reachable) |
| Last state change timestamp | Derived — log when state transitions between on/off |

### Via WebSocket SSAP (Full API — requires proxy or native WebSocket support)

| Metric | Notes |
|---|---|
| Power state | On / Off / Standby |
| Current input source | HDMI1, HDMI2, TV, etc. |
| Current app | YouTube, Netflix, Disney+, Live TV, etc. |
| Volume level | 0–100 |
| Muted state | Boolean |
| Channel (if TV tuner active) | Channel number and name |
| 3D mode | Boolean (older models) |

### Write (Control — WebSocket SSAP)

| Action | SSAP URI |
|---|---|
| Power off | `ssap://system/turnOff` |
| Change input | `ssap://tv/switchInput` |
| Set volume | `ssap://audio/setVolume` |
| Mute/unmute | `ssap://audio/setMute` |
| Launch app | `ssap://system.launcher/launch` |
| Play/Pause | `ssap://media.controls/play`, `/pause` |
| Send remote key | `ssap://com.webos.service.ime/sendEnterKey` etc. |

---

## 6. Estimated Implementation Difficulty

**Network ping approach:** ✅ **Easy** — single `os.execute` call, no API, no parsing.

**Full WebSocket SSAP integration (with proxy):** 🔴 **Very Hard** — requires:
- Intermediate proxy service (additional infrastructure)
- Proxy development and maintenance
- WebSocket pairing and client key management
- Not native to 5500AC Lua environment

**Recommendation:** Implement network ping for power state first. Document proxy approach for future phase if richer data is required.

---

## 7. Known Limitations and Risks

- **Network ping limitations** — TV may remain network-reachable for a short period after power-off due to network standby. Conversely, some TVs go into deep sleep and stop responding to pings while still "available" via WoL. A consistent pattern must be established through testing.
- **WebOS not accessible from Lua** — without a proxy bridge, full TV API control/monitoring is not achievable from the 5500AC Lua environment.
- **LG ThinQ cloud API complexity** — the cloud API is documented but uses a multi-step authentication with country-specific server selection and app signing. It is disproportionately complex for a TV on/off indicator.
- **Model variation** — SSAP API capabilities vary between WebOS versions (WebOS 1.x through WebOS 23+). Test against the specific TV model.

---

## 8. Recommended C-Bus Group Address Strategy

```
LG_TV_Power          (Number — 0=off, 1=on)
LG_TV_LastSeen       (String — last time TV was detected as on)
LG_TV_OnDuration     (Number — minutes TV has been continuously on — derived)
```

If proxy-based full integration is implemented later:
```
LG_TV_Input          (String — "HDMI1", "Netflix", etc.)
LG_TV_Volume         (Number)
LG_TV_App            (String)
```

---

## 9. Dependencies on Gold-Standard Patterns

| Pattern | Source | Applicability |
|---|---|---|
| `os.execute` for system ping | Standard Lua | Trivial — no library needed |
| Module state for on-duration tracking | Panasonic `_energyState` pattern | Track `_tv_on_since` timestamp |
| `safeSetUserParam` | All gold-standard | Required |
| `isDebuggingEnabled` cached per poll | All gold-standard | Required |

---

## Action Required

1. **Implement network ping approach** first — confirm that the TV IP is stable (DHCP reservation recommended) and that it responds to ping when on and does not when off/standby.
2. **Test standby behaviour** — determine whether the TV remains pingable in standby mode (some LG TVs do with Quick Start enabled). Adjust detection logic if needed.
3. **Evaluate proxy option** — if usage/watch-time metrics (current app, duration per app) are required, design a lightweight proxy service (Python + aiohttp on a NAS or Pi).
4. **Write integration script** in a future session.
