# Integration Research: Panasonic Heating (Comfort Cloud)

**Integration #:** 1  
**Device / Service:** Panasonic Heating — ducted and split-system heat pumps  
**Last Researched:** 2025  

---

## 1. Integration Method

**Cloud API** — Panasonic Comfort Cloud REST API (`https://accsmart.panasonic.com`).

The gold-standard `cbus-panasonic-comfort-cloud` integration already covers this device fully. The Panasonic Comfort Cloud platform handles all Panasonic AC units including heating-mode heat pumps and ducted zoned systems — there is no separate heating API.

**Assessment:** The existing integration requires **no new integration work** for basic heating and cooling control. Review whether additional heat pump-specific parameters (e.g. A2W — air-to-water heat pump registers) are needed and whether any `a2w.control` scope endpoints provide additional data.

### A2W (Air-to-Water) Consideration

Panasonic Aquarea (A2W) heat pumps use a separate scope (`a2w.control`) and potentially different API endpoints. If the heating system is an Aquarea model, an extension to the existing library may be required. The existing token scope already includes `a2w.control`; dedicated endpoint research is needed in a future session if applicable.

---

## 2. Connectivity Requirement

☁️ **Internet connection required.**  
All communication goes through Panasonic's cloud servers. There is no known local LAN API for Comfort Cloud devices. If the internet is unavailable, no status polling or control is possible.

---

## 3. Authentication Method

**OAuth2 / Auth0** — Refresh token flow.

- Initial tokens are obtained via the `tools/generate_tokens.py` Python script included in the gold-standard repository (runs on a desktop, not on the 5500AC).
- The `refresh_token` and `access_token` are stored in `user.secrets` on the 5500AC.
- The Lua library (`user.panasonic`) handles automatic token refresh via `P.RefreshAccessToken()` and stores the current session in LogicMachine persistent `storage`.
- The Comfort Cloud `client_id` is obtained via `/auth/v2/login` after each token refresh.
- A dynamic HMAC-SHA256 API key (`x-cfc-api-key`) is signed per-request using the access token and a timestamp.
- App version must match the current live Comfort Cloud app version; the library auto-detects the latest version via Apple App Store / Google Play Store lookup, with fallback version bumping.
- HTTP 4106 = app version rejected → auto-discovers latest version.
- HTTP 412 = terms not accepted → auto-accepts agreements.

---

## 4. Polling vs. Event-Driven

**Polling** — 60-second resident script interval (configurable).

The Comfort Cloud API is request/response only — there is no push or webhook mechanism available. A 60-second interval is appropriate for HVAC state; shorter intervals risk rate limiting.

---

## 5. Available Data / Controllable Parameters

### Read (Status)

| Parameter | C-Bus UserParam (default prefix `AC_`) | Notes |
|---|---|---|
| Power on/off | `AC_Power` | Boolean (0/1) |
| Target temperature | `AC_TargetTemp` | °C |
| Inside temperature | `AC_InsideTemp` | °C — sensor in indoor unit |
| Outside temperature | `AC_OutsideTemp` | °C — sensor in outdoor unit |
| Operation mode | `AC_Mode` / `AC_Mode_Text` | 0=Auto, 1=Dry, 2=Cool, 3=Heat, 4=Fan |
| Fan speed | `AC_FanSpeed` / `AC_FanSpeed_Text` | 0=Auto…5=High |
| Eco mode | `AC_EcoMode` / `AC_EcoMode_Text` | 0=Auto, 1=Powerful, 2=Quiet |
| Vertical swing | `AC_SwingUD` / `AC_SwingUD_Text` | |
| Horizontal swing | `AC_SwingLR` / `AC_SwingLR_Text` | |
| Nanoe air purification | `AC_Nanoe` | 0–4 |
| EcoNavi | `AC_EcoNavi` | |
| iAuto-X / AI ECO | `AC_IAutoX` | |
| Inside cleaning | `AC_InsideCleaning` | |
| HVAC action (derived) | `AC_HVACAction` / `AC_HVACAction_Text` | Off/Idle/Heating/Cooling/Drying/Fan |
| Active zone count | `AC_ActiveZones` | Ducted systems only |
| Per-zone on/off | `AC_Zone1_Power` … | Ducted zoned systems |
| Per-zone damper % | `AC_Zone1_Damper` … | 0–100% |
| Per-zone temperature | `AC_Zone1_Temp` … | Where sensor fitted |
| Daily energy (kWh) | `AC_Daily_kWh` | Resets at midnight |
| Heating energy (kWh) | `AC_Heating_kWh` | |
| Cooling energy (kWh) | `AC_Cooling_kWh` | |
| Extrapolated power (W) | `AC_CurrentPower_W` | Derived from energy delta |
| Last updated | `AC_LastUpdated` | Timestamp string |

