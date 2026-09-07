# cbus-smart-home

C-Bus / LogicMachine 5500AC smart home integration project — Lua scripts, research, and dashboard design for a comprehensive home automation system.

---

## Overview

This repository houses all Lua integration scripts, research documentation, and dashboard design work for a Clipsal C-Bus 5500AC (LogicMachine OEM) smart home controller. The system integrates a broad range of local and cloud-connected devices and services into a unified smart home dashboard.

All Lua scripts target the **C-Bus 5500AC (SpaceLogic NAC)** platform running LogicMachine firmware. Scripts follow the conventions and quality standards established in the gold-standard integration repositories listed below.

---

## Gold-Standard References

The following repositories define the code quality, structure, and conventions for all integrations in this project. New scripts must conform to these patterns without exception.

| Repository | Description |
|---|---|
| [`cbus-panasonic-comfort-cloud`](https://github.com/ks00410/cbus-panasonic-comfort-cloud) | Cloud OAuth2 API, token management, bi-directional control, energy telemetry |
| [`Cbus-Inception`](https://github.com/ks00410/Cbus-Inception) | Local LAN REST API, long-poll event monitoring, entity discovery, backoff |
| [`cbus-unisenza`](https://github.com/ks00410/cbus-unisenza) | Local LAN AES-encrypted API, auto-discovery, resident poll + event scripts |
| [`Cbus-OpenSprinkler`](https://github.com/ks00410/Cbus-OpenSprinkler) | Local LAN REST API, resident poll, prototype-grade (reference only) |
| [`Cbus-iZone`](https://github.com/ks00410/Cbus-iZone) | Local LAN, HVAC zone control (prototype — reference only) |
| [`sigenergy-modbus-profile`](https://github.com/ks00410/sigenergy-modbus-profile) | Modbus TCP/RTU register mappings for Sigenergy ESS |

---

## Repository Structure

```
cbus-smart-home/
├── README.md                        # This file — master project overview
├── CHANGELOG.md                     # Version history
├── .gitignore                       # Excludes secrets, build artefacts, OS files
│
├── docs/                            # Per-integration research and planning documents
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
│   └── DASHBOARD_CAPABILITIES.md   # Master capabilities and dashboard data model
│
├── integrations/                    # Lua integration scripts (future — not yet written)
│   └── .gitkeep
│
└── dashboard/                       # Dashboard design work (future — not yet started)
    └── .gitkeep
```

---

## Integrations

| # | Integration | Method | Local/Cloud | Status |
|---|---|---|---|---|
| 1 | Panasonic Heating | Cloud API (Comfort Cloud) | Cloud | Research complete |
| 2 | Unisenza Radiators | Local LAN (AES HTTP) | Local | Research complete |
| 3 | Inception Alarm | Local LAN (REST + long-poll) | Local | Research complete |
| 4 | Ecowitt Weather Station | Local LAN (HTTP push/pull) | Local | Research complete |
| 5 | BOM Weather | Cloud API | Cloud | Research complete |
| 6 | Shelly Devices | Local LAN (REST API) | Local | Research complete |
| 7 | Asko Washing Machine | Cloud API (ConnectLife) | Cloud | Research complete |
| 8 | Gaggenau Oven & Cooktop | Cloud API (Home Connect) | Cloud | Research complete |
| 9 | Ubiquiti Dream Machine | Local LAN (UniFi API) | Local | Research complete |
| 10 | LG TV | Local LAN (LG ThinQ / WebOS) | Local | Research complete |
| 11 | Apple TV | Local LAN (pyatv protocol) | Local | Research complete |
| 12 | Sonos | Local LAN (Sonos REST API) | Local | Research complete |
| 13 | OpenSprinkler | Local LAN (REST API) | Local | Research complete |
| 14 | Reclaim Hot Water | Cloud API (Reclaim Energy) | Cloud | Research complete |
| 15 | Sigenergy | Modbus TCP | Local | Research complete |
| 16 | SolCast | Cloud API | Cloud | Research complete |

---

## Lua Scripting Conventions

All scripts in this repository follow the conventions documented in the gold-standard repositories. Key rules:

1. **Module structure** — sections ordered: require → configuration → ID maps → module state → logging helpers → C-Bus I/O helpers → utility functions → derived value functions → HTTP fetch → payload parser → resident poll
2. **C-Bus I/O** — `GetUserParam` and `SetUserParam` always wrapped in `pcall` via `safeGetUserParam` / `safeSetUserParam`
3. **Debug logging** — `isDebuggingEnabled()` called once per poll cycle; result cached in `dbg` and passed through to all helpers
4. **Missing params** — warned once per session via `_missingParamWarned` table; never floods the log
5. **Secrets** — all credentials stored in `user.secrets` library; never committed to version control
6. **HTTP** — `socket.http` for plain HTTP (local LAN); `ssl.https` + `ltn12` for HTTPS (cloud APIs)
7. **Nil safety** — `safeSetUserParam` accepts `nil` as a silent no-op; no nil guards needed at call sites
8. **Temperature encoding** — temperatures stored as integers ×10 (e.g. 21.5 °C → 215) due to C-Bus integer param constraint

---

## Secrets Management

Credentials are stored in a `user.secrets` Lua library loaded into the 5500AC. A `secrets.example.lua` template is provided for each integration. **Never commit a real `secrets.lua` to this repository.**

---

## Platform Notes

- **Controller:** Clipsal C-Bus 5500AC (LogicMachine OEM), any firmware
- **Lua:** 5.1 compatible
- **Available libraries:** `socket.http`, `ssl.https`, `ltn12`, `json`, `cjson`, `bit`, `crypto` / `sha2`
- **Scripting types:** Resident scripts (polling), Event scripts (triggered), User Libraries (shared modules)
- **User Parameters:** Integer, Boolean, or String — no float support; use ×10 encoding for temperatures

---

## Contributing

All code must pass a manual review against the gold-standard conventions before merge. No new patterns should be introduced without documented justification.
