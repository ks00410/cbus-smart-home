# Integration Research: Gaggenau Oven and Cooktop (Home Connect)

**Integration #:** 8  
**Device / Service:** Gaggenau oven and cooktop via BSH Home Connect cloud platform  
**Last Researched:** 2025  

---

## 1. Integration Method

**Cloud API — BSH Home Connect REST API.**

Gaggenau is a premium brand within the BSH Home Appliances group (along with Bosch, Siemens, Neff, and others). All BSH connected appliances use the **Home Connect** platform.

BSH provides an **officially documented developer API** at `https://api.home-connect.com`. This is one of the most developer-friendly appliance APIs available, with full OAuth2 documentation, a developer sandbox, and a published API reference.

**Base URL:** `https://api.home-connect.com`  
**Key endpoints:**
- `GET /api/homeappliances` — list all registered appliances
- `GET /api/homeappliances/<haId>/status` — current appliance status
- `GET /api/homeappliances/<haId>/settings` — current settings
- `PUT /api/homeappliances/<haId>/settings/<settingKey>` — change a setting
- `GET /api/homeappliances/<haId>/programs/active` — currently running program
- `PUT /api/homeappliances/<haId>/programs/active` — start a program
- `DELETE /api/homeappliances/<haId>/programs/active` — stop current program
- `GET /api/homeappliances/<haId>/events` — **Server-Sent Events (SSE) stream** for real-time updates

The SSE event stream is the most powerful feature — the API server pushes state changes to the client in real time. However, SSE requires a persistent HTTP connection with chunked transfer encoding, which is difficult to implement in Lua on the 5500AC. **Polling is the recommended approach for this platform.**

---

## 2. Connectivity Requirement

☁️ **Internet connection required.**  
The Home Connect API is a cloud service. BSH has stated no intention to provide a local LAN API. An internet connection is required for all status polling and control.

---

## 3. Authentication Method

**OAuth2 — Authorization Code flow with PKCE.**

The Home Connect API uses standard OAuth2. Initial token generation requires a user to authenticate via a web browser (Authorization Code flow), making it unsuitable for fully automated headless setup on the 5500AC.

**Recommended approach:**
1. Register as a developer at `developer.home-connect.com` and create an application (Client ID + Client Secret).
2. Run a Python OAuth2 helper script on a desktop to complete the Authorization Code flow and obtain an initial `access_token` and `refresh_token`.
3. Store the refresh token in `user.secrets` on the 5500AC.
4. The Lua library handles token refresh using the refresh token (same pattern as Panasonic).

**Token endpoint:** `POST https://api.home-connect.com/security/oauth/token`

Token lifespan: Access tokens expire after approximately 24 hours; refresh tokens are long-lived.

Credentials in `user.secrets`:
```lua
secrets.homeconnect = {
  client_id     = "your-client-id",
  client_secret = "your-client-secret",
  access_token  = "...",
  refresh_token = "...",
  oven_ha_id    = "Gaggenau-Oven-XXXXXXXXXXXX",
  cooktop_ha_id = "Gaggenau-Cooktop-XXXXXXXXXXXX"
}
```

---

## 4. Polling vs. Event-Driven

**Polling** — 60-second interval recommended.

While the Home Connect API offers an SSE event stream for real-time updates, implementing SSE in Lua on the 5500AC is impractical (requires parsing chunked HTTP with partial reads). HTTP polling is simpler and sufficient for dashboard monitoring.

Recommended intervals:
- **When idle:** Every 5 minutes
- **When active (program running):** Every 30–60 seconds

State-aware polling (same technique as Asko) reduces unnecessary API calls. Access token refresh is handled automatically on 401 responses.

---

## 5. Available Data / Controllable Parameters

### Read (Status and Program State)

**Oven:**

| Metric | Key | Notes |
|---|---|---|
| Door state | `BSH.Common.Status.DoorState` | Closed / Open / Locked |
| Operation state | `BSH.Common.Status.OperationState` | Inactive / Ready / Run / Pause / ActionRequired / Finished / Error |
| Remote control active | `BSH.Common.Status.RemoteControlActive` | Boolean — must be true for remote commands |
| Remote start allowed | `BSH.Common.Status.RemoteControlStartAllowed` | Boolean |
| Active program | `BSH.Common.Root.ActiveProgram` | e.g. `Cooking.Oven.Program.HeatingMode.HotAir` |
| Heating mode | `Cooking.Oven.Option.SetpointTemperature` | °C |
| Set temperature | `Cooking.Oven.Status.CurrentCavityTemperature` | °C (current actual) |
| Duration / remaining time | `BSH.Common.Option.Duration`, `BSH.Common.Option.RemainingProgramTime` | Seconds |
| Preheat complete | `Cooking.Oven.Event.PreheatFinished` | Event |

