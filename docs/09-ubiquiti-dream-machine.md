# Integration Research: Ubiquiti UniFi Dream Machine

**Integration #:** 9  
**Device / Service:** Ubiquiti UniFi Dream Machine — device presence detection and network health  
**Last Researched:** 2025  

---

## 1. Integration Method

**Local LAN — UniFi Network Controller REST API.**

The UniFi Dream Machine (UDM / UDM-Pro / UDM-SE) runs the UniFi Network application internally, which exposes a REST API. This API is used by the UniFi web and mobile interfaces and is fully accessible on the local network without cloud involvement.

**Base URL:** `https://<udm-ip>:443/proxy/network/api/s/default/`  
(Or `https://<udm-ip>/proxy/network/api/s/<site>/` for named sites)

**Key endpoints:**
- `POST /api/auth/login` — authenticate and obtain session cookie
- `GET /proxy/network/api/s/default/stat/sta` — all currently connected clients (including MAC, IP, hostname, RSSI, last seen)
- `GET /proxy/network/api/s/default/stat/alluser` — all known clients (historical, includes last seen time)
- `GET /proxy/network/api/s/default/stat/health` — network subsystem health status
- `GET /proxy/network/api/s/default/stat/sys` — system metrics (CPU, memory, uptime)
- `GET /proxy/network/api/s/default/stat/wan` — WAN/internet status (uptime, latency, throughput)

### Presence Detection Approach

Presence detection is based on tracking specific MAC addresses (mobile phones) in the `stat/sta` (currently connected stations) endpoint. A device is considered **home** if its MAC address appears in the connected station list. It is considered **away** if absent.

**Important considerations:**
- iOS and Android devices randomise their MAC address per Wi-Fi network as of iOS 14+ and Android 10+. The device must have **Private Address (MAC randomisation) disabled** for the home Wi-Fi network, or the network must identify devices by hostname/IP instead of MAC.
- Alternatively, use the `stat/alluser` endpoint with a `last_seen` timestamp comparison — if the device was last seen within the last N minutes, it is considered present.
- RSSI value can optionally be used to estimate rough in-home location (near AP = in home, weak/absent = away).

---

## 2. Connectivity Requirement

🏠 **Fully local — no internet connection required.**  
The UniFi Network Controller API is served directly by the UDM on the LAN. Cloud connectivity to Ubiquiti's services is not required for API access.

> **Note:** The UDM uses a self-signed certificate for HTTPS. The Lua SSL library (`ssl.https`) must be configured to skip certificate verification, or the certificate must be accepted. On a trusted LAN, skipping verification is acceptable: `ssl.https.verify = "none"` or equivalent LuaSec configuration.

---

## 3. Authentication Method

**Session-based — username/password login returning a session cookie.**

Two authentication flows exist depending on UDM firmware version:

### Modern UniFi OS (UDM firmware 1.9+):
- `POST https://<udm-ip>/api/auth/login` with `{"username": "...", "password": "...", "remember": true}`
- Returns `Set-Cookie: TOKEN=<jwt>` header
- JWT token used in `Cookie: TOKEN=<jwt>` header for subsequent requests
- Token lifespan: varies (typically hours); re-authenticate on 401

### Legacy (older firmware):
- `POST https://<udm-ip>/api/login`
- Session cookie returned

The Lua HTTP client must capture the response cookie and include it in subsequent requests. This requires parsing the `Set-Cookie` response header — achievable with `ltn12` sink and manual header inspection.

Credentials in `user.secrets`:
```lua
secrets.unifi = {
  host     = "192.168.1.1",
  username = "admin",
  password = "your-password",
  site     = "default"
}
```

Session token is cached in module state (`_sessionToken`) and refreshed automatically on 401 or expiry.

---

## 4. Polling vs. Event-Driven

**Polling** — 60-second resident script interval.

The UniFi API is request/response only — no webhook or event push capability is available without third-party software. A 60-second polling interval provides acceptable presence detection latency (devices absent for 1–2 minutes after disconnecting from Wi-Fi before polling confirms absence).

For tighter presence detection, a 30-second interval is acceptable.

---

## 5. Available Data / Controllable Parameters

### Read

**Presence Detection (per tracked individual):**