### Write (Control)

All parameters above with settable counterparts can be written from event scripts using `panasonic.Event_Control()` or `panasonic.ControlDevice()`:

- Power on/off
- Target temperature (clamped 16–30 °C)
- Operation mode
- Fan speed
- Eco mode
- Vertical / horizontal swing
- Nanoe, EcoNavi, iAuto-X
- Zone on/off and damper %

---

## 6. Estimated Implementation Difficulty

✅ **Already implemented** — gold-standard library (`user.panasonic`) is complete and production-quality.

For heating control specifically: **No additional work required** — the existing integration covers all modes including Heat. If the heating system is an Aquarea A2W model with dedicated endpoints, complexity would be **Medium**.

---

## 7. Known Limitations and Risks

- **Cloud dependency** — no local fallback. An outage of Panasonic's servers or the internet connection renders the integration non-functional.
- **Token expiry** — refresh tokens are long-lived but can be revoked by Panasonic (e.g. password change, account security action). Requires re-running the token generation tool.
- **App version sensitivity** — Panasonic's API rejects requests with an outdated `x-app-version` header. The auto-detection mechanism mitigates this but adds an additional HTTPS call to the App Store on version rejection.
- **Rate limits** — Panasonic does not publish rate limits. Polling more frequently than every 30 seconds is not recommended.
- **Terms & Agreements** — Panasonic periodically updates their T&Cs; the library auto-accepts these but a manual review would be preferable in a production deployment.
- **No local API** — entirely cloud-dependent; there is no known reverse-engineered local protocol for Comfort Cloud.

---

## 8. Recommended C-Bus Group Address Strategy

The existing implementation writes primarily to **User Parameters** (preferred for dashboard display and Lua-to-Lua access). Optional Group Address mappings are supported for integration with physical wall panels or C-Bus lighting scenes.

Suggested User Parameter naming convention (already in use):

```
AC_Power              (Number, 0/1)
AC_TargetTemp         (Float, °C)
AC_InsideTemp         (Number)
AC_OutsideTemp        (Number)
AC_Mode               (Number)
AC_Mode_Text          (String)
AC_HVACAction         (Number, 0–5)
AC_HVACAction_Text    (String)
AC_Daily_kWh          (Number)
AC_CurrentPower_W     (Number)
AC_LastUpdated        (String)
```

For multi-unit households, prefix per unit: `Lounge_AC_Power`, `Bedroom_AC_Power`, etc.

---

## 9. Dependencies on Gold-Standard Patterns

| Pattern | Source | Applicability |
|---|---|---|
| Auth0 OAuth2 token refresh | Panasonic gold-standard | Direct — already implemented |
| `safeSetUserParam` / `safeGetUserParam` | All gold-standard | Already in use |
| `isDebuggingEnabled` cached per poll | All gold-standard | Already in use |
| `_missingParamWarned` flood suppression | All gold-standard | Already in use |
| `ssl.https` + `ltn12` for HTTPS | Panasonic gold-standard | Already in use |
| Derived value functions (`calculateHVACAction`, `calculateExtrapolatedPower`) | Panasonic gold-standard | Already in use |
| `user.secrets` isolation | All gold-standard | Already in use |

---

## Action Required

1. **Confirm** whether the Panasonic heating system is a Comfort Cloud-compatible split/ducted unit (covered) or an Aquarea A2W unit (requires extension).
2. **If Aquarea:** Research `/a2w/` API endpoints in a future session; the existing token scope already includes `a2w.control`.
3. **No script work required** for standard Comfort Cloud heating units — integration is production-ready.
