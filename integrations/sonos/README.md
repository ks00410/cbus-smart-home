# Sonos — C-Bus Integration

Local LAN integration for Sonos S2 speakers using the [Sonos Local Control API v1](https://docs.sonos.com/docs/local-control).
No proxy, no cloud, no Sonos account required at runtime.

## Files

| File | Purpose |
|---|---|
| `user_library_sonos.lua` | User Library — load as `user.sonos` |
| `script_resident_poll.lua` | Resident script — 30-second poll cycle |

## How it works

On first poll the script discovers the Sonos household and all groups by querying
each IP in `DISCOVERY_IPS` until one responds. Group IDs, player names, and the
working base URL are cached in module state for subsequent polls.

If a group poll returns a 404 (stale group IDs — rooms were regrouped), the cache
is invalidated and re-discovery runs on the next poll cycle.

## Setup

### 1. Secrets

No credentials are required for the Sonos Local API on the LAN. No `user.secrets`
entry is needed for Sonos.

### 2. IPs

The five speaker IPs are configured in `DISCOVERY_IPS` in the library.
**Assign DHCP reservations for all Sonos speakers** so their IPs never change.

Current IPs configured:
- `192.168.1.52`
- `192.168.1.80`
- `192.168.1.93`
- `192.168.1.133`
- `192.168.1.72`

### 3. C-Bus User Parameters

Create the following User Parameters on network 0. Group/room names come from
your Sonos app room names — spaces and special characters become underscores.

**Per-room params** (one set per Sonos group/room):
```
Sonos_<RoomName>_State    (String — "Playing" / "Paused" / "Idle" / "Buffering")
Sonos_<RoomName>_Volume   (Number — 0–100)
Sonos_<RoomName>_Muted    (Number — 0/1)
Sonos_<RoomName>_Track    (String — "Song Title – Artist")
Sonos_<RoomName>_Service  (String — "Spotify" / "Apple Music" / "Radio" etc.)
```

**Global params:**
```
Sonos_ActiveRooms   (Number — count of rooms currently playing)
Sonos_Status        (String — "Online" / "Offline")
Sonos_LastUpdated   (String)
Debug Logging       (Boolean/Number — set to 1 for verbose output)
```

For example, if your rooms are "Lounge" and "Kitchen":
```
Sonos_Lounge_State, Sonos_Lounge_Volume, Sonos_Lounge_Muted
Sonos_Lounge_Track, Sonos_Lounge_Service
Sonos_Kitchen_State, Sonos_Kitchen_Volume ...
```

### 4. Scripts

1. Load `user_library_sonos.lua` as a User Library named `sonos`.
2. Create a Resident script with sleep interval **30 seconds**, paste `script_resident_poll.lua`.

## Control

From an event script or the Lua console:

```lua
require("user.sonos")

sonos.Play("Lounge")              -- Resume playback
sonos.Pause("Lounge")             -- Pause
sonos.Next("Lounge")              -- Skip to next track
sonos.SetVolume("Lounge", 40)     -- Set volume 0–100
sonos.SetMute("Lounge", true)     -- Mute
sonos.SetMute("Lounge", false)    -- Unmute
```

Room names are matched to Sonos group names (spaces → underscores, case-insensitive).

## Notes

- **S2 firmware only.** This integration uses the Sonos Local Control API v1 which
  requires S2 firmware (2020+). Older S1 hardware is not supported by this implementation.
- **Self-signed certificate.** The Sonos Local API uses HTTPS with a self-signed cert.
  `verify = "none"` is set in the library to allow connections on the LAN.
- **Group IDs are dynamic.** When you group or ungroup rooms in the Sonos app, group IDs
  change. The library detects 404 errors and re-discovers automatically on the next poll.
- **Port 1443.** The local API uses HTTPS on port 1443 (not standard 443).