| Metric | Notes |
|---|---|
| Presence boolean | 0=away, 1=home |
| Last seen timestamp | ISO date string |
| Connected AP name | Which access point the phone is connected to (rough location) |
| Signal strength (RSSI) | dBm — stronger = closer to AP |
| IP address | Current LAN IP |
| Device hostname | As reported by device |

**Internet / WAN Health:**

| Metric | Notes |
|---|---|
| WAN status | Up / Down |
| WAN latency | ms (ping to gateway) |
| WAN download throughput | Mbps (measured) |
| WAN upload throughput | Mbps |
| WAN uptime | Seconds since last reconnect |

**Network Health:**

| Metric | Notes |
|---|---|
| LAN subsystem status | OK / Warning / Error |
| WLAN subsystem status | OK / Warning / Error |
| WAN subsystem status | OK / Warning / Error |
| Connected client count | Number of associated devices |

**System:**

| Metric | Notes |
|---|---|
| CPU usage | % |
| Memory usage | % |
| UDM uptime | Seconds |

### Write (Control)

The UniFi API supports limited network management operations (block/unblock clients, provision devices), but these are not relevant to this use case. **This integration is read-only for monitoring purposes.**

---

## 6. Estimated Implementation Difficulty

🟠 **Medium.**

- Local HTTPS with self-signed certificate requires LuaSec configuration.
- Session cookie management requires parsing `Set-Cookie` response headers and re-attaching the cookie on subsequent requests.
- MAC address tracking requires configuration of which MACs to monitor.
- MAC randomisation on mobile devices requires per-person setup steps (disable private address on home Wi-Fi).

The actual API response parsing is straightforward JSON.

---

## 7. Known Limitations and Risks

- **MAC randomisation** — modern iOS and Android randomise MAC per SSID. Users must disable "Private Wi-Fi Address" on the home SSID for their phone for reliable detection. This is a per-user setup step.
- **Alternative: hostname-based tracking** — if MAC is randomised, match by device hostname (less reliable as hostnames can change or be absent).
- **Departure detection lag** — when a phone leaves the network, it takes time (typically 1–5 minutes depending on Wi-Fi beacon/probe interval) for the controller to mark it as disconnected. The `last_seen` approach with a 5-minute window reduces false negatives.
- **Self-signed certificate** — requires SSL verification to be disabled or the certificate to be trusted. Disabling verification is acceptable on a LAN.
- **API changes between firmware versions** — Ubiquiti has changed the authentication endpoint between major firmware versions. The script should handle both authentication paths.
- **Guest network isolation** — devices on a guest SSID may not appear in the `stat/sta` endpoint depending on UniFi guest network configuration.

---

## 8. Recommended C-Bus Group Address Strategy

User Parameters per tracked person plus global network health params.

Suggested naming convention:

```
Person_Kyle_Home         (Number — 0=away, 1=home)
Person_Kyle_LastSeen     (String — "05 Jun 2025, 08:32")
Person_Other_Home        (Number)
Person_Other_LastSeen    (String)

Network_WAN_Status       (String — "Up" / "Down")
Network_WAN_Latency      (Number — ms)
Network_Client_Count     (Number)
Network_LastUpdated      (String)
```

For C-Bus scene automation based on presence (e.g. arriving home triggers lighting scenes), write to a C-Bus Group Address from an event script that watches the UserParam change.

---

## 9. Dependencies on Gold-Standard Patterns

| Pattern | Source | Applicability |
|---|---|---|
| `ssl.https` + `ltn12` HTTPS | Panasonic gold-standard | Required — UDM uses HTTPS |
| Session token caching in module state | Panasonic `_cachedSession` | Adapt for cookie-based session |
| `safeSetUserParam` | All gold-standard | Required |
| `isDebuggingEnabled` cached per poll | All gold-standard | Required |
| `_missingParamWarned` | All gold-standard | Required |
| `user.secrets` isolation | All gold-standard | Required |
| Device list config table | Panasonic zone config pattern | Person → MAC address map |

---

## Action Required

1. **Disable MAC randomisation** — for each person to track, disable Private Wi-Fi Address on their phone for the home Wi-Fi SSID.
2. **Note MAC addresses** — record the fixed MAC (or IP/hostname) for each tracked person's primary device.
3. **Confirm UDM firmware version** — determine which authentication endpoint to use.
4. **Write integration script** in a future session — this research is sufficient to proceed.
