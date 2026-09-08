# Integration Research: Asko Washing Machine (ConnectLife)

**Integration #:** 7  
**Device / Service:** Asko Pro Washing Machine via ConnectLife cloud platform  
**Last Researched:** 2025-06  
**Research sources:** [`oyvindwe/connectlife-ha`](https://github.com/oyvindwe/connectlife-ha) (HA HACS, 292 stars, 64 contributors, v0.46.0); [`oyvindwe/connectlife`](https://github.com/oyvindwe/connectlife) (Python API library)

---

## 1. Integration Method

**Cloud API — ConnectLife / HijuConn gateway, OAuth2 + request signing.**

Asko is a brand owned by Gorenje/Haier Group. Asko appliances connect to the ConnectLife cloud platform. The `oyvindwe/connectlife-ha` integration has fully reverse-engineered the protocol — this doc is derived directly from that source.

### Protocol Summary

The auth flow is a **three-step chain**, then all device calls go through the HijuConn gateway with a signed payload:

1. **Gigya login** — POST email/password to `https://accounts.eu1.gigya.com/accounts.login` with `APIKey = 4_yhTWQmHFpZkQZDSV1uV-_A` → returns `UID` and `sessionInfo.cookieValue` (login token)
2. **Gigya JWT** — POST login token to `https://accounts.eu1.gigya.com/accounts.getJWT` → returns `id_token`
3. **OAuth2 authorise** — POST JWT + UID to `https://oauth.hijuconn.com/oauth/authorize` with `client_id = 5065059336212` → returns `code`
4. **Token exchange** — POST code to `https://oauth.hijuconn.com/oauth/token` with `client_secret = 07swfKgvJhC3ydOUS9YV_SwVz0i4LKqlOLGNUukYHVMsJRF1b-iWeUGcNlXyYCeK` → returns `access_token` + `refresh_token`

**Token refresh:** POST to `/oauth/token` with `grant_type=refresh_token`. Falls back to full re-login if refresh fails.

### HijuConn Gateway

All device requests go through `https://clife-eu-gateway.hijuconn.com`:

| Endpoint | Method | Purpose |
|---|---|---|
| `/clife-svc/pu/get_device_status_list` | GET | List all appliances + current status |
| `/device/pu/property/set` | POST | Update appliance property |
| `/clife-svc/pu/energyConsumptionCurve` | POST | Energy/water usage statistics |

### Request Signing

Every gateway request includes a **SHA-256 + RSA-PKCS1v15 signature**:
1. Sort all payload keys alphabetically (excluding `sign`), build `key=value&key=value` string
2. Append the constant suffix `D9519A4B756946F081B7BB5B5E8D1197`
3. SHA-256 hash the string
4. RSA-PKCS1v15 encrypt the hash with a hardcoded 2048-bit public key (in `api.py`)
5. Base64-encode the result → `sign` field

Each request also includes a per-request nonce `randStr` (32 random hex chars). The gateway rejects duplicate nonces.

**⚠️ The RSA signing step requires an RSA implementation.** The 5500AC has `crypto` (OpenSSL bindings) and `encdec` available — RSA PKCS1v15 encryption is technically possible but non-trivial. This is the primary implementation complexity.

### Device Identity

The **ASKO Pro Washing Machine** has:
- `deviceTypeCode = "003"`
- `deviceFeatureCode = "000"`

These are confirmed in [`DEVICES.md`](https://github.com/oyvindwe/connectlife-ha/blob/main/DEVICES.md). The device list response includes a `puid` (per-unit ID) used for all subsequent calls.

---

## 2. Connectivity Requirement

☁️ **Internet connection required** — ConnectLife is a fully cloud-based platform. There is no local LAN API.

---

## 3. Authentication Method

**Gigya SSO → HijuConn OAuth2 → gateway access token.**

Credentials in `user.secrets`:
```lua
secrets.connectlife = {
  email         = "your@email.com",
  password      = "your-password",
  -- populated at runtime, persisted across polls:
  access_token  = "",
  refresh_token = "",
  token_expiry  = 0,   -- Unix timestamp
  puid          = "",  -- discovered from device list on first run
}
```

The access token has an `expires_in` field (seconds). Renew 90 seconds before expiry (per HA integration logic). Persist tokens between polls using `safeSetUserParam` on the `user.secrets` library object — same pattern as Panasonic.

> **Initial token generation:** The three-step Gigya → OAuth2 chain is complex. A Python helper script (using the `connectlife` library) should be run once on a desktop to generate the initial `refresh_token`, which is then stored in `user.secrets`. The 5500AC only needs to perform the `refresh_token` grant going forward, falling back to full re-login if refresh fails.

---

## 4. Polling vs. Event-Driven

**Polling** — ConnectLife offers no push/webhook.

| Appliance state | Interval |
|---|---|
| Idle / Off | Every 5 minutes |
| Running (mid-cycle) | Every 60 seconds |
| Finished (until acknowledged) | Every 5 minutes |

Track `_lastStatus = DeviceStatus` in module state to implement state-aware interval switching. This mirrors the HA coordinator logic (30s active / 5min idle for Reclaim).

---

## 5. Available Data / Controllable Parameters

All property names below are taken directly from [`003.yaml`](https://github.com/oyvindwe/connectlife-ha/blob/main/custom_components/connectlife/data_dictionaries/003.yaml). The API returns these as a flat key-value map per device (`statusList`).

### Core Status (Read)

| Property | Description | Values |
|---|---|---|
| `DeviceStatus` | Machine state | 0=standby, 1=program_select, 2=running, 3=pause, 4=permanent_error, 5=temporary_error, 8=program_finished |
| `DoorStatus` | Door open/closed | 0=closed, 1=open |
| `CurrentProgramPhase` | Active cycle phase | 0=delay, 1=prewash, 2=wash, 3=rinsing, 4=spinning, 5=anti_crease, 6=drain_water, 7=stop_program, 8=cooling, 12=finished |
| `SelectedProgram` | Active programme name | String (programme name from device) |
| `ProgramRemainingTime` | Time to end | Minutes (read-only) |
| `CurrentWaterTemperature` | Current water temp | °C (read-only) |
| `SpinTime` | Spin duration | Minutes (read-only) |
| `AlarmWashFinished` | Cycle complete flag | 0/1 |
| `TotalProgramCycles` | Lifetime cycle count | Integer (total increasing) |

### Alerts / Diagnostics (Read)

| Property | Description |
|---|---|
| `AlarmCleanFilterWarning` | Filter cleaning required |
| `AlarmFillAdContainer1Warning` | Detergent container 1 empty |
| `AlarmFillAdContainer2Warning` | Detergent container 2 (fabric softener) empty |
| `AlarmFoamDetection` | Excess foam detected |
| `AlarmPowerFailAlert` | Power failure occurred |
| `Error0`…`Error47` | Specific fault codes (optional, model-dependent) |
| `FailureReadOut1`…`10` | Failure history with last-cycle and repetition count |

### Configurable / Writable

| Property | Description | Values |
|---|---|---|
| `AddClothes` | Allow adding clothes mid-cycle | switch (0/1) |
| `AllergyModeEnable` | Allergy rinse mode | switch |
| `ColdWash` | Force cold wash | switch |
| `ChildLockEnabled` | Child lock | switch |
| `ExtraRinse` | Extra rinse cycle | switch |
| `HeatingSteps` | Gradual heating enabled | switch |
| `Load` | Load size | 0=25%, 1=50%, 2=100% |
| `SetMaxMotorSpeed` | Max spin speed | 0=reserved, 1=no_drain, 2=no_spin, 3=100rpm … 16=1600rpm |
| `ProgramOptionTimeStartDelayHour` | Delay start hours | 0–24 h |
| `StartDelayFunction` | Enable delay start | switch |
| `Sound` / `Volume` | Audible alerts | switch / level 1–5 |
| `Brightness` | Display brightness | level 1–5 |

### Energy / Statistics (Read — via `energyConsumptionCurve` endpoint)

| Metric | Description |
|---|---|
| `electricUsage` | kWh for period |
| `waterUsage` | Litres for period |
| `runTimes` | Runtime hours |
| `cycles` | Cycle count for period |
| `electricCurve` | Per-day kWh breakdown |
| `waterCurve` | Per-day water breakdown |

---

## 6. Estimated Implementation Difficulty

🟠 **Hard** — RSA signing is confirmed feasible on LM via FFI, but requires new FFI code.

### RSA Signing via LuaJIT FFI (confirmed approach)

The `user.aes` library from Unisenza proves `ffi.load("crypto")` (OpenSSL `libcrypto`) works on LM. That library uses `EVP_EncryptInit_ex` / `EVP_EncryptUpdate` / `EVP_EncryptFinal_ex` for AES. The same FFI pattern can call OpenSSL's RSA API for PKCS1v15:

```lua
local ffi = require("ffi")
local crypto = ffi.load("crypto")
ffi.cdef[[
  typedef struct evp_pkey_st EVP_PKEY;
  typedef struct evp_pkey_ctx_st EVP_PKEY_CTX;
  typedef struct bio_st BIO;
  BIO *BIO_new_mem_buf(const void *buf, int len);
  EVP_PKEY *PEM_read_bio_PUBKEY(BIO *bp, EVP_PKEY **x, void *cb, void *u);
  EVP_PKEY_CTX *EVP_PKEY_CTX_new(EVP_PKEY *pkey, void *e);
  int EVP_PKEY_encrypt_init(EVP_PKEY_CTX *ctx);
  int EVP_PKEY_CTX_set_rsa_padding(EVP_PKEY_CTX *ctx, int pad);
  int EVP_PKEY_encrypt(EVP_PKEY_CTX *ctx, unsigned char *out, size_t *outlen,
                       const unsigned char *in, size_t inlen);
  void EVP_PKEY_CTX_free(EVP_PKEY_CTX *ctx);
  void EVP_PKEY_free(EVP_PKEY *key);
  void BIO_free(BIO *a);
]]
-- RSA_PKCS1_PADDING = 1
```

This is **new FFI code** — no existing LM library does RSA. It must be written and tested on the device. It is not a research unknown but an implementation task.

**Alternative — thin proxy:** A Python script on the home server handles auth + signing, exposing a simple HTTP endpoint. Simpler overall but adds infrastructure dependency.

### Once Signing is Resolved

After auth + signing, everything else is straightforward — JSON parsing, flat property map, simple POST for control.

---

## 7. Known Limitations and Risks

- **RSA FFI code required** — no existing LM library does RSA. The FFI binding must be written and tested. If it proves too difficult, fall back to the proxy approach.
- **Three-step auth chain** — Gigya SSO → OAuth2 → gateway is more complex than Panasonic's two-step. The initial token acquisition must be done via external Python helper.
- **Undocumented API** — private commercial platform; endpoints or signing may change. The HA integration has had breaking auth changes at least once in its history.
- **Cloud dependency** — no local fallback. All data unavailable if ConnectLife cloud is down.
- **Property codes are named (not short codes)** — unlike prior doc's `f47` etc., the actual API uses full PascalCase names (`DeviceStatus`, `DoorStatus`). The old property code format was incorrect — the data dictionary (`003.yaml`) has the authoritative names.
- **`puid` must be discovered** — the per-unit device ID is only available after calling the device list endpoint. Must be persisted to `user.secrets` after first successful poll.
- **Rate limits** — ConnectLife does not publish limits. Respect the 5-minute idle interval.

---

## 8. Recommended C-Bus UserParam Strategy

```
Asko_DeviceStatus      (String — "standby" / "running" / "pause" / "program_finished")
Asko_ProgramPhase      (String — "wash" / "rinsing" / "spinning" / "finished" etc.)
Asko_SelectedProgram   (String — programme name)
Asko_TimeRemaining     (Number — minutes)
Asko_WaterTemp         (Float, °C — e.g. 60.0)
Asko_DoorOpen          (Number — 0/1)
Asko_WashFinished      (Number — 0/1, flag cleared on next start)
Asko_FilterWarning     (Number — 0/1)
Asko_DetergentWarning  (Number — 0/1, either container)
Asko_EnergyKwh         (Number — kWh this week)
Asko_WaterLitres       (Number — litres this week)
Asko_LastUpdated       (String)
```

---

## 9. Dependencies on Gold-Standard Patterns

| Pattern | Source | Applicability |
|---|---|---|
| OAuth2 token refresh loop | Panasonic gold-standard | Adapt `P.RefreshAccessToken()` — similar structure |
| `ssl.https` + `ltn12` | Panasonic gold-standard | All HTTPS requests |
| `safeSetUserParam` / `safeGetUserParam` | All gold-standard | Required |
| `isDebuggingEnabled()` cached per poll | All gold-standard | Required |
| `user.secrets` | All gold-standard | Tokens + puid |
| Library + thin resident script | Panasonic / Unisenza | Required |
| RSA PKCS1v15 via `crypto`/`ffi` | TBD — new pattern | Required for signing, or use proxy |

---

## 10. Action Required Before Implementation

1. **Decide signing approach** — attempt RSA PKCS1v15 via `ffi.load("crypto")` on LM (FFI code template above), or implement a thin Python proxy. No further external research needed — both paths are fully understood.
2. **Confirm Asko model** — ensure the physical machine is ASKO Pro (device type `003`, feature `000`). Other Asko models may use different type codes.
3. **Generate initial tokens** — run `python -m connectlife` from `oyvindwe/connectlife` on a desktop, capture `access_token` + `refresh_token`, store in `user.secrets`.
4. **Discover `puid`** — call `get_device_status_list`, find the `003` device, extract and persist `puid`.
5. **Implement read-only monitoring first** — `DeviceStatus`, `CurrentProgramPhase`, `ProgramRemainingTime`, `AlarmWashFinished` are the highest-value properties.
6. **Energy stats** — implement `energyConsumptionCurve` polling separately (daily, not per-status-poll).

---

## Reference

- [`oyvindwe/connectlife-ha`](https://github.com/oyvindwe/connectlife-ha) — Home Assistant HACS integration (primary source, 292 stars)
- [`oyvindwe/connectlife`](https://github.com/oyvindwe/connectlife) — Python API library (auth + gateway logic)
- [`api.py`](https://github.com/oyvindwe/connectlife/blob/main/connectlife/api.py) — full auth chain, gateway signing, endpoints
- [`003.yaml`](https://github.com/oyvindwe/connectlife-ha/blob/main/custom_components/connectlife/data_dictionaries/003.yaml) — ASKO washing machine property dictionary
- [`003-000.yaml`](https://github.com/oyvindwe/connectlife-ha/blob/main/custom_components/connectlife/data_dictionaries/003-000.yaml) — ASKO Pro device entry (uses default mappings)
- [`DEVICES.md`](https://github.com/oyvindwe/connectlife-ha/blob/main/DEVICES.md) — device type/feature code registry
