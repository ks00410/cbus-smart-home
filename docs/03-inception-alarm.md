# Integration Research: Inception Alarm System

**Integration #:** 3  
**Device / Service:** Inner Range Inception security and access control system  
**Last Researched:** 2025  

---

## 1. Integration Method

**Local LAN — Inner Range Inception REST API** with HTTP long-polling.

The gold-standard `Cbus-Inception` integration implements this fully. The Inception controller exposes a REST API over plain HTTP on the local network. The key mechanism is a **long-poll** `POST /monitor-updates` endpoint that holds the connection open for up to 60 seconds, returning immediately when any subscribed state changes. This is event-driven in effect — the 5500AC receives updates within seconds of a state change rather than waiting for the next poll interval.

Endpoints used:
- `GET /api/v1/system-info` — system name and serial number (discovery, startup only)
- `GET /control/area/summary` — all areas with current state
- `GET /control/door/summary` — all doors with current state
- `GET /control/input/summary` — all inputs/zones with current state
- `GET /control/output/summary` — all outputs with current state
- `POST /monitor-updates` — long-poll subscription for state change events
- `POST /control/area/{id}/activity` — arm/disarm an area
- `POST /control/door/{id}/activity` — lock/unlock/open a door
- `POST /control/output/{id}/activity` — control an output

**Assessment:** The existing integration is complete and production-quality. Review whether the current `MONITOR_CONFIG` and C-Bus User Params match the live Inception installation's entity names exactly. An entity name mismatch results in a silent fail (warning logged at startup only).

---

## 2. Connectivity Requirement

🏠 **Fully local — no internet connection required.**  
All communication is directly to the Inception controller on the LAN. The Inception system operates entirely independently of cloud services for this integration.

---

## 3. Authentication Method

**Static API Token** — `APIToken <token>` in the `Authorization` HTTP header.

The API token is generated in the Inception web interface under **System → Users → API Users**. It is stored in `user.secrets` on the 5500AC:

```lua
secrets.inception = {
  API_ROOT  = "http://192.168.1.x/api/v1",
  api_token = "your-token-here"
}
```

No token refresh or expiry management is required — the token is static until revoked in the Inception UI.

---

## 4. Polling vs. Event-Driven

**Effectively event-driven** via HTTP long-polling.

The resident script runs with a **0 or 1 second sleep interval** — the actual update frequency is governed by the Inception server, not the timer. The `POST /monitor-updates` request blocks for up to 60 seconds; the Inception server responds immediately when a subscribed state changes (door opens, alarm triggered, zone sealed, etc.), or returns an empty body after 60 seconds if nothing changed.

This means the 5500AC receives alarm and access events within approximately 1 second of them occurring, making this integration effectively real-time.

Subscriptions per long-poll:
- Area state changes (`MonitorEntityStates` for areas)
- Door state changes (`MonitorEntityStates` for doors)
- Input/zone state changes (`MonitorEntityStates` for inputs)
- Output state changes (`MonitorEntityStates` for outputs)
- Live review events (`LiveReviewEvents` — security and access event log)
- Activity progress (`ActivityProgress` — arm/disarm confirmation feedback)

---

## 5. Available Data / Controllable Parameters

### Read (State Monitoring)

All states are decoded from bitmask integers into human-readable dash-separated strings (e.g. `"Armed - Away Arm"`, `"Locked - Closed"`).

**Areas:**

| State | Example Values |
|---|---|
| Arm state | `"Armed"`, `"Disarmed"`, `"Armed - Away Arm"`, `"Armed - Stay Arm"`, `"Armed - Sleep Arm"` |
| Alarm active | Includes `"Alarm"` in state string |
| Entry/Exit delay | Includes `"Entry Delay"` / `"Exit Delay"` |

**Doors:**

| State | Example Values |
|---|---|
| Lock/unlock state | `"Locked - Closed"`, `"Unlocked - Open"`, `"Locked Out"` |
| Forced/held open | Includes `"Forced"` / `"Held Open Too Long"` |

**Inputs / Zones:**

| State | Example Values |
|---|---|
| Sensor state | `"Sealed"`, `"Active"`, `"Tamper"`, `"Isolated"` |

**Outputs:**

| State | Example Values |
|---|---|
| Output state | `"On"`, `"Off"` |

**Review Events:**

| Parameter | C-Bus UserParam | Notes |
|---|---|---|
| Last security event | `last_alarm_event` | Description + who + timestamp string |

**Activity Progress:**

| Parameter | C-Bus UserParam | Notes |
|---|---|---|
| Arm/disarm result | `alarmstate_detail` | "Success" or "Failed: reason" |

