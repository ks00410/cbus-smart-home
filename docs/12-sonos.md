# Integration Research: Sonos

**Integration #:** 12  
**Device / Service:** Sonos speakers — playback state and room/zone control  
**Last Researched:** 2025  

---

## 1. Integration Method

**Local LAN — Sonos Local Control API (S2 / latest firmware).**

Sonos exposes a local REST API introduced in firmware S2 (2020+). This replaced the older UPnP-based SOAP API (`/xml/device_description.xml`) and is the current recommended local integration method.

**API Type:** REST with Server-Sent Events (SSE) for state changes  
**Base URL:** `https://<speaker-ip>:1443` (HTTPS, self-signed cert)  
**Alternate:** `http://<speaker-ip>:1400` (HTTP, older SOAP endpoint — still works on most firmware)

### Local API v1 (Recommended)

The Sonos Local Control API provides:
- `GET /api/v1/households` — list households
- `GET /api/v1/households/<hhId>/groups` — list groups and players
- `GET /api/v1/households/<hhId>/groups/<groupId>/playback` — current playback state
- `POST /api/v1/households/<hhId>/groups/<groupId>/playback/play` — resume playback
- `POST /api/v1/households/<hhId>/groups/<groupId>/playback/pause` — pause
- `POST /api/v1/households/<hhId>/groups/<groupId>/volume` — get/set group volume
- `POST /api/v1/households/<hhId>/groups/<groupId>/playback/skipToNextTrack` — skip
- `GET /api/v1/households/<hhId>/groups/<groupId>/playbackMetadata` — now-playing metadata

The API also supports SSE subscriptions (`/subscribe`) for real-time push updates, but as with Home Connect SSE, this is difficult to consume from Lua on the 5500AC.

**Alternative: UPnP / SOAP (Legacy, simpler)**
Older Sonos UPnP API on port 1400 uses SOAP XML. More verbose to implement but HTTP-based and compatible with `socket.http`. Some Home Assistant integrations still use this for simplicity. The gold-standard approach uses REST over HTTP; UPnP/SOAP is not recommended for new implementations.

**Recommended approach:** Local API v1 via `ssl.https` against `https://<speaker-ip>:1443`, with certificate verification disabled (self-signed). Poll for playback state and metadata; use POST endpoints for control.

A reference implementation exists in the Inception repository: `Sonos_UserLibrary.lua` and `Sonos_Resident.lua`. These should be reviewed and assessed against gold-standard quality conventions before reuse.

---

## 2. Connectivity Requirement

🏠 **Fully local — no internet connection required.**  
The Sonos Local Control API operates entirely on the LAN. No Sonos cloud account is needed for local polling and control.

> **Note:** Sonos devices require a Sonos account for initial setup and some features, but the local API works independently of cloud connectivity once the system is set up.

---

## 3. Authentication Method

**No authentication required** for the local Sonos API when accessed on the same network. The API is available without credentials on the local subnet.

> The Sonos cloud API (`api.ws.sonos.com`) uses OAuth2, but this is not needed for local control.

---

## 4. Polling vs. Event-Driven

**Polling** — 30-second resident script interval.

The Local API supports SSE subscriptions for real-time state push, but implementing SSE in Lua is impractical (same limitation as Home Connect). Polling at 30-second intervals provides acceptable responsiveness for a dashboard showing current playback state and volume.

---

## 5. Available Data / Controllable Parameters

### Read

**Per Group (room or zone):**

| Metric | Notes |
|---|---|
| Playback state | `PLAYBACK_STATE_PLAYING` / `PAUSED` / `IDLE` / `BUFFERING` |
| Volume | 0–100 |
| Muted | Boolean |
| Is playing local line-in | Boolean |
| Crossfade enabled | Boolean |
| Repeat/shuffle mode | |

**Now Playing Metadata (per group):**

| Metric | Notes |
|---|---|
| Track title | String |
| Artist | String |
| Album | String |
| Service name | e.g. "Spotify", "Apple Music", "Radio" |
| Image URL | Album art URL (local or cloud) |
| Duration | Seconds |
| Position | Seconds |

**Household / System:**