**Cooktop:**

| Metric | Key | Notes |
|---|---|---|
| Operation state | `BSH.Common.Status.OperationState` | Inactive / Run / Error |
| Active zone power levels | Zone-specific status keys | 0=off, 1–9 = power level |
| Child lock | `BSH.Common.Setting.ChildLock` | Boolean |

### Write (Control)

Remote commands require `RemoteControlActive = true` (user must enable remote on the appliance) and `RemoteControlStartAllowed = true`.

| Action | Notes |
|---|---|
| Preheat oven to temperature | Set `Cooking.Oven.Program.HeatingMode.HotAir` with temp |
| Start timed cooking | Program + temperature + duration |
| Stop program | `DELETE /programs/active` |
| Change setting | `PUT /settings/<key>` (e.g. child lock, light) |

> **Practical note:** For safety, the oven's physical "Remote Start" button must be pressed by a user before remote commands will be accepted. This limits automation of oven start — monitoring is the more practical use case.

---

## 6. Estimated Implementation Difficulty

🟠 **Medium to Hard.**

The API is well-documented (unlike Asko/ConnectLife) which reduces integration risk significantly. The main challenges are:
- OAuth2 Authorization Code flow for initial token generation (requires desktop Python helper)
- Token refresh management (same complexity as Panasonic)
- Appliance HA ID discovery
- Mapping BSH key strings to C-Bus UserParam names

A read-only monitoring implementation is **Medium**. Adding remote control raises to **Hard** due to the remote-start-authorisation requirement and safety implications.

---

## 7. Known Limitations and Risks

- **Remote control safety gate** — the oven only accepts remote commands when "Remote Start" has been physically enabled on the appliance. This is a deliberate safety design — remote oven ignition without physical user confirmation is not possible.
- **Developer account required** — must register at `developer.home-connect.com`. Approval is typically automatic but requires acceptance of T&Cs.
- **Cloud dependency** — no local API fallback.
- **Rate limits** — Home Connect API enforces rate limits. As of 2024: 1 request per second, 1000 requests per day per client. At 60-second polling for 2 appliances, daily usage is ~2880 requests — likely to exceed the free tier limit. **Use state-aware polling (5-minute intervals when idle) to stay within limits.**
- **Access token and refresh token management** — same approach as Panasonic but must be implemented separately (Home Connect is not related to Comfort Cloud).
- **SSE not viable on 5500AC** — the real-time event stream cannot practically be consumed from Lua.

---

## 8. Recommended C-Bus Group Address Strategy

User Parameters per appliance.

Suggested naming convention:

```
Oven_OperationState   (String — "Inactive" / "Ready" / "Run" / "Finished")
Oven_DoorState        (String — "Closed" / "Open")
Oven_SetTemp          (Number, °C)
Oven_CurrentTemp      (Number, °C)
Oven_Program          (String — "Hot Air", "Grill", etc.)
Oven_TimeRemaining    (Number — seconds)
Oven_PreheatDone      (Number — 0/1)
Oven_RemoteAllowed    (Number — 0/1)
Oven_LastUpdated      (String)

Cooktop_OperationState (String)
Cooktop_LastUpdated    (String)
```

---

## 9. Dependencies on Gold-Standard Patterns

| Pattern | Source | Applicability |
|---|---|---|
| OAuth2 token refresh | Panasonic gold-standard | Adapt `P.RefreshAccessToken()` pattern |
| `ssl.https` + `ltn12` HTTPS | Panasonic gold-standard | Required |
| `safeSetUserParam` | All gold-standard | Required |
| `isDebuggingEnabled` cached per poll | All gold-standard | Required |
| State-aware polling | Module state pattern | `_ovenState` persisted between polls |
| `user.secrets` isolation | All gold-standard | Required |

---

## Action Required

1. **Register Home Connect developer account** at `developer.home-connect.com` and create an application.
2. **Discover HA IDs** — run the Python helper to authenticate and call `GET /api/homeappliances` to get the HA IDs for both the oven and cooktop.
3. **Confirm rate limits** — review current Home Connect API rate limit documentation and design polling strategy accordingly.
4. **Write Python OAuth2 helper** for desktop-based initial token generation.
5. **Implement read-only monitoring first** — operation state, temperature, time remaining.
6. **Write integration script** in a future session.

---

## Reference

- Home Connect Developer Portal: https://developer.home-connect.com
- Home Connect API Reference: https://apiclient.home-connect.com
- Home Assistant Home Connect integration: https://github.com/home-assistant/core/tree/dev/homeassistant/components/home_connect
