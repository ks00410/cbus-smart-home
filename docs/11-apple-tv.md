# Integration Research: Apple TV

**Integration #:** 11  
**Device / Service:** Apple TV — state and usage monitoring  
**Last Researched:** 2025  

---

## 1. Integration Method

**Local LAN — Apple TV companion app protocol (pyatv / MRP).**

Apple TV (4th generation and later) exposes two local network protocols:

### MRP (Media Remote Protocol)
Used by the Apple TV remote app and other companion apps. Runs on a local TCP port (varies). Requires device pairing and uses a custom binary protocol. This is the primary protocol for control and status monitoring.

### AirPlay 2
Used for media streaming. Not useful for status monitoring.

### RAOP (Remote Audio Output Protocol)
Audio streaming. Not useful for status monitoring.

### HomeKit (tvOS 11+)
Apple TV is a HomeKit hub and exposes a HomeKit Accessory Protocol (HAP) interface. State monitoring via HomeKit is possible but requires HAP implementation in Lua (very complex).

**Recommended approach for C-Bus:**

The most practical integration path is an **HTTP proxy service** using the Python library [`pyatv`](https://pyatv.dev) running on a LAN device (NAS, Raspberry Pi, or always-on computer). `pyatv` abstracts the MRP protocol and exposes a simple REST API via the companion `atvremote` HTTP server mode.

The 5500AC then polls the HTTP proxy with `socket.http` — same pattern as Shelly/OpenSprinkler.

**Alternative:** Network presence (ping) for power state only, identical to the LG TV approach. Simple but limited.

---

## 2. Connectivity Requirement

🏠 **Fully local — no internet connection required** for proxy-based integration.  
The proxy runs on the LAN and communicates with the Apple TV over the local network. No Apple ID cloud services are required for state monitoring.

---

## 3. Authentication Method

**MRP Pairing** — the proxy must complete a one-time pairing with the Apple TV by entering a PIN code displayed on the TV screen. The resulting pairing credentials are stored by the proxy and used for all subsequent connections.

After pairing, the proxy handles authentication transparently. From the 5500AC's perspective, authentication to the proxy itself can be via a simple static token or no auth (on a trusted LAN).

---

## 4. Polling vs. Event-Driven

**Polling** — 30-second resident script interval (via proxy HTTP endpoint).

The proxy can be designed to maintain a persistent connection to the Apple TV (pyatv supports event callbacks), caching the latest state. The 5500AC polls the proxy endpoint at 30-second intervals to retrieve the cached state — no per-poll latency for the MRP connection.

Alternatively, the proxy can itself push updates to the 5500AC via HTTP GET on a configured URL (requires an HTTP listener on the 5500AC — not recommended).

---

## 5. Available Data / Controllable Parameters

### Read (via pyatv proxy)

| Metric | Notes |
|---|---|
| Power state | On / Standby / Off |
| App in use | Bundle ID or display name (e.g. `com.apple.TVMovies`, "Netflix", "YouTube") |
| Media playback state | Playing / Paused / Idle / Stopped |
| Media title | Currently playing content title |
| Media type | Music / TV Show / Movie / Unknown |
| Playback position | Seconds |
| Total duration | Seconds |
| Shuffle / Repeat state | |
| Device name | |

### Write (Control via pyatv proxy)

| Action | Notes |
|---|---|
| Select menu | Navigate home screen |
| Play / Pause | Media control |
| Next / Previous | Skip tracks/chapters |
| Volume up/down | If volume control is enabled |
| Launch app | By bundle ID |
| Power on / Standby | Send sleep/wake command |

---

## 6. Estimated Implementation Difficulty

**Network ping only:** ✅ **Easy**

**Full proxy-based integration:**
- **Proxy setup:** 🟡 **Easy to Medium** — `pyatv` is well-documented and the Python HTTP server is straightforward
- **C-Bus Lua client:** 🟡 **Easy** — standard `socket.http` polling against proxy endpoint
- **Overall:** 🟠 **Medium** — requires separate infrastructure (proxy service)

---

## 7. Known Limitations and Risks

- **Proxy infrastructure required** — a separate always-on LAN device (NAS, Pi, etc.) must run the Python proxy. This is additional infrastructure to maintain.
- **Apple TV sleep state** — Apple TV in standby may take a few seconds to wake and respond to the MRP connection. The proxy handles this but may show brief gaps.
- **Protocol changes** — Apple has changed MRP and companion protocols across tvOS updates. `pyatv` maintains compatibility but may require updates after major tvOS releases.
- **App identification** — the "current app" is reported as a bundle ID which must be mapped to human-readable names for dashboard display (e.g. `com.netflix.Netflix` → "Netflix").
- **Multiple Apple TVs** — if multiple Apple TVs exist in the home, the proxy and C-Bus params should be per-device.
- **HomeKit alternative** — if a HomeKit controller is already present on the network, it may be possible to query Apple TV state via HomeKit. This avoids the proxy but HomeKit-over-LAN requires HAP implementation which is very complex in Lua.

---

## 8. Recommended C-Bus Group Address Strategy

```
AppleTV_Power         (String — "On" / "Standby")
AppleTV_App           (String — "Netflix" / "YouTube" / "Apple TV+" / "Idle")
AppleTV_PlayState     (String — "Playing" / "Paused" / "Idle")
AppleTV_MediaTitle    (String — title of currently playing content)
AppleTV_LastUpdated   (String)
```

For monitoring usage patterns (which apps, how long): store `_app_start_time` in module state and compute duration when app changes.

---

## 9. Dependencies on Gold-Standard Patterns

| Pattern | Source | Applicability |
|---|---|---|
| `socket.http` local LAN polling | Inception, Unisenza | Polling the proxy endpoint |
| `safeSetUserParam` | All gold-standard | Required |
| `isDebuggingEnabled` | All gold-standard | Required |
| Module state for duration tracking | Panasonic `_energyState` | Track `_app_start_time` per app |

---

## Action Required

1. **Decide infrastructure** — confirm availability of an always-on LAN device (NAS, Pi, etc.) to host the pyatv proxy service.
2. **Set up pyatv** — install Python pyatv on the proxy host, complete Apple TV pairing.
3. **Design proxy HTTP API** — define the JSON response format the proxy returns (matching what the Lua script expects).
4. **Write integration script** in a future session once the proxy is operational.

---

## Reference

- pyatv documentation: https://pyatv.dev
- pyatv GitHub: https://github.com/postlund/pyatv
- Apple TV protocols overview: https://pyatv.dev/documentation/protocols/
