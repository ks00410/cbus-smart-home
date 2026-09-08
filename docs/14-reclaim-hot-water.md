# Integration Research: Reclaim Hot Water System

**Integration #:** 14  
**Device / Service:** Reclaim Energy CO₂ heat pump hot water system  
**Last Researched:** 2025-06  
**Research source:** [`david-collett/reclaimenergy`](https://github.com/david-collett/reclaimenergy) (Home Assistant HACS integration, Python); [LogicMachine KB — MQTT client](https://kb.logicmachine.net/integration/mqtt-client/)

---

## 1. Integration Method

**AWS IoT Core MQTT over mutual TLS.**

The Reclaim V2 controller (SRE/MMSP series) connects to Wi-Fi and communicates exclusively via **AWS IoT Core MQTT** in the `ap-southeast-2` region. There is no local LAN API. The `david-collett/reclaimenergy` HA integration (56 stars, actively maintained) fully reverse-engineers the protocol — the implementation below is derived directly from its source.

### Protocol Summary

1. **One-time setup:** Authenticate anonymously to an AWS Cognito identity pool to obtain temporary AWS credentials, then call the IoT API to issue a per-device X.509 certificate + private key pair. Attach the `pswpolicy` IAM policy. Store the cert and key permanently — they do not expire.
2. **Unit ID:** 17-digit numeric ID printed on the device label. A custom checksum algorithm (key = 0x2F, 8-round bit-shift XOR over hex representation) validates the ID.
3. **MQTT topics** (derived from `hexid = hex(unit_id)[:-2]`, 14 hex chars):
   - Subscribe: `dontek{hexid}/status/psw`
   - Publish (commands): `dontek{hexid}/cmd/psw`
4. **Transport:** TLS 1.2+ mutual authentication using the issued cert/key against Amazon Root CA 1.
5. **Data request:** Publish `{"messageId":"read","modbusReg":1,"modbusVal":[1]}` → device responds on the status topic with a flat Modbus register dump.
6. **Write (control):** Publish `{"messageId":"write","modbusReg":<reg>,"modbusVal":[<value>]}`.

### AWS Connection Constants

```
AWS_REGION:        ap-southeast-2
AWS_IDENTITY_POOL: ap-southeast-2:e04c5d62-0c40-4eac-a343-27d5f76c4920
AWS_HOSTNAME:      a254daig9zo2wn-ats.iot.ap-southeast-2.amazonaws.com
AWS_PORT:          8883
MQTT policy:       pswpolicy
```

---

## 2. Connectivity Requirement

☁️ **Internet connection required** — AWS IoT Core MQTT is a cloud broker. There is no known local LAN fallback.

Polling interval: 30 seconds when pump/compressor is active; 5 minutes at idle (per HA coordinator logic).

---

## 3. Authentication Method

**Mutual TLS with AWS IoT Core X.509 certificates.**

- Certificates are obtained once via AWS Cognito anonymous identity pool (no account needed).
- The `obtain_aws_keys()` function in `reclaimv2.py` shows the exact Cognito → IoT Core certificate issuance flow using `boto3`.
- Certificates stored as PEM files — no expiry.

For the 5500AC implementation, the one-time cert issuance must be performed externally (Python script using `boto3`), producing three files:
- `AmazonRootCA1.pem` (download from Amazon)
- `reclaim_cert.pem`
- `reclaim_key.pem`

These are stored on the 5500AC filesystem and referenced from `user.secrets`:

```lua
secrets.reclaim = {
  unit_id  = "12345678901234567",  -- 17-digit ID from device label
  cacert   = "/path/to/AmazonRootCA1.pem",
  cert     = "/path/to/reclaim_cert.pem",
  key      = "/path/to/reclaim_key.pem",
}
```

---

## 4. Polling vs. Event-Driven

**MQTT push (event-driven) with periodic poll requests.**

The device does not push unsolicited updates. The client must publish a read request; the device replies on the status topic. The HA integration:
- Sends a read request on connect, then every 30s when heating active, every 5 minutes at idle.
- Processes the reply as an event (MQTT message callback).

On the 5500AC, a **resident Lua script** using the built-in `mosquitto` Lua binding polls on a timer and processes replies via the `ON_MESSAGE` callback. The `socket.selectfds()` pattern (documented in the LM KB) makes the loop non-blocking and suitable for a 0-sleep resident.

---

## 5. Available Data / Controllable Parameters

Full register map from `ReclaimState.modbus_map` in `reclaimv2.py`:

### Read (Status)

| Field | Modbus Reg | Notes |
|---|---|---|
| `pump` | 200 | Compressor/pump running (bool) |
| `power` | 225 | Power consumption (W) |
| `current` | 226 | Current ÷ 1000 (A) |
| `water` | 79 | Tank water temperature ÷ 2 (°C) — signed short |
| `case` | 50 | Case temperature ÷ 2 (°C) — signed short |
| `outlet` | 213 | Outlet water temperature (°C) — signed short |
| `inlet` | 214 | Inlet water temperature (°C) — signed short |
| `discharge` | 215 | Compressor discharge temperature (°C) — signed short |
| `suction` | 216 | Suction temperature (°C) — signed short |
| `evaporator` | 217 | Evaporator temperature (°C) — signed short |
| `ambient` | 218 | Ambient air temperature (°C) — signed short |
| `compspeed` | 219 | Compressor speed (RPM) |
| `waterspeed` | 220 | Water pump speed |
| `fanspeed` | 221 | Fan speed |
| `hours` | 222 | Total compressor hours |
| `starts` | 223 | Total compressor starts |
| `mode` | 40964 | Operating mode (see modes list below) |

**Operating modes** (register 40964, values 2–9):
1. Mode 1: 24H
2. Mode 2: Off-Peak 1
3. Mode 3: Off-Peak 2
4. Mode 4: PV Connectivity ← smart solar divert
5. Mode 5: User Timers
6. Mode 6: User Timers & Temperature
7. Mode 7: PV Default Timer
8. Mode 8: Holiday Mode

### Read/Write (Control)

| Field | Modbus Reg | Notes |
|---|---|---|
| `boost` | 40990 | Boost mode active (bool → int) |
| `mode` | 40964 | Operating mode (string ↔ index+2) |
| `mode5_timer1_start` | 40971 | Timer 1 start hour (÷256 read, ×256 write) |
| `mode5_timer1_duration` | 40972 | Timer 1 duration |
| `mode5_timer2_start` | 40973 | Timer 2 start hour |
| `mode5_timer2_duration` | 40974 | Timer 2 duration |
| `mode5_timer2_on_temp` | 40975 | Timer 2 on-temperature (÷2 / ×2) |
| `mode6_timer1_start` | 40976 | Mode 6 timer 1 start |
| `mode6_timer1_duration` | 40977 | Mode 6 timer 1 duration |
| `mode6_timer2_start` | 40991 | Mode 6 timer 2 start |
| `mode6_timer2_duration` | 40992 | Mode 6 timer 2 duration |
| `mode6_timer2_on_temp` | 40978 | Mode 6 timer 2 on-temp (÷2 / ×2) |
| `mode6_timer2_off_temp` | 40979 | Mode 6 timer 2 off-temp (÷2 / ×2) |
| `mode7_start` | 40980 | Mode 7 PV default timer start |
| `mode7_duration` | 40981 | Mode 7 PV default timer duration |
| `mode8_day` | 41000 | Holiday mode day of week |
| `mode8_start` | 41001 | Holiday mode start |

---

## 6. Estimated Implementation Difficulty

🟡 **Medium** — protocol fully known, transport fully supported natively on 5500AC.

The LogicMachine KB confirms a built-in **`mosquitto`** Lua binding (`require('mosquitto')`) with native mutual TLS support:

```lua
client = require('mosquitto').new()
client:tls_set('/data/ftp/AmazonRootCA1.pem', nil, '/data/ftp/reclaim_cert.pem', '/data/ftp/reclaim_key.pem')
client.ON_CONNECT = function(status, ...) ... end
client.ON_MESSAGE = function(mid, topic, payload) ... end
client:connect(AWS_HOSTNAME, 8883)
-- resident loop using socket.selectfds()
```

No proxy, no external library, no infrastructure dependency. Everything runs on the 5500AC.

**Remaining complexity:**
- One-time cert issuance (Python + `boto3` on external machine) and upload to 5500AC via FTP
- Unit ID hex derivation and checksum validation in Lua
- Register decode: `ushort()` (signed 16-bit) + `/2` temperature scaling
- Adaptive polling interval (30s active / 5min idle) via `timerfd`

The data parsing is straightforward — JSON decode + flat register dictionary lookup.

---

## 7. Known Limitations and Risks

- **Cloud dependency** — entirely dependent on AWS IoT Core; no local LAN fallback.
- **AWS Cognito cert issuance** — one-time setup requires Python + `boto3` on a separate machine. Result (three PEM files) uploaded to 5500AC `/data/ftp/` via FTP.
- **Unit ID checksum** — the 17-digit ID has a CRC; must be validated before use (algorithm in `reclaimv2.py`).
- **PV Connectivity mode** — Mode 4 is the solar divert mode. Directly relevant for automation with Sigenergy solar production data.
- **No local fallback** — if AWS IoT Core is unreachable, no data is available.

---

## 8. Recommended C-Bus UserParam Strategy

```
ReclaimHW_TankTemp       (Number, ×10 °C — e.g. 215 = 21.5°C)
ReclaimHW_AmbientTemp    (Number, ×10 °C)
ReclaimHW_OutletTemp     (Number, ×10 °C)
ReclaimHW_Power          (Number, W)
ReclaimHW_PumpActive     (Number — 0/1)
ReclaimHW_BoostActive    (Number — 0/1)
ReclaimHW_Mode           (String — e.g. "Mode 4: PV Connectivity")
ReclaimHW_CompSpeed      (Number — RPM)
ReclaimHW_Hours          (Number — total compressor hours)
ReclaimHW_LastUpdated    (String)
```

---

## 9. Dependencies on Gold-Standard Patterns

| Pattern | Source | Applicability |
|---|---|---|
| `ssl.https` / TLS with cert + key | Panasonic gold-standard | Mutual TLS socket to AWS IoT |
| `safeSetUserParam` / `safeGetUserParam` | All gold-standard | Required |
| `user.secrets` for credentials + cert paths | All gold-standard | Required |
| `isDebuggingEnabled()` cached per poll | All gold-standard | Required |
| Library + resident script pattern | Panasonic / Unisenza | Required |
| JSON payload decode | All integrations | Standard `json.decode()` |

---

## 10. Action Required Before Implementation

1. **Run `obtain_aws_keys()`** — on a Python machine with `boto3` installed, run the cert issuance script once. Upload `AmazonRootCA1.pem`, `reclaim_cert.pem`, `reclaim_key.pem` to `/data/ftp/` on the 5500AC via FTP. *(No other external infrastructure needed.)*
2. **Note unit ID** — 17-digit numeric ID from the device label. Validate with the checksum algorithm from `reclaimv2.py`.
3. **Write integration script** — protocol, transport (`mosquitto` + `tls_set`), register map, and decode logic are all fully documented. Ready to implement.

---

## Reference

- [`david-collett/reclaimenergy`](https://github.com/david-collett/reclaimenergy) — Home Assistant HACS integration (primary source)
- [`reclaimv2.py`](https://github.com/david-collett/reclaimenergy/blob/main/custom_components/reclaimenergy/reclaimv2.py) — full protocol implementation
- [`coordinator.py`](https://github.com/david-collett/reclaimenergy/blob/main/custom_components/reclaimenergy/coordinator.py) — polling intervals and update logic
- Reclaim Energy product page: https://reclaimenergy.com.au
- AWS IoT Core MQTT documentation: https://docs.aws.amazon.com/iot/latest/developerguide/mqtt.html
