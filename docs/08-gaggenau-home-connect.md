# Integration Research: Gaggenau Oven and Cooktop (Home Connect — Local WebSocket)

**Integration #:** 8  
**Device / Service:** Gaggenau oven and cooktop via BSH Home Connect — **local LAN WebSocket, direct from 5500AC**  
**Last Researched:** 2025  
**Updated:** WebSocket confirmed viable on LogicMachine/5500AC — no proxy required

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

🟠 **Medium.**

Components:

| Component | Difficulty | Notes |
|---|---|---|
| `user.websocket` library | ✅ Done | Use LogicMachine KB Casambi library verbatim or adapt |
| AES payload encryption | ✅ Done | Reuse `user.aes` from Unisenza gold-standard |
| Profile download | ✅ Easy | One-time, desktop tool |
| PSK/TLS mode | ⚠️ Uncertain | Test on device — may need to fall back to AES mode |
| Appliance protocol message format | 🟠 Medium | JSON message format needs mapping from `homeconnect-websocket` source |
| C-Bus resident script | 🟡 Easy | Same pattern as Unisenza |
| Event script for control | 🟡 Easy | Same pattern as Panasonic event script |

The main unknown is the **message format** — the specific JSON request/response schema for querying entity values and sending commands. This must be derived from the `homeconnect-websocket` Python library source code in a future implementation session.

---

## 7. Known Limitations and Risks

- **PSK TLS support uncertain** — if TLS/PSK ciphersuites are not available in the 5500AC's LuaSec build, TLS-mode appliances cannot be connected directly. Mitigation: check the `connectionType` in the downloaded profile — if it is `"AES"`, proceed confidently. If `"TLS"`, test PSK support on the device before committing to this approach.
- **Remote control safety gate** — the oven only accepts programme start commands when the user has physically pressed "Remote Start" on the appliance. Monitoring works without this.
- **Message format research needed** — the exact WebSocket JSON protocol (request/response message schema, entity query format, command format) must be mapped from the Python `homeconnect-websocket` source code in a dedicated implementation session.
- **Static IP required** — assign a DHCP reservation for each appliance to prevent IP changes breaking the integration.
- **Profile re-download on re-keying** — unlikely but if BSH rotates keys, profiles must be re-downloaded.
- **`DeviceDescription.xml` / `FeatureMapping.xml`** — these files are required by the library to know which entity keys the specific appliance supports. The relevant entity keys must be extracted from these files and configured in the Lua integration.

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

## Action Required

1. **Download appliance profiles** — install [Home Connect Profile Downloader](https://github.com/bruestel/homeconnect-profile-downloader), log in with Home Connect account, download ZIP for oven and cooktop. Note the `connectionType` field (`"TLS"` or `"AES"`).
2. **Test PSK TLS** — if `connectionType = "TLS"`, test on the live 5500AC whether `ssl.wrap()` supports PSK ciphersuites. If not, check whether the appliance supports AES fallback.
3. **Map WebSocket message format** — read `homeconnect-websocket` Python source to document the exact JSON request/response format for entity queries and control commands.
4. **Obtain `user.websocket` library** — copy the Casambi WebSocket user library from the [LogicMachine KB](https://kb.logicmachine.net/integration/casambi/) and load it on the 5500AC.
5. **Write integration script** in a future session — `user.gaggenau` library + thin resident + event script for oven control.

---

## Reference

- LogicMachine KB Casambi (official WebSocket example): https://kb.logicmachine.net/integration/casambi/
- lipp/lua-websockets (pure-Lua WebSocket): https://github.com/lipp/lua-websockets
- LogicMachine forum WebSocket thread: https://forum.logicmachine.net/showthread.php?tid=1294
- Home Connect Local HA integration: https://github.com/chris-mc1/homeconnect_local_hass
- homeconnect-websocket Python library: https://pypi.org/project/homeconnect-websocket/
- Home Connect Profile Downloader: https://github.com/bruestel/homeconnect-profile-downloader
