# cbus-smart-home

C-Bus / LogicMachine 5500AC smart home integration project — Lua scripts, research, and dashboard design for a comprehensive home automation system.

---

## Overview

This repository is the central hub for all smart home automation work on a Clipsal C-Bus 5500AC (LogicMachine OEM) controller. It contains:

- **`docs/`** — per-integration research documents covering protocol, auth, data model, difficulty, and implementation notes for all 16 integrations
- **`integrations/`** — each integration as a git submodule, pointing to its own dedicated repository
- **`dashboard/`** — dashboard design work (future)

All Lua scripts target **C-Bus 5500AC (SpaceLogic NAC)** running LogicMachine firmware, follow shared conventions documented below, and are written in Lua 5.1.

---

## Repository Structure

```
cbus-smart-home/
├── README.md
├── CHANGELOG.md
├── .gitmodules                          # Submodule registry
│
├── docs/                                # Per-integration research documents
│   ├── 01-panasonic-heating.md
│   ├── 02-unisenza-radiators.md
│   ├── 03-inception-alarm.md
│   ├── 04-ecowitt-weather-station.md
│   ├── 05-bom-weather.md
│   ├── 06-shelly-devices.md
│   ├── 07-asko-washing-machine.md
│   ├── 08-gaggenau-home-connect.md
│   ├── 09-ubiquiti-dream-machine.md
│   ├── 10-lg-tv.md
│   ├── 11-apple-tv.md
│   ├── 12-sonos.md
│   ├── 13-opensprinkler.md
│   ├── 14-reclaim-hot-water.md
│   ├── 15-sigenergy-modbus.md
│   ├── 16-solcast.md
│   ├── DASHBOARD_CAPABILITIES.md       # Master data model for dashboard design
│   └── MEASUREMENT_APPLICATION.md      # C-Bus app 228 assessment — which integrations should use it
│
├── integrations/                        # One submodule per integration
│   ├── panasonic/        → ks00410/cbus-panasonic-comfort-cloud
│   ├── unisenza/         → ks00410/cbus-unisenza
│   ├── inception/        → ks00410/Cbus-Inception
│   ├── ecowitt/          → ks00410/cbus-ecowitt
│   ├── opensprinkler/    → ks00410/Cbus-OpenSprinkler
│   ├── sonos/            → ks00410/cbus-sonos
│   ├── bom/              → ks00410/cbus-bom
│   └── sigenergy-profile/→ ks00410/sigenergy-modbus-profile
│
└── dashboard/                           # Dashboard design (future)
```

---

## Cloning

Because this repository uses git submodules, always clone with `--recurse-submodules`:

```bash
git clone --recurse-submodules https://github.com/ks00410/cbus-smart-home.git
```

If you already cloned without it:

```bash
git submodule update --init --recursive
```

To pull the latest commit for all submodules:

```bash
git submodule update --remote --merge
```

---

## Integrations

| # | Integration | Submodule | Method | Local/Cloud | Status |
|---|---|---|---|---|---|
| 1 | Panasonic Heating | [`integrations/panasonic`](https://github.com/ks00410/cbus-panasonic-comfort-cloud) | Cloud OAuth2 | ☁️ | ✅ Production |
| 2 | Unisenza Radiators | [`integrations/unisenza`](https://github.com/ks00410/cbus-unisenza) | Local LAN AES | 🏠 | ✅ Production |
| 3 | Inception Alarm | [`integrations/inception`](https://github.com/ks00410/Cbus-Inception) | Local REST + long-poll | 🏠 | ✅ Production |
| 4 | Ecowitt Weather | [`integrations/ecowitt`](https://github.com/ks00410/cbus-ecowitt) | Local HTTP | 🏠 | ✅ Production |
| 5 | BOM Weather | [`integrations/bom`](https://github.com/ks00410/cbus-bom) | Cloud HTTPS | ☁️ | ✅ Production |
| 6 | Shelly Devices | — | Local REST | 🏠 | 🔲 Not yet written |
| 7 | Asko Washing Machine | — | Cloud OAuth2 | ☁️ | 🔲 Not yet written |
| 8 | Gaggenau Home Connect | — | Local WebSocket | 🏠 | 🔲 Not yet written |
| 9 | Ubiquiti Dream Machine | — | Local HTTPS | 🏠 | 🔲 Not yet written |
| 10 | LG TV | — | Local WebSocket | 🏠 | 🔲 Not yet written |
| 11 | Apple TV | — | Proxy (pyatv) | 🏠 | 🔲 Not yet written |
| 12 | Sonos | [`integrations/sonos`](https://github.com/ks00410/cbus-sonos) | Local HTTPS | 🏠 | ✅ Production |
| 13 | OpenSprinkler | [`integrations/opensprinkler`](https://github.com/ks00410/Cbus-OpenSprinkler) | Local HTTP | 🏠 | ✅ Production |
| 14 | Reclaim Hot Water | — | Cloud MQTT | ☁️ | 🔲 Not yet written |
| 15 | Sigenergy | [`integrations/sigenergy-profile`](https://github.com/ks00410/sigenergy-modbus-profile) (data) | Modbus TCP | 🏠 | 🔲 Not yet written |
| 16 | SolCast | — | Cloud HTTPS | ☁️ | 🔲 Not yet written |

---

## Lua Scripting Conventions

All scripts follow a shared 11-section structure and set of conventions:

1. **Module structure** — sections in order: `require` → configuration → ID maps → module state → logging helpers → C-Bus I/O helpers → utility functions → derived value functions → HTTP fetch → payload parser → resident poll
2. **C-Bus I/O** — `GetUserParam` and `SetUserParam` always wrapped in `pcall` via `safeGetUserParam` / `safeSetUserParam`
3. **Debug logging** — `isDebuggingEnabled()` called **once** per poll cycle; result cached in `dbg` and passed through to all helpers — never called inline inside helpers
4. **Missing params** — warned once per session via `_missingParamWarned` table
5. **Secrets** — all credentials in `user.secrets` library; never committed to version control
6. **HTTP** — `socket.http` for local LAN (plain HTTP); `ssl.https` + `ltn12` for HTTPS (cloud or self-signed LAN)
7. **Nil safety** — `safeSetUserParam` accepts `nil` as a silent no-op; no nil guards needed at call sites
8. **Type safety** — use Float params for numeric values with decimal precision (temperatures, pressures, power readings); use Integer for whole-number values; use String for text

---

## Platform Notes

- **Controller:** Clipsal C-Bus 5500AC (SpaceLogic NAC / LogicMachine OEM)
- **Lua:** 5.1, LuaJIT FFI available
- **Libraries:** `socket.http`, `ssl.https`, `ltn12`, `json`, `cjson`, `bit`, `crypto`/`sha2`, `encdec`, `mosquitto`, `user.websocket` (Casambi KB)
- **Script types:** Resident (polling), Event (triggered on C-Bus group write), User Library (shared module)
- **User Parameters:** Boolean, Integer (32-bit signed or unsigned), **Float (32-bit)**, String (255 bytes), and more — native float support means no ×10 integer encoding is required

---

## Secrets Management

Credentials are stored in a `user.secrets` Lua library on the 5500AC. Each integration's README documents the required `secrets.*` structure. **Never commit real credentials to any repository.**
