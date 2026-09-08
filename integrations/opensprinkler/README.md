# OpenSprinkler — C-Bus Integration

Local HTTP REST integration for an [OpenSprinkler](https://opensprinkler.com) irrigation controller.

## Files

| File | Purpose |
|---|---|
| `user_library_opensprinkler.lua` | User Library — load as `user.opensprinkler` |
| `script_resident_poll.lua` | Resident script — 60-second poll cycle |
| `script_event_run_zone.lua` | Event script — manual zone run/stop from dashboard |

## Setup

### 1. Secrets

Add the following to your `user.secrets` library:

```lua
secrets.opensprinkler = {
  host         = "192.168.1.119",   -- DHCP reservation recommended
  password_md5 = "a6c952bb16c8d37b",  -- MD5 hash of your device password
}
```

**Generating the MD5 hash:**

The OpenSprinkler API requires the password as an MD5 hash in the URL.
The default password is `opendoor`. To compute its MD5:

```bash
# macOS / Linux
echo -n "opendoor" | md5sum
# Output: a6c952bb16c8d37b...  (use the first 16 hex chars, or the full 32)
```

Or use any online MD5 tool — search "MD5 hash generator", enter your password,
copy the full 32-character hex result.

> **Note:** The MD5 hash is transmitted in the URL over plain HTTP on the LAN.
> This is the OpenSprinkler API's design. It is acceptable on a trusted private LAN.

### 2. C-Bus User Parameters

Create the following User Parameters on network 0. Zone params are named from
the zone names configured in OpenSprinkler — spaces are replaced with underscores.

**System params:**
```
Irrigation_WaterLevel       (Number — weather adjustment %, 0–200)
Irrigation_RainSensor       (Number — 0/1)
Irrigation_RainDelay        (Number — seconds remaining, 0=inactive)
Irrigation_LastRun          (String — e.g. "Front Lawn ran for 5m, ended 08:45")
Irrigation_LastUpdated      (String)
Debug Logging               (Boolean/Number — set to 1 for verbose output)
```

**Per-zone params** (one pair per zone, named from controller zone names):
```
Irrigation_<ZoneName>_Active    (Number — 0=off, 1=running)
Irrigation_<ZoneName>_Remaining (Number — seconds left in current run)
```

For example, if your zones are named "Front Lawn" and "Back Garden":
```
Irrigation_Front_Lawn_Active
Irrigation_Front_Lawn_Remaining
Irrigation_Back_Garden_Active
Irrigation_Back_Garden_Remaining
```

**For manual zone control (event script):**
```
Irrigation_RunZone  (Number — write zone number to run, 0 to stop all)
```

### 3. Scripts

1. Load `user_library_opensprinkler.lua` as a User Library named `opensprinkler`.
2. Create a Resident script with sleep interval **60 seconds**, paste `script_resident_poll.lua`.
3. *(Optional)* Create an Event script on `Irrigation_RunZone` parameter write,
   paste `script_event_run_zone.lua`.

## Control

From an event script or the Lua console:

```lua
require("user.opensprinkler")

sprinkler.RunZone(2, 300)    -- Run zone 2 for 5 minutes
sprinkler.StopZone(2)        -- Stop zone 2
sprinkler.StopAll()          -- Stop all zones immediately
```

## Notes

- Zone names are discovered automatically from the controller on first poll and cached
  for the session. Renaming zones in OpenSprinkler takes effect on the next restart.
- The water level reflects the OpenSprinkler weather-adjustment percentage (0–200%).
  100% = full watering, 0% = skip, 200% = double watering.
- Rain delay is in seconds. 0 means no delay is active.
