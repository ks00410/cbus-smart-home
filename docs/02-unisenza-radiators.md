# Integration Research: Unisenza Plus Radiators

**Integration #:** 2  
**Device / Service:** Unisenza Plus smart panel radiators (per-room control)  
**Last Researched:** 2025  

---

## 1. Integration Method

**Local LAN — AES-256-CBC encrypted HTTP API** on the Unisenza Plus gateway (model PUMG021GW).

The gold-standard `cbus-unisenza` integration implements this fully. The gateway exposes a plain HTTP API on port 80. All request and response bodies are **AES-256-CBC encrypted JSON**, with the AES key derived from the gateway's EUID via MD5("Salus-" + euid_lower). The IV is fixed (`88a6b0795d85dbfce6e0b3e9a629654b`).

The Unisenza Plus system is an OEM of the **Salus iT600** platform. The protocol is identical across both brands and is confirmed by the open-source [pyit600](https://github.com/jnimmo/pyit600) Home Assistant integration.

Two endpoints are used:
- `POST /deviceid/read` with `{ requestAttr: "readall" }` — returns all device data
- `POST /deviceid/write` with device-specific payload — sets temperature or hold type

**Assessment:** The existing integration is complete and production-quality. No new integration work is required unless functionality needs to be extended (e.g. reading room temperature sensors, scheduling, or adding devices).

---

## 2. Connectivity Requirement

🏠 **Fully local — no internet connection required.**  
All communication is directly to the Unisenza Plus gateway on the LAN. The gateway communicates with the radiators over a Zigbee mesh — no cloud dependency for local control.

---

## 3. Authentication Method

**No explicit login/session required.** Authentication is implicit via the AES key, which is derived from the gateway's hardware EUID (printed on the sticker). Possession of the EUID grants full access to the gateway API.

Credentials required in `user.secrets` (or config table):
- `gateway_ip` — LAN IP address of the gateway
- `gateway_euid` — EUID from the hardware sticker (e.g. `001E5E090292DD94`)

---

## 4. Polling vs. Event-Driven

**Polling** — 30-second resident script interval.

The gateway API is pure request/response with no push capability. A 30-second interval provides responsive temperature feedback without excessive network load. The gateway communicates with radiators over Zigbee and updates its state continuously; values read on each poll reflect the current state.

---

## 5. Available Data / Controllable Parameters

### Read (per radiator, dynamically discovered by name)

| Parameter | C-Bus UserParam | Notes |
|---|---|---|
| Room temperature | `NAME_CurrentTemp` | Float °C (e.g. 14.2) |
| Heating setpoint | `NAME_Setpoint` | Float °C — writable |
| Hold type | `NAME_HoldType` | 0=Schedule, 1=Temp, 2=Hold, 7=Off, 10=Eco |
| Heating demand | `NAME_Demand` | 0–100 % |
| Online status | `NAME_Online` | 1=online, 0=offline |

### Global Parameters

| Parameter | C-Bus UserParam | Notes |
|---|---|---|
| Poll status | `Unisenza_Status` | "OK" or error string |
| Last updated | `Unisenza_LastUpdated` | Timestamp string |
| Device count | `Unisenza_DeviceCount` | Number of discovered radiators |

### Write (Control)

| Action | Method |
|---|---|
| Set room temperature | Write `NAME_Setpoint` (Float °C) — event script calls `unisenza.set_temperature()` |
| Change mode (schedule / eco / off) | Write `NAME_HoldType` — event script calls `unisenza.set_hold()` |

**Device auto-discovery** — no static device list needed. All radiators discovered on each first poll and logged with name, UID, and model.

---

## 6. Estimated Implementation Difficulty

✅ **Already implemented** — gold-standard library (`user.unisenza`) and event script (`unisenza_set.lua`) are complete and production-quality.

For any extension (e.g. schedule read/write, additional sensor types): **Medium** — requires further protocol reverse engineering.

---

## 7. Known Limitations and Risks

- **EUID required** — the gateway EUID must be read from the hardware sticker. There is no online lookup or recovery mechanism if the sticker is damaged.
- **Fixed IV** — the protocol uses a hardcoded IV, which is a known weakness of this manufacturer's implementation. This is not a risk in a trusted LAN environment.
- **Zigbee mesh stability** — radiators marked `Online=0` have lost their Zigbee connection to the gateway. May require repositioning of gateway or radiator.
- **Temperature resolution** — setpoints are rounded to the nearest 0.5 °C.
- **No scheduling API** — the Lua API supports Hold modes only; schedule read/write is not reverse-engineered.
- **Min/max setpoint enforcement** — the library clamps setpoints to `device.min_sp` / `device.max_sp` as reported by the gateway (typically 5–30 °C).

---

## 8. Recommended C-Bus Group Address Strategy

Primary storage is via User Parameters (Float type for temperatures). Native float support on the 5500AC means temperatures are stored as raw °C values.

Naming convention (already in use):

```
Romy_CurrentTemp      (Float, °C)
Romy_Setpoint         (Float, °C — write to control)
Romy_HoldType         (Number)
Romy_Demand           (Number, 0–100)
Romy_Online           (Number, 0/1)

Finn_CurrentTemp
... (one set per radiator, named from gateway discovery)

Unisenza_Status       (String)
Unisenza_LastUpdated  (String)
Unisenza_DeviceCount  (Number)
```

Dashboard display rule: divide `NAME_CurrentTemp` by 10 to display in °C.

---

## 9. Dependencies on Gold-Standard Patterns

| Pattern | Source | Applicability |
|---|---|---|
| Local LAN HTTP with `socket.http` | Inception, Unisenza | Direct — already in use |
| `safeSetUserParam` closure pattern | All gold-standard | Slightly simplified version in unisenza.lua (local closure) |
| `isDebuggingEnabled` cached per poll | All gold-standard | Implemented inline in `Resident_Poll` |
| `_missingParamWarned` flood suppression | All gold-standard | `_missing_warned` table in use |
| Module state (`_known_devices`, `_ctx`) | Unisenza gold-standard | AES context cached once per controller restart |
| Pure-Lua AES-256-CBC library | Unisenza gold-standard | `user.aes` — uploaded separately to 5500AC |
| Auto-discovery log pattern | Inception gold-standard | First-poll discovery log with device list |

---

## Action Required

No action required. Integration is production-ready for:
- Per-room temperature reading
- Setpoint control
- Hold mode switching (Schedule / Eco / Off / Permanent)

Future enhancements to consider:
- Group setpoint control (set all radiators in a zone simultaneously)
- Frost protection mode automation (triggered by occupancy or time schedule)
