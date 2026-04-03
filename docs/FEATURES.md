# LittleBrother Feature Expansion Roadmap
## CounterSurveillance / SIGINT Suite

Version: 0.8.0 (Planning)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    LittleBrother Network                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐        ┌──────────────┐        ┌──────────┐ │
│  │ Mobile Phone │◄──────►│  Desktop PC   │◄──────►│ Crowdsrc │ │
│  │  (Scanner)   │  WiFi  │  (Homebase)   │   TLS   │ Server   │ │
│  │              │  REST  │              │         │          │ │
│  │ • WiFi/BLE   │        │ • Full scan  │         │ • Aggre- │ │
│  │ • Cell       │        │ • SDR opts   │         │   gation │ │
│  │ • GPS        │        │ • 24/7 ops   │         │ • Intel  │ │
│  │ • (SDR opt)  │        │ • Alerts     │         │   share  │ │
│  └──────┬───────┘        └──────┬───────┘         │ • Map    │ │
│         │                       │                  │   tiles  │ │
│         │ Local SQLite         │ Local SQLite    └──────────┘ │
│         │ (phone.db)           │ (desktop.db)                │
│         │                       │                             │
│         │              ┌──────┴──────┐                       │
│         │              │ Sync Merge  │                       │
│         └─────────────►│   Layer     │◄──────────────────────┘
│                        └─────────────┘
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Enhanced CounterSurveillance Detection

### 1.1 Spyware Detection (Priority: HIGH) — IMPLEMENTED v0.8.0

| Feature | Status | Description |
|---------|--------|-------------|
| **Silent SMS Detector** | DONE | Detect class 0 (hidden) SMS messages |
| **SMS Exfiltration Detector** | DONE | Detect unusual SMS patterns to unknown recipients |
| **Passive Monitoring** | DONE | Background checks every 15 minutes during scan |
| **Forensic Scan** | DONE | On-demand full spyware scan |
| **Alert Integration** | DONE | Routes findings to alert engine + push notifications |

### 1.2 WiFi Countermeasures (Priority: HIGH) — IMPLEMENTED v0.8.0

| Feature | Status | Description |
|---------|--------|-------------|
| **Deauth Storm Detector** | DONE | Monitor for deauth/disassociation flood attacks via AP disappearance |
| **Enhanced Rogue AP** | DONE | Evil twin detection, captive portal identification, spoofed home networks |
| **Privacy-Breaking AP Database** | DONE | Detects xfinitywifi, captive portals, honeypots |
| **EAPOL Handshake Monitor** | PLANNED | Detect 4-way handshake capture attempts |
| **PMKID Harvesting Detection** | PLANNED | Alert on RSN PMKID IE in auth frames |
| **Evil Twin Alert** | DONE | Flag cloned SSIDs on same channel from multiple BSSIDs |

### 1.2 BLE Countermeasures (Priority: HIGH) — IMPLEMENTED v0.8.0

| Feature | Status | Description |
|---------|--------|-------------|
| **AirTag/SmartTag Detector** | DONE | Detect Apple AirTags, Tile, Galaxy SmartTag, Chipolo by signature |
| **Enhanced BLE Tracking** | DONE | Cross-session persistence detection via geohash analysis |
| **Proximity Alerts** | DONE | Alert when device within 2m for sustained period |
| **Randomized MAC Detection** | DONE | Flag randomized MACs with no vendor info (AirTag-like) |

### 1.3 Cellular Countermeasures (Priority: HIGH)

| Feature | Status | Description |
|---------|--------|-------------|
| **Enhanced Stingray Heuristics** | PLANNED | LAC/CID jitter, TA inconsistency, downgrade |
| **Silent SMS Detection** | PLANNED | Monitor for class 0 SMS |

---

## Phase 2: Desktop Sync (REST API)

### 2.1 Communication Protocol

| Component | Implementation |
|-----------|----------------|
| **Discovery** | mDNS/Bonjour for local desktop discovery |
| **Transport** | HTTPS REST API with JWT auth |
| **Protocol** | JSON signal streaming, batched every 5s |
| **Sync Strategy** | Merge on desktop - phone keeps local copy |

### 2.2 Desktop Database Schema