### Write (Control)

| Action | Method |
|---|---|
| Arm area (Away) | `inception.Control_Area(id, "Arm")` |
| Arm area (Stay) | `inception.Control_Area(id, "ArmStay")` |
| Arm area (Sleep) | `inception.Control_Area(id, "ArmSleep")` |
| Disarm area | `inception.Control_Area(id, "Disarm")` |
| Lock door | `inception.Control_Door(id, "Lock")` |
| Unlock door | `inception.Control_Door(id, "Unlock")` |
| Open door (access grant) | `inception.Control_Door(id, "Open")` |
| Timed unlock | `inception.Control_Door(id, "TimedUnlock", seconds)` |
| Lockout door | `inception.Control_Door(id, "Lockout")` |
| Output on/off/toggle/pulse | `inception.Control_Output(id, "On"/"Off"/"Toggle"/"Pulse")` |

Entity GUIDs are resolved by friendly name using `inception.GetEntityId(type, name)` — no hardcoding of GUIDs in event scripts.

---

## 6. Estimated Implementation Difficulty

✅ **Already implemented** — gold-standard library (`user.inception`) is complete and production-quality.

For any extension (e.g. monitoring additional entity types, custom event filtering): **Easy** — follows established patterns.

---

## 7. Known Limitations and Risks

- **Inception API user permissions** — the API token belongs to a specific Inception user account. That user must have permissions to view and control the relevant entities. Entities the user cannot see will not appear in discovery and will produce a warning log.
- **Long-poll TCP connection** — the 5500AC holds an open HTTP connection for up to 60 seconds. This is intentional and supported by the Inception API. No firewall rules should terminate long-lived connections to the Inception controller.
- **Entity name sensitivity** — `MONITOR_CONFIG` entity names must exactly match the names in Inception (case-sensitive). A mismatch results in the entity not being monitored (warning logged at startup).
- **No encryption** — the local API uses plain HTTP. Acceptable on a trusted LAN but note that credentials (API token) are transmitted in headers in plaintext.
- **Backoff on unreachable** — consecutive failures trigger exponential backoff (30s → 60s → 120s → 300s). During backoff, no state updates are received. This is intentional to avoid log flooding during an outage.
- **Activity feedback latency** — arm/disarm activity confirmation is received via the long-poll and may take several seconds depending on access control hardware response time.

---

## 8. Recommended C-Bus Group Address Strategy

Primary storage is via User Parameters (String type for state descriptions). Monitoring is by human-readable state strings which can be evaluated in dashboard display rules.

Suggested User Parameter naming convention (already in use):

```
alarmstate          (String — area arm state, e.g. "Armed - Away Arm")
garagedoor          (String — door state, e.g. "Locked - Closed")
security_zone1      (String — input state, e.g. "Sealed")
security_zone2      (String — input state)
cctv_output         (String — output state, e.g. "On")
last_alarm_event    (String — latest security/access event description)
alarmstate_detail   (String — arm/disarm activity result)
Debug Logging       (Boolean — enables verbose debug output)
```

For dashboard arming controls, write to a C-Bus Group Address or UserParam that triggers an event script calling `inception.Control_Area()`.

---

## 9. Dependencies on Gold-Standard Patterns

| Pattern | Source | Applicability |
|---|---|---|
| Local LAN HTTP with `socket.http` | Inception gold-standard | Direct — already in use |
| Long-poll pattern with configurable timeout | Inception gold-standard | `HTTP_TIMEOUT_LONGPOLL = 61` |
| Exponential backoff | Inception gold-standard | `_recordFailure()` / `_recordSuccess()` |
| `safeSetUserParam` | All gold-standard | Already in use |
| `isDebuggingEnabled` cached per poll | All gold-standard | Already in use |
| `_missingParamWarned` flood suppression | All gold-standard | Already in use |
| `user.secrets` isolation | All gold-standard | Already in use |
| Entity auto-discovery and GUID resolution | Inception gold-standard | `_discoverEntities()` / `GetEntityId()` |
| Bitmask decoding to human-readable strings | Inception gold-standard | `decodeBitmask()` |
| `timeSinceUpdate` token advancing | Inception gold-standard | Ensures only new events received per poll |

---

## Action Required

1. **Confirm entity names** — verify that the `MONITOR_CONFIG` area, door, input, and output names in `Resident-LongPoll.lua` exactly match the entity names configured in the live Inception installation.
2. **Create C-Bus User Params** — ensure all required params (listed in section 8) exist in the C-Bus project with correct names and types.
3. **No script modifications required** — the integration handles all use cases including arm/disarm, door control, zone monitoring, and live event streaming.
