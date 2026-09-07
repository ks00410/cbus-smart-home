# Integration Research: Asko Washing Machine (ConnectLife)

**Integration #:** 7  
**Device / Service:** Asko washing machine via ConnectLife cloud platform  
**Last Researched:** 2025  

---

## 1. Integration Method

**Cloud API — ConnectLife REST API.**

Asko appliances (washing machines, dryers, dishwashers) connect to the cloud via the **ConnectLife** platform, which is a Haier-owned appliance connectivity ecosystem. Asko is a brand owned by Gorenje/Haier Group.

### ConnectLife API

ConnectLife exposes a documented (though not publicly published) REST API used by the ConnectLife mobile app. Several open-source implementations exist, most notably the Home Assistant [ConnectLife integration](https://github.com/oyvindwe/connectlife-ha).

**Base URL:** `https://connectlife.haier.com`  
**Authentication:** Username/password → OAuth2 access token + refresh token  
**Key endpoints:**
- `GET /api/v1/appliance` — list of registered appliances with device IDs
- `GET /api/v1/appliance/<device_id>/status` — current appliance status
- `PUT /api/v1/appliance/<device_id>/command` — send control commands

Appliance status is represented as a flat key-value map of **property codes** (e.g. `f54` = wash program, `f11` = door locked). The property codes are appliance-specific and documented in the ConnectLife HA integration's device YAML files.

**Asko W/M property codes (examples from ConnectLife HA):**

| Code | Description | Values |
|---|---|---|
| `f11` | Door lock | 0=unlocked, 1=locked |
| `f37` | Program | 0=cotton, 1=synthetics, etc. |
| `f38` | Temperature | Numeric °C |
| `f40` | Spin speed | rpm |
| `f47` | Running status | 0=off, 1=running, 2=paused, etc. |
| `f54` | Time remaining | Minutes |
| `f103` | Wash complete notification | 0/1 |

> **Note:** Property codes vary between appliance models. The ConnectLife HA integration maintains a community-sourced YAML dictionary of codes per model. Check the HA integration repository for the specific Asko washing machine model in use.

---

## 2. Connectivity Requirement

☁️ **Internet connection required.**  
The ConnectLife API is a cloud service. There is no known local LAN API or Zigbee/Z-Wave radio in Asko appliances for local control. An internet connection is required for all status polling and control.

---

## 3. Authentication Method

**OAuth2** — username/password login to obtain access and refresh tokens.

Flow:
1. `POST /api/v1/user/login` with email and password → returns `access_token` and `refresh_token`
2. Access token used as `Bearer` in all subsequent requests
3. Refresh token used to obtain new access token when expired

The access token expires (typically in hours). The Lua library must implement token refresh using the same pattern as the Panasonic integration (`P.RefreshAccessToken()`).

Credentials stored in `user.secrets`:
```lua
secrets.connectlife = {
  email         = "your@email.com",
  password      = "your-password",
  device_id     = "your-appliance-device-id",
  access_token  = "",   -- populated after first login
  refresh_token = ""    -- populated after first login
}
```

> **Initial token generation** — as with Panasonic, a Python helper script (run on a desktop) should be used to perform the initial login and save the refresh token. The 5500AC then uses the refresh token to maintain a valid session.

---

## 4. Polling vs. Event-Driven

**Polling** — relatively low frequency appropriate.

The ConnectLife API does not offer push notifications or webhooks. Recommended polling intervals:
- **When appliance is idle:** Every 5 minutes (no useful state change expected)
- **When appliance is running:** Every 60 seconds (to track time remaining and program state)

Implement a **state-aware polling interval** — if the last status showed `running_status = running`, poll every 60 seconds; if `off`, poll every 5 minutes. This reduces unnecessary API calls. Use module-level state (`_lastStatus`) to track the previous state between polls.

---

## 5. Available Data / Controllable Parameters

### Read (Status)

| Metric | Notes |
|---|---|
| Running status | Off / Running / Paused / Finished / Error |
| Door locked | Boolean |
| Current wash program | String (Cotton, Synthetics, Delicates, etc.) |
| Wash temperature | °C |
| Spin speed | RPM |
| Time remaining | Minutes |
| Wash complete / cycle end | Boolean / notification flag |
| Error code | Numeric — look up in model documentation |

### Write (Control)

| Action | Notes |
|---|---|
| Start wash | Requires program, temperature, spin selection |
| Pause / Resume | |
| Cancel / Stop | |
| Set program parameters | Program, temperature, spin speed |
| Delay start | Set timer for future start |

> **Practical limitation:** Start commands require the door to be physically closed and loaded. In practice, the dashboard is more useful for **monitoring** (is the wash done? time remaining?) than for remote start.

---

## 6. Estimated Implementation Difficulty

🟠 **Hard.**

Challenges:
- ConnectLife API is not officially documented for third parties; reverse-engineered from app traffic and the Home Assistant integration.
- Property codes are model-specific and require mapping from the HA integration YAML files.
- OAuth2 token management must be implemented from scratch (no existing gold-standard equivalent for this platform).
- API may change without notice as it is a private commercial platform.
- Login endpoint and token format have changed at least once; the HA integration has had breaking changes.

**Recommended approach for initial implementation:** Read-only monitoring only (running status, time remaining, cycle complete). Control can be added in a later phase.

---

## 7. Known Limitations and Risks

- **Undocumented API** — no official developer agreement or stability guarantees. API changes may break the integration without warning.
- **Cloud dependency** — no local fallback whatsoever.
- **Password storage** — requires storing ConnectLife account password (or tokens derived from it) on the 5500AC in `user.secrets`. Use a dedicated account if possible.
- **Property code fragmentation** — appliance property codes are model-specific. Codes must be validated against the actual Asko model; the wrong codes will return null or incorrect values.
- **Rate limits** — ConnectLife does not publish rate limits. Excessive polling may result in temporary blocks.
- **Limited practical control value** — the washing machine must be physically loaded and set up before a remote start is useful. Monitoring (finished notification) is the primary value.
- **Appliance must be "connected"** — the appliance must be registered in the ConnectLife app and connected to Wi-Fi.

---

## 8. Recommended C-Bus Group Address Strategy

User Parameters — monitoring only to start with.

Suggested naming convention:

```
WashingMachine_Status     (String — "Off" / "Running" / "Paused" / "Finished")
WashingMachine_Program    (String — "Cotton 60°C")
WashingMachine_TimeLeft   (Number — minutes remaining)
WashingMachine_DoorLocked (Number — 0/1)
WashingMachine_Complete   (Number — 0/1, set to 1 when cycle ends, reset on next start)
WashingMachine_LastUpdated (String)
```

---

## 9. Dependencies on Gold-Standard Patterns

| Pattern | Source | Applicability |
|---|---|---|
| OAuth2 token refresh | Panasonic gold-standard | Adapt `P.RefreshAccessToken()` pattern |
| `ssl.https` + `ltn12` HTTPS | Panasonic gold-standard | Required |
| `safeSetUserParam` | All gold-standard | Required |
| `isDebuggingEnabled` cached per poll | All gold-standard | Required |
| State-aware polling interval | Derived value functions pattern | Module-level `_lastStatus` state |
| `user.secrets` isolation | All gold-standard | Required — password or tokens |

---

## Action Required

1. **Confirm Asko model number** — find the model number to look up the correct property codes in the ConnectLife HA integration YAML files.
2. **Register and test ConnectLife account** — ensure the appliance is visible in the ConnectLife app before attempting API integration.
3. **Identify property codes** — cross-reference the HA integration YAML dictionary for the specific Asko model.
4. **Write Python token helper** — implement initial login on a desktop to generate the first refresh token.
5. **Implement as read-only monitoring first** — status, time remaining, and cycle-complete notification are the highest-value use cases.
6. **Write integration script** in a future session — this research plus the HA integration source code is sufficient to proceed.

---

## Reference

- Home Assistant ConnectLife integration: https://github.com/oyvindwe/connectlife-ha
- ConnectLife API client (Python): https://github.com/oyvindwe/python-connectlife-api