Same as mobile with additions:
- `source_device` field (phone_id, desktop_id)
- `merged_at` timestamp for sync deduplication

---

## Phase 3: SDR Integration

### 3.1 Subprocess Adapter Pattern

```
┌─────────────────────────────────────────────┐
│           SDR Subprocess Adapter            │
├─────────────────────────────────────────────┤
│                                              │
│  ┌────────────────────────────────────────┐ │
│  │         ScanCoordinator                │ │
│  └──────────────────┬─────────────────────┘ │
│                     │                        │
│                     ▼                        │
│  ┌────────────────────────────────────────┐ │
│  │     SdrSubprocessWrapper              │ │
│  │  • spawn('dump1090 --net ...')        │ │
│  │  • parse stdout (JSON/CSV)            │ │
│  │  • emit LBSignal batches              │ │
│  └──────────────────┬─────────────────────┘ │
│                     │                        │
│        ┌────────────┼────────────┐          │
│        ▼            ▼            ▼          │
│   ┌─────────┐  ┌─────────┐  ┌──────────┐    │
│   │ dump1090│  │AIS-catch│  │ dsd-neo  │    │
│   │(ADS-B) │  │  (AIS)  │  │(P25/DMR) │    │
│   └─────────┘  └─────────┘  └──────────┘    │
│                                              │
└─────────────────────────────────────────────┘
```

### 3.2 Supported Signals

| Signal | Frequency | Tool | Status |
|--------|-----------|------|--------|
| ADS-B | 1090 MHz | dump1090 | PLANNED |
| AIS | 161.975/162.025 MHz | AIS-catcher | PLANNED |
| P25/DMR | 150-470 MHz | dsd-neo | PLANNED |
| FM RDS | 88-108 MHz | fm demod | PLANNED |

---

## Phase 4: Alert Delivery

### 4.1 Alert Channels

| Channel | Implementation | Status |
|---------|----------------|--------|
| **Push** | flutter_local_notifications | DONE |
| **Email** | SMTP mailer (desktop) | PLANNED |
| **SMS** | Twilio API (desktop) | PLANNED |
| **Webhook** | HTTP POST (desktop) | PLANNED |

### 4.2 Alert Routing

Configurable per threat type:
```yaml
alerts:
  stingray:
    push: true
    email: true
    webhook: "https://example.com/alert"
  rogue_ap:
    push: true
    sms: false
  deauth_storm:
    push: true
    email: true
    sms: true
```

---

## Phase 5: Headless Backend

### 5.1 Desktop Modes

| Mode | Description |
|------|-------------|
| **GUI** | Full Flutter desktop app (current) |
| **Headless** | CLI service, no display required |
| **API Server** | REST API + Web dashboard |

### 5.2 Service Configuration

```yaml
service:
  mode: headless  # gui | headless | api_server
  port: 8080
  
database:
  path: /var/lib/littlebrother/lbscan.db
  
scan:
  continuous: true
  interval_seconds: 5
  
alerts:
  channels: [push, email, webhook]
```

---

## Implementation Order

### Phase 1 (Weeks 1-3)
1. [ ] Deauth Storm Detector
2. [ ] Enhanced Rogue AP heuristics  
3. [ ] AirTag/SmartTag Detector
4. [ ] BLE Tracking Alert improvements

### Phase 2 (Weeks 4-6)
5. [ ] REST API server module
6. [ ] mDNS desktop discovery
7. [ ] Mobile→Desktop sync client
8. [ ] Database merge layer

### Phase 3 (Weeks 7-10)
9. [ ] SDR subprocess adapter skeleton
10. [ ] ADS-B integration (dump1090)
11. [ ] AIS integration (AIS-catcher)
12. [ ] P25/DMR integration (dsd-neo)

### Phase 4 (Weeks 11-12)
13. [ ] Email alert module
14. [ ] SMS alert module
15. [ ] Webhook alert module
16. [ ] Headless mode

---

## Legal Notes

All features operate in **passive receive-only mode**:
- No signal transmission, injection, or jamming
- "RF kill" affects only user's own device radios
- For research, training, and authorized security audits only
- SDR reception subject to local regulations

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 0.8.0 | 2026-04-03 | Feature expansion roadmap created |
