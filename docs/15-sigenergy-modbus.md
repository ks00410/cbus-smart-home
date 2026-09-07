# Integration Research: Sigenergy Solar / Battery System (Modbus)

**Integration #:** 15  
**Device / Service:** Sigenergy hybrid inverter and battery energy storage system  
**Last Researched:** 2025  

---

## 1. Integration Method

**Local LAN — Modbus TCP (not a polled HTTP API).**

Sigenergy hybrid inverters and battery storage systems (SigenStor, SigenHybrid, SigenPV series) expose a **Modbus TCP/RTU interface** as documented in the [Sigenergy Modbus Protocol V2.9](https://github.com/ks00410/sigenergy-modbus-profile). The gold-standard `sigenergy-modbus-profile` repository contains the full JSON register mapping for all registers.

**Protocol:** Modbus TCP (preferred for IP-connected installations)  
**Port:** 502 (standard Modbus/TCP)  
**Slave address:** `247` for plant-level data (all inverters), `1–246` per individual inverter  
**Minimum polling period:** 1000 ms (as specified in Sigenergy protocol)

### Modbus in Lua on the 5500AC

The 5500AC / LogicMachine platform does **not** include a built-in Lua Modbus library by default. Options:

### Option A: LogicMachine Modbus Module (Recommended)
LogicMachine 5 (which the 5500AC is based on) includes optional Modbus TCP support as a built-in protocol module. In the LogicMachine web interface:
- **Settings → Protocols → Modbus TCP Master** — add the Sigenergy inverter as a Modbus TCP slave device
- Configure polling intervals and register mappings directly in the LogicMachine UI
- Register values are automatically mapped to LogicMachine **data objects** (equivalent to C-Bus User Parameters)
- Values are accessible in Lua scripts via `grp.checkupdate()` or direct object access

This approach requires **no custom Modbus Lua library** — it uses the built-in LogicMachine Modbus driver. The register mappings from the `sigenergy-modbus-profile` JSON files are used to configure the Modbus object list.

### Option B: Pure-Lua Modbus TCP implementation
A Modbus TCP client can be implemented in Lua using `socket` library TCP sockets. The Modbus TCP frame is:
```
[Transaction ID: 2 bytes] [Protocol ID: 0x0000: 2 bytes] [Length: 2 bytes]
[Unit ID (slave addr): 1 byte] [Function code: 1 byte] [Data: N bytes]
```
- FC03 (Read Holding Registers) for writable registers
- FC04 (Read Input Registers) for read-only registers
- FC06 (Write Single Register) / FC16 (Write Multiple Registers) for control

This is implementable in Lua but adds significant complexity. The LogicMachine built-in Modbus module (Option A) is strongly preferred.

**Recommended approach:** **Option A — LogicMachine built-in Modbus TCP Master module** for register polling, with a Lua resident script to perform any derived value calculations and custom UserParam writes from the polled object values.

---

## 2. Connectivity Requirement

🏠 **Fully local — no internet connection required.**  
Modbus TCP communicates directly over the LAN to the Sigenergy inverter. No cloud account or internet access needed.

---

## 3. Authentication Method

**No authentication.** Modbus TCP has no built-in authentication mechanism. Access is controlled at the network level — the inverter communicates with any Modbus master that can reach port 502.

The inverter's Modbus TCP interface must be enabled in the **MySigen app** or inverter settings. Consult the Sigenergy commissioning documentation for the specific model.

---

## 4. Polling vs. Event-Driven

**Polling** — minimum 1-second interval (as per Sigenergy protocol spec).  
**Recommended:** 5-second interval for power flow data, 60-second for energy totals.

The LogicMachine Modbus module handles polling automatically at the configured interval. Lua scripts consume the polled values without needing to manage the Modbus timing themselves.

---

## 5. Available Data / Controllable Parameters

Based on the `sigenergy-modbus-profile` register mappings (V2.9). Using the **Lite profiles** as the recommended starting point.

### Plant Level (Slave Address 247)

**Read — `Sigenergy_Plant_Lite.json` (28 key registers):**

| Register Category | Key Metrics |
|---|---|
| ESS (Battery) | SOC (%), SOH (%), battery power (W), charge/discharge power, rated energy |
| PV Solar | PV power (W), daily generation (kWh), total generation (kWh) |
| Grid | Import/export power (W per phase), total import (kWh), total export (kWh) |
| Load | Total load power (W), daily consumption (kWh) |
| EMS | Work mode (Self-Consumption / Feed-in / Backup / Charge from Grid) |
| On/Off Grid | On-grid / off-grid status |
| System | System time, timezone |

**Write — Control Registers (holding registers via FC16):**

| Action | Notes |
|---|---|
| Set EMS work mode | Self-Consumption, Feed-in Max, Backup, Time-of-Use |
| Set battery min SOC (grid protection) | % |
| Set battery charge/discharge power limits | W |
| Enable/disable remote EMS control | |
| Set power dispatch values | W (for manual dispatch) |
| Clear alarms | |

### Inverter Level (Slave Address 1–246)

**Read — `Sigenergy_Inverter_Lite.json` (26 key registers):**

| Register Category | Key Metrics |
|---|---|
| Battery | SOC (%), SOH (%), power (W), avg cell temp (°C) |
| PV | PV power per MPPT string (W), daily PV generation (kWh) |
| AC Output | Phase voltages (V), phase currents (A), frequency (Hz) |
| Energy | Daily charge/discharge energy (kWh) |

---

## 6. Estimated Implementation Difficulty

**Using LogicMachine built-in Modbus module:** 🟡 **Medium**
- Register configuration in the LogicMachine UI is manual but straightforward
- 28 Lite plant registers + 26 Lite inverter registers = ~54 objects to configure
- Derived value calculations (self-consumption %, solar fraction, grid dependency) require a Lua resident script
- The `sigenergy-modbus-profile` JSON provides all register addresses, types, and scaling factors

**Pure Lua Modbus TCP implementation:** 🔴 **Very Hard** — not recommended.

---

## 7. Known Limitations and Risks

- **Modbus TCP must be enabled on the inverter** — check MySigen app or inverter settings. Default state may be disabled.
- **Slave address configuration** — plant address is always `247`; inverter addresses are configured via the MySigen app and must be confirmed.
- **Multi-inverter plants** — each inverter requires a separate Modbus connection (different slave address). The LogicMachine Modbus module can handle multiple slaves.
- **Register V2.9 compatibility** — the register map may differ for older firmware. Verify the inverter firmware version supports V2.9 registers, or use the applicable protocol version document.
- **Minimum 1s polling period** — do not poll faster than 1 second. The LogicMachine module enforces configurable intervals.
- **Writable register caution** — care must be taken with writable control registers. Incorrect values could affect inverter behaviour. Read-only monitoring first, control later after thorough testing.
- **EVAC (EV Charger)** — if a SigenEVAC is present, an additional slave address and separate register set (`Sigenergy_EVAC.json`) are required.

---

## 8. Recommended C-Bus Group Address Strategy

LogicMachine Modbus objects are mapped to data object addresses (equivalent to Group Addresses). Additionally, write key values to User Parameters for dashboard display.

Suggested User Parameter naming convention:

```
Solar_PV_Power_W          (Number — current PV generation watts)
Solar_PV_Daily_kWh        (Number — today's PV generation)
Solar_Battery_SOC         (Number — battery state of charge %)
Solar_Battery_SOH         (Number — battery health %)
Solar_Battery_Power_W     (Number — positive=charging, negative=discharging)
Solar_Grid_Power_W        (Number — positive=importing, negative=exporting)
Solar_Load_Power_W        (Number — total house consumption watts)
Solar_EMS_Mode            (String — "Self-Consumption" / "Backup" etc.)
Solar_OnGrid              (Number — 1=on-grid, 0=off-grid)
Solar_SelfConsumption_Pct (Number — derived: PV consumed locally / PV total)
Solar_SolarFraction_Pct   (Number — derived: solar energy / total load)
Solar_LastUpdated         (String)
```

---

## 9. Dependencies on Gold-Standard Patterns

| Pattern | Source | Applicability |
|---|---|---|
| LogicMachine Modbus TCP module | LogicMachine platform | Register polling handled by built-in module |
| Derived value functions section | Panasonic / Ecowitt gold-standard | Self-consumption %, solar fraction, etc. |
| `safeSetUserParam` | All gold-standard | For derived and formatted UserParam writes |
| `isDebuggingEnabled` cached per poll | All gold-standard | Resident Lua script for derived calcs |
| Sigenergy register profile JSON | `sigenergy-modbus-profile` repo | Full register map — plant and inverter lite |

---

## Action Required

1. **Enable Modbus TCP on the Sigenergy inverter** — via MySigen app under System Settings → Communication.
2. **Confirm inverter slave address** — check MySigen app for the configured slave address (default often 1 or auto-assigned).
3. **Configure LogicMachine Modbus TCP Master** — add the inverter as a Modbus slave in the LogicMachine Protocols UI, using the register addresses from `Sigenergy_Plant_Lite.json` and `Sigenergy_Inverter_Lite.json`.
4. **Write derived values Lua script** — resident script that reads polled Modbus object values and writes formatted UserParams (self-consumption %, solar fraction, formatted status strings).
5. **Test with read-only registers first** — validate polling before attempting any write operations.
6. **Consult register profile** — `sigenergy-modbus-profile/Sigenergy_Plant_Lite.json` and `Sigenergy_Inverter_Lite.json` for the complete register list with addresses, types, and scaling.

---

## Reference

- Sigenergy Modbus Profile repository: https://github.com/ks00410/sigenergy-modbus-profile
- Sigenergy Modbus Protocol V2.9 PDF (in repository references folder)
- LogicMachine Modbus documentation: https://openrb.com/modbus-tcp-master/
