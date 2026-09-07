# Integration Research: Reclaim Hot Water System

**Integration #:** 14  
**Device / Service:** Reclaim Energy CO₂ heat pump hot water system  
**Last Researched:** 2025  

---

## 1. Integration Method

**Cloud API — Reclaim Energy cloud platform.**

Reclaim Energy produces CO₂ heat pump hot water systems popular in Australia for their high efficiency (COP 5+). Their connected controller (SRE series) connects to Wi-Fi and communicates with the Reclaim cloud platform, accessible via the Reclaim app.

### API Discovery Status

Reclaim Energy does not publish a developer API. Two approaches are possible:

### Option A: Reverse-Engineered App API
The Reclaim mobile app communicates with a cloud backend. Traffic analysis of the app reveals API endpoints. The Home Assistant community has investigated this; as of 2024–2025 there is limited open-source tooling for Reclaim specifically, though some community members have identified API endpoints.

Reported base URL (community-sourced, may change): `https://api.reclaimenergy.com.au` or similar.  
Authentication: email/password → JWT token.

**Status: Uncertain** — this API is not officially supported, may require traffic capture to document current endpoints, and may change without notice.

### Option B: Modbus (Hardware Option)
Some Reclaim controllers support Modbus RTU over RS485 directly on the controller PCB. If the controller has an exposed Modbus interface, it could be polled from the 5500AC via a USB-to-RS485 adapter or a Modbus TCP gateway on the LAN. This is the most reliable and local approach but requires physical wiring.

**Verify with Reclaim documentation** whether the specific model has Modbus support.

### Option C: Smart Meter / Clamp Sensor
If the Reclaim unit's power consumption can be measured via a Shelly EM or similar clamp sensor, power state (heating active / standby) can be inferred from current draw. This is indirect but robust and local.

**Recommended approach:** 
1. Investigate cloud API by capturing app traffic
2. If Modbus available — use Modbus TCP (same approach as Sigenergy) — preferred for reliability
3. If cloud API works — use same OAuth2 + HTTPS pattern as Panasonic/Asko
4. Shelly clamp as a fallback for power state monitoring

---

## 2. Connectivity Requirement

☁️ **Internet connection required** for cloud API approach.  
🏠 **Local only** if Modbus is available on the hardware.

---

## 3. Authentication Method

**Cloud API:** JWT token from email/password login.  
**Modbus:** No authentication — physical RS485/TCP connection.

Cloud credentials in `user.secrets`:
```lua
secrets.reclaim = {
  email    = "your@email.com",
  password = "your-password",
  -- device_id discovered from device list endpoint
}
```

---

## 4. Polling vs. Event-Driven

**Polling** — 5-minute interval appropriate for hot water monitoring.

Hot water system state changes slowly (heating cycles are 30–60+ minutes). A 5-minute polling interval provides adequate resolution for dashboard display of tank temperature and heating state.

---

## 5. Available Data / Controllable Parameters

### Expected Read Data (based on app features and community research)

| Metric | Notes |
|---|---|
| Tank water temperature | °C — current tank temp |
| Target temperature | °C — setpoint |
| Heating state | Heating / Standby / Boost |
| Operation mode | Heat Pump / Element / Off |
| Boost mode active | Boolean |
| Timer/schedule state | Next scheduled run |
| COP estimate | Energy performance (if available) |
| Error codes | Fault status |

### Expected Write (Control)

| Action | Notes |
|---|---|
| Enable boost mode | Force heat pump to run immediately |
| Set target temperature | °C |
| Change operation mode | Heat pump / Electric element |
| Enable/disable timer schedule | |

---

## 6. Estimated Implementation Difficulty

**If cloud API is accessible:** 🟠 **Hard**  
- API is reverse-engineered and undocumented
- Requires traffic capture to document current endpoints
- Risk of API changes breaking integration
- OAuth/JWT implementation needed

**If Modbus available:** 🟡 **Medium**  
- Follow the Sigenergy Modbus pattern
- Requires physical RS485/TCP wiring
- Register map must be sourced from Reclaim (may need to request from manufacturer)

**Power state via Shelly clamp:** ✅ **Easy** (but limited — no temperature data)

---

## 7. Known Limitations and Risks

- **Undocumented cloud API** — no official developer support; high risk of breakage.
- **Modbus register map** — not publicly available; would need to be requested from Reclaim or discovered via experimentation.
- **Hardware access** — Modbus requires physical access to the controller PCB.
- **Limited community tooling** — less open-source support than Panasonic, Sonos, etc. — more original research required.
- **Cloud dependency** — cloud API requires internet; Modbus requires physical wiring.

---

## 8. Recommended C-Bus Group Address Strategy

```
HotWater_TankTemp      (Number, ×10 °C)
HotWater_TargetTemp    (Number, ×10 °C)
HotWater_State         (String — "Heating" / "Standby" / "Boost")
HotWater_Mode          (String — "Heat Pump" / "Element")
HotWater_BoostActive   (Number — 0/1)
HotWater_LastUpdated   (String)
```

---

## 9. Dependencies on Gold-Standard Patterns

| Pattern | Source | Applicability |
|---|---|---|
| OAuth2 / JWT token refresh | Panasonic gold-standard | If cloud API |
| `ssl.https` + `ltn12` | Panasonic gold-standard | If cloud API |
| Modbus TCP framing | Sigenergy profile | If Modbus hardware available |
| `safeSetUserParam` | All gold-standard | Required |
| `user.secrets` | All gold-standard | Required |

---

## Action Required

1. **Identify Reclaim model** — confirm exact model/controller to check Modbus support in product documentation.
2. **Check for Modbus** — contact Reclaim Energy support to ask if the controller supports Modbus RTU/TCP and obtain the register map.
3. **If cloud API** — capture app traffic using Charles Proxy or mitmproxy to document current API endpoints, authentication, and response format.
4. **Consider Shelly EM clamp** as a quick-win interim for heating active/standby detection.
5. **Write integration script** in a future session once the API approach is confirmed.

---

## Reference

- Reclaim Energy product page: https://reclaimenergy.com.au
- Home Assistant community forum threads on Reclaim integration (search forums.home-assistant.io for "Reclaim Energy")
