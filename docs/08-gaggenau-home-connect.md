# Integration Research: Gaggenau Oven and Cooktop (Home Connect — Local WebSocket)

**Integration #:** 8  
**Device / Service:** Gaggenau oven and cooktop via BSH Home Connect — **local LAN WebSocket, direct from 5500AC**  
**Last Researched:** 2025-06
**Updated:** WebSocket confirmed on LM; complete message protocol mapped from [`chris-mc1/homeconnect_websocket`](https://github.com/chris-mc1/homeconnect_websocket) v1.5.4

---

## 1. Integration Method

**Local LAN — Home Connect WebSocket protocol (TLS/PSK or AES), implemented directly in Lua on the 5500AC.**

BSH appliances (Gaggenau, Bosch, Siemens, Neff) communicate over the local network using a **WebSocket-based protocol** with per-appliance encryption. This is confirmed by the open-source HA integration [`homeconnect_local_hass`](https://github.com/chris-mc1/homeconnect_local_hass) and the Python library [`homeconnect-websocket`](https://pypi.org/project/homeconnect-websocket/).

### WebSocket is natively achievable on the 5500AC

Earlier research incorrectly stated that WebSocket is not available in Lua on the 5500AC. This is wrong. Three confirmed references demonstrate WebSocket working directly on LogicMachine:

1. **[`lipp/lua-websockets`](https://github.com/lipp/lua-websockets)** — a pure-Lua WebSocket implementation using `socket.tcp()` from LuaSocket (`client_sync.lua`). All dependencies (`bit`, `socket`, `ssl`) are available on LogicMachine.
2. **[LogicMachine forum thread #1294](https://forum.logicmachine.net/showthread.php?tid=1294)** — community implementation and discussion of WebSocket on LogicMachine.
3. **[LogicMachine KB — Casambi integration](https://kb.logicmachine.net/integration/casambi/)** — the **official LogicMachine knowledge base** ships a complete `user.websocket` Lua library. It uses `bit`, `ssl`, `socket`, `encdec`, and `socket.url` — all standard on the 5500AC. This is a first-party reference.

The LogicMachine `user.websocket` library is a self-contained, production-quality WebSocket client implementation. It handles:
- HTTP upgrade handshake (`Upgrade: websocket`, `Sec-WebSocket-Key`, `Sec-WebSocket-Accept`)
- Frame encoding and decoding (masking, continuation frames, binary/text)
- WSS (`wss://`) via `ssl.wrap()` / `ssl.dohandshake()`
- `connect()`, `send()`, `receive()`, `close()`

### Protocol details

- **Transport:** WebSocket (`ws://`) — plain TCP with HTTP upgrade
- **Encryption:** Two modes depending on appliance generation:
  - **TLS/PSK mode** (newer appliances): TLS with a per-appliance PSK. This requires `ssl.wrap()` with the PSK parameter — needs verification that the 5500AC's LuaSec build supports PSK ciphersuites (not all do).
  - **AES mode** (older appliances): AES-CBC envelope encryption *over plain WebSocket*. The WebSocket frame payload is AES-encrypted; the transport itself is plain HTTP upgrade. The `user.aes` library from the Unisenza gold-standard integration handles this directly.
- **Encryption credentials:** Retrieved once from the Home Connect cloud via the [Home Connect Profile Downloader](https://github.com/bruestel/homeconnect-profile-downloader). The downloaded ZIP contains each appliance's `DeviceDescription.xml`, `FeatureMapping.xml`, encryption key, and IV/PSK.
- **Discovery:** Appliances advertise via mDNS/Zeroconf. For the 5500AC integration, use a static IP (DHCP reservation) and configure it directly.

### Integration architecture (no proxy needed)

```
5500AC (LogicMachine)
  └── gaggenau_poll.lua  (resident script, e.g. 30s)
        └── user.gaggenau → ws://<appliance-ip>/  (persistent or per-poll WebSocket)
              └── user.websocket  (LogicMachine KB Casambi WebSocket library)
                    └── socket.tcp() / ssl.wrap()  (LuaSocket / LuaSec)
```

The Unisenza gold-standard pattern (library + thin resident script) applies directly here.

### Complete WebSocket Message Protocol (from `homeconnect_websocket` source)

All messages are JSON with a fixed envelope:

```json
{
  "sID": <int>,      -- Session ID (from init message)
  "msgID": <int>,    -- Incrementing message counter
  "resource": "/ro/values",
  "version": <int>,  -- From service version negotiation
  "action": "GET",   -- GET | POST | RESPONSE | NOTIFY
  "data": [...]      -- Array of entity objects (optional)
}
```

#### Connection and Handshake Sequence

1. **Connect** — WebSocket to `ws://<host>:80/homeconnect` (AES) or `wss://<host>:443/homeconnect` (TLS/PSK)
2. **Init message received from appliance:**
   ```json
   {"sID":1,"msgID":1,"resource":"/ei/initialValues","version":2,"action":"NOTIFY",
    "data":[{"edMsgID":1}]}
   ```
3. **Respond with app identity:**
   ```json
   {"sID":1,"msgID":1,"resource":"/ei/initialValues","version":2,"action":"RESPONSE",
    "data":[{"deviceType":"Application","deviceName":"MyApp","deviceID":"<uuid>"}]}
   ```
4. **Request available services:**
   ```json
   {"sID":1,"msgID":2,"resource":"/ci/services","version":1,"action":"GET"}
   ```
   Response: `"data":[{"service":"ci","version":2},{"service":"ro","version":1},...]`
5. **Authentication** (if `ci` version < 3):
   ```json
   {"sID":1,"msgID":3,"resource":"/ci/authentication","version":1,"action":"GET",
    "data":[{"nonce":"<32-char-random-urlsafe-b64>"}]}
   ```
6. **Request entity descriptions + initial values:**
   ```json
   {"sID":1,"msgID":4,"resource":"/ro/allDescriptionChanges","version":1,"action":"GET"}
   {"sID":1,"msgID":5,"resource":"/ro/allMandatoryValues","version":1,"action":"GET"}
   ```
   Response data: array of entity objects: `[{"uid":1234,"value":"BSH.Common.EnumType.OperationState.Inactive","access":"read"}]`
7. **Device ready** (if `ei` version == 2):
   ```json
   {"sID":1,"msgID":6,"resource":"/ei/deviceReady","version":2,"action":"NOTIFY"}
   ```

#### Reading Entity State

After init, entity updates arrive as NOTIFY messages on `/ro/values` or `/ro/descriptionChange`. Each message's `data` is an array of `{"uid":<int>,"value":<any>}` objects. The `uid` maps to the entity's full key name (e.g. `BSH.Common.Status.OperationState`) via the profile/description data.

For a single entity GET:
```json
{"sID":1,"msgID":7,"resource":"/ro/values","version":1,"action":"GET",
 "data":[{"uid":1234}]}
```

#### Sending a Command (POST)

```json
{"sID":1,"msgID":8,"resource":"/ro/values","version":1,"action":"POST",
 "data":[{"uid":1234,"value":"BSH.Common.EnumType.PowerState.On"}]}
```

#### AES Encryption Detail (AES-mode appliances only)

AES socket operates over **plain `ws://` WebSocket** (not WSS). Each WebSocket frame carries a **binary payload** (not text JSON):

- **Key derivation:** `enckey = HMAC-SHA256(psk, b"ENC")`, `mackey = HMAC-SHA256(psk, b"MAC")`
- **Encryption:** AES-256-CBC with the IV from the profile
- **Padding:** Pad to 16-byte boundary: `msg + 0x00 + random(pad_len-2) + byte(pad_len)`
- **Send frame:** `AES_CBC_encrypt(padded_msg) + HMAC-SHA256(mackey, iv + 0x45 + last_tx_hmac + enc_msg)[0:16]`
- **Receive frame:** Last 16 bytes = HMAC tag; first n-16 bytes = ciphertext. Verify HMAC before decrypting.
- **State:** CBC IV is shared across the session (stateful — must process messages in order)

#### TLS/PSK Mode Detail

- **Transport:** WSS — `wss://<host>:443/homeconnect`
- **TLS:** TLS 1.2, PSK cipher suite (`TLS_PSK_WITH_AES_128_CBC_SHA` or similar), `verify = CERT_NONE`, no hostname check
- **PSK:** Decoded from the urlsafe-base64 `psk64` in the appliance profile

For LuaSec: `ssl.wrap(sock, {protocol="tlsv1_2", ciphers="PSK", verify="none", psk=psk_bytes})`

### PSK TLS caveat

The Home Connect TLS/PSK mode requires the TLS handshake to use PSK ciphersuites (e.g. `TLS_PSK_WITH_AES_128_CBC_SHA`). LuaSec on LogicMachine uses OpenSSL; whether PSK is supported depends on the OpenSSL build. **This must be tested on the actual device.**

- **If PSK works:** Connect with `ssl.wrap(sock, { protocol = "tlsv1_2", ciphers = "PSK", psk = ... })`
- **If PSK does not work:** The appliance may fall back to plain WebSocket with AES payload encryption (AES mode) — check the `connectionType` field in the downloaded appliance profile JSON.

For AES-mode appliances, this is straightforward: the `user.aes` library from the Unisenza integration handles the encryption, and the WebSocket layer is plain `ws://`. This is a simpler and more certain path.

---

## 2. Connectivity Requirement

🏠 **Fully local at runtime — no internet connection required.**

One-time setup that requires internet:
1. Create a Home Connect account and connect appliances via the Home Connect app (once only)
2. Run the [Home Connect Profile Downloader](https://github.com/bruestel/homeconnect-profile-downloader) to extract appliance profiles (once only)

After profile download, **no internet or cloud access is needed** for ongoing operation.

---

## 3. Authentication Method

**Per-appliance PSK or AES key** — static hardware credentials from the downloaded profile.

Credentials in `user.secrets`:
```lua
secrets.gaggenau = {
  oven_host     = "192.168.1.xx",
  oven_ha_id    = "Gaggenau-Oven-XXXXXXXXXXXX",
  oven_key      = "base64-or-hex-key",    -- from profile download
  oven_iv       = "base64-or-hex-iv",     -- AES mode only
  oven_mode     = "AES",                  -- "AES" or "TLS"

  cooktop_host  = "192.168.1.xy",
  cooktop_ha_id = "Gaggenau-Cooktop-XXXXXXXXXXXX",
  cooktop_key   = "...",
  cooktop_iv    = "...",
  cooktop_mode  = "AES",
}
```

No token refresh, no OAuth2, no expiry management.

---

## 4. Polling vs. Event-Driven

**Two viable approaches:**

### Option A: Per-poll WebSocket connect (simpler, recommended initially)
- Open a new WebSocket connection on each resident poll cycle
- Send a status query message, receive the response
- Close the connection
- Same pattern as Unisenza / OpenSprinkler — clean and simple
- Latency: response within one poll interval (e.g. 30 seconds)

### Option B: Persistent WebSocket connection (event-driven, advanced)
- Open WebSocket once on first poll, keep open in module state (`_ws_conn`)
- Appliance pushes state change events to the connection in real time
- Resident script wakes periodically to drain the receive buffer
- Lower latency; more complex reconnection handling
- Pattern similar to Inception long-poll

**Recommended:** Start with Option A (per-poll connect) — simpler, easier to debug, lower risk. Upgrade to Option B if real-time response is needed.

---

## 5. Available Data / Controllable Parameters

Based on entity descriptions in [`cooking.py`](https://github.com/chris-mc1/homeconnect_local_hass/blob/main/custom_components/homeconnect_ws/entity_descriptions/cooking.py) and the `homeconnect-websocket` Python library entity key list.

### Oven

**Read:**

| Entity Key | Notes |
|---|---|
| `BSH.Common.Status.OperationState` | Inactive / Ready / Run / Pause / ActionRequired / Finished / Error |
| `BSH.Common.Status.DoorState` | Closed / Open / Locked |
| `BSH.Common.Status.RemoteControlActive` | Boolean — must be true for remote commands |
| `BSH.Common.Status.RemoteControlStartAllowed` | Boolean |
| `Cooking.Oven.Status.Cavity.N.CurrentTemperature` | °C — current cavity temp (per cavity) |
| `Cooking.Oven.Status.Cavity.N.WaterTankEmpty` | Boolean |
| `Cooking.Oven.Event.Cavity.N.AlarmClockElapsed` | Boolean |
| `Cooking.Oven.Event.Cavity.N.PreheatFinished` | Boolean |
| `BSH.Common.Root.ActiveProgram` | Currently running programme key |
| `BSH.Common.Option.RemainingProgramTime` | Seconds remaining |
| `BSH.Common.Option.Duration` | Programme duration (seconds) |
| `BSH.Common.Option.StartInRelative` | Delayed start (seconds) |

**Write (requires `RemoteControlActive = true`):**

| Action | Entity Key |
|---|---|
| Start programme | `BSH.Common.Root.ActiveProgram` + options |
| Stop programme | Delete active programme |
| Set alarm clock | `Cooking.Oven.Setting.Cavity.N.AlarmClock` |
| Set child lock | `BSH.Common.Setting.ChildLock` |
| Set oven light | `Cooking.Oven.Setting.Cavity.N.Light` |

### Cooktop

**Read:**

| Entity Key | Notes |
|---|---|
| `BSH.Common.Status.OperationState` | Inactive / Run / Error |
| `BSH.Common.Status.LocalControlActive` | Boolean — user actively using cooktop |

**Write:**

| Action | Notes |
|---|---|
| Child lock | `BSH.Common.Setting.ChildLock` |

---

## 6. Estimated Implementation Difficulty

🟡 **Medium** — protocol fully known, one remaining transport gate.

Components:

| Component | Difficulty | Notes |
|---|---|---|
| `user.websocket` library | ✅ Done | Use LogicMachine KB Casambi library verbatim or adapt |
| AES payload encryption | ✅ Done | Reuse `user.aes` from Unisenza gold-standard |
| Profile download | ✅ Easy | One-time, desktop tool |
| **Message format / protocol** | ✅ **Fully known** | Mapped from `homeconnect_websocket` source — see Section 1 |
| PSK/TLS mode | ⚠️ Uncertain | LuaSec PSK cipher support must be tested on device |
| C-Bus resident script | 🟡 Easy | Same pattern as Unisenza |
| Event script for control | 🟡 Easy | Same pattern as Panasonic event script |

The only remaining uncertainty is whether LuaSec on the 5500AC supports PSK ciphersuites. For AES-mode appliances, there is no uncertainty at all — the full AES encryption algorithm, padding, HMAC verification, and message format are completely documented above.

---

## 7. Known Limitations and Risks

- **PSK TLS support uncertain** — if LuaSec on the 5500AC does not support PSK ciphersuites, TLS-mode appliances require an alternative (check `connectionType` in the downloaded profile — `"AES"` is the simpler path).
- **Remote control safety gate** — the oven only accepts programme start commands when the user has physically pressed "Remote Start" on the appliance. Monitoring works without this.
- **Stateful AES CBC** — the AES socket is stateful (IV and HMAC chain across the session). A persistent WebSocket connection is therefore preferable over reconnecting per-poll, as each reconnect resets the IV. The `user.aes` library from Unisenza will need adaptation to maintain IV state across messages.
- **`uid` mapping** — entity values arrive by numeric `uid`, not by the friendly key name. The `uid` → key-name mapping comes from `/ro/allDescriptionChanges` on connect. This mapping must be parsed and cached at connection time.
- **Static IP required** — assign a DHCP reservation for each appliance to prevent IP changes.
- **Profile re-download on re-keying** — unlikely but if BSH rotates keys, profiles must be re-downloaded.

---

## 8. Recommended C-Bus Group Address Strategy

User Parameters via direct `user.gaggenau` library calls from the resident script.

Suggested naming convention:

```
Oven_OperationState   (String — "Inactive" / "Ready" / "Run" / "Finished" / "Error")
Oven_DoorState        (String — "Closed" / "Open")
Oven_CurrentTemp      (Number, °C)
Oven_Program          (String — active programme name)
Oven_TimeRemaining    (Number — seconds)
Oven_PreheatDone      (Number — 0/1)
Oven_AlarmElapsed     (Number — 0/1)
Oven_RemoteAllowed    (Number — 0/1)
Oven_LastUpdated      (String)

Cooktop_OperationState (String — "Inactive" / "Run")
Cooktop_LastUpdated    (String)
```

---

## 9. Dependencies on Gold-Standard Patterns

| Pattern | Source | Applicability |
|---|---|---|
| `user.websocket` library | LogicMachine KB (Casambi) | Use/adapt this library directly — do not rewrite |
| `user.aes` AES-256-CBC | Unisenza gold-standard | AES payload encryption for AES-mode appliances |
| Library + thin resident script | Unisenza gold-standard | `user.gaggenau` + `script_resident_poll.lua` |
| `safeSetUserParam` / `safeGetUserParam` | All gold-standard | Required |
| `isDebuggingEnabled` cached per poll | All gold-standard | Required |
| `_missingParamWarned` | All gold-standard | Required |
| `user.secrets` isolation | All gold-standard | PSK/AES key storage |
| Event script for control | Panasonic gold-standard | Same pattern for oven command scripts |

---

## 10. Action Required Before Implementation

1. **Download appliance profiles** — run [Home Connect Profile Downloader](https://github.com/bruestel/homeconnect-profile-downloader) once with Home Connect account. Extract `psk64`, `iv64` (AES) or `psk64` only (TLS), and `connectionType` from each appliance's profile ZIP.
2. **Confirm connection type** — if `connectionType = "AES"`, proceed directly. If `"TLS"`, test PSK cipher support on the live 5500AC (`ssl.wrap` with `ciphers="PSK"`).
3. **Obtain `user.websocket` library** — copy from the [LogicMachine KB Casambi page](https://kb.logicmachine.net/integration/casambi/) and load on the 5500AC.
4. **Write integration script** — protocol, handshake, message format, AES encryption, and entity key names are all fully documented. Ready to implement once profile credentials are in hand.

---

## Reference

- LogicMachine KB Casambi (official WebSocket example): https://kb.logicmachine.net/integration/casambi/
- lipp/lua-websockets (pure-Lua WebSocket): https://github.com/lipp/lua-websockets
- LogicMachine forum WebSocket thread: https://forum.logicmachine.net/showthread.php?tid=1294
- Home Connect Local HA integration: https://github.com/chris-mc1/homeconnect_local_hass
- homeconnect-websocket Python library: https://pypi.org/project/homeconnect-websocket/
- Home Connect Profile Downloader: https://github.com/bruestel/homeconnect-profile-downloader