| Metric | Notes |
|---|---|
| Group list | Which rooms are grouped together |
| Active rooms (playing count) | Derived |

### Write (Control)

| Action | Endpoint |
|---|---|
| Play | `POST /playback/play` |
| Pause | `POST /playback/pause` |
| Skip next | `POST /playback/skipToNextTrack` |
| Skip previous | `POST /playback/skipToPreviousTrack` |
| Set volume | `POST /volume` with `{ "volume": 50 }` |
| Mute/unmute | `POST /volume` with `{ "muted": true }` |
| Group rooms | `POST /groups` |
| Ungroup room | Group management endpoints |

---

## 6. Estimated Implementation Difficulty

🟡 **Easy to Medium.**

- Local API is clean JSON REST, no authentication needed.
- HTTPS with self-signed cert requires `ssl.https` with certificate verification disabled.
- Group/household discovery is required on first poll (similar to Inception entity discovery pattern).
- The `Sonos_UserLibrary.lua` and `Sonos_Resident.lua` in the Inception repository provide a usable reference — review and upgrade to gold-standard conventions.

---

## 7. Known Limitations and Risks

- **Self-signed certificate** — `ssl.https` must be configured to skip certificate verification for local API access.
- **Port 1443** — the local API uses HTTPS on port 1443, not the standard 443. Some firewalls may block non-standard ports.
- **Group IDs are dynamic** — Sonos group IDs change when rooms are grouped or ungrouped. The script must re-discover group IDs if they are stale, not hardcode them.
- **API version changes** — Sonos has changed the local API between firmware versions. The v1 API has been stable since 2020 but monitor for breaking changes.
- **Sonos S1 legacy devices** — older Sonos hardware running the S1 firmware uses a different (older) API. If S1 devices are present, the UPnP/SOAP API must be used for those devices.
- **Rate limits** — Sonos imposes rate limits on local API calls. Polling multiple groups rapidly may result in `429 Too Many Requests` responses. Stagger requests with brief sleeps between devices.
- **Prototype reference in repo** — `Sonos_UserLibrary.lua` in the Inception repository is a prototype-grade reference. It should be reviewed and potentially rewritten to gold-standard conventions.

---

## 8. Recommended C-Bus Group Address Strategy

Per room/zone User Parameters.

Suggested naming convention:

```
Sonos_Lounge_State       (String — "Playing" / "Paused" / "Idle")
Sonos_Lounge_Volume      (Number — 0–100)
Sonos_Lounge_Track       (String — "Song Title - Artist")
Sonos_Lounge_Service     (String — "Spotify" / "Apple Music" etc.)

Sonos_Kitchen_State      (String)
Sonos_Kitchen_Volume     (Number)

Sonos_ActiveRooms        (Number — count of rooms currently playing)
Sonos_LastUpdated        (String)
```

---

## 9. Dependencies on Gold-Standard Patterns

| Pattern | Source | Applicability |
|---|---|---|
| `ssl.https` + `ltn12` HTTPS | Panasonic gold-standard | Required — Local API uses HTTPS |
| Group/entity discovery on first poll | Inception gold-standard | Discover household/group IDs once |
| `safeSetUserParam` | All gold-standard | Required |
| `isDebuggingEnabled` cached per poll | All gold-standard | Required |
| `_missingParamWarned` | All gold-standard | Required |
| Module state for group ID caching | Inception `_entityMap` pattern | Cache discovered group IDs |

---

## Action Required

1. **Review `Sonos_UserLibrary.lua`** in the Inception repository — assess against gold-standard conventions and decide whether to refactor or rewrite.
2. **Identify room names** and map to desired C-Bus UserParam names.
3. **Confirm all Sonos devices are S2** (2020+ firmware) — if any are S1, a separate handling path is needed.
4. **Test SSL cert skip configuration** for `ssl.https` on the 5500AC firmware version in use.
5. **Write integration script** in a future session.

---

## Reference

- Sonos Local Control API: https://docs.sonos.com/reference/local-control-api
- Sonos Local Control overview: https://docs.sonos.com/docs/local-control
- Home Assistant Sonos integration: https://github.com/home-assistant/core/tree/dev/homeassistant/components/sonos
