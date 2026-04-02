# LittleBrother System Architecture

Version: 0.7.2 (2026-04-02)

---

## Overview

LittleBrother is a passive RF intelligence platform organized as a three-tier system:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        LittleBrother System                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────────┐   │
│  │   User Frontend  │     │   User Backend  │     │  Crowdsource Server  │   │
│  │   (Flutter UI)   │◄───►│  (Scan Service) │◄───►│  (Aggregation Hub)   │   │
│  └─────────────────┘     └─────────────────┘     └─────────────────────┘   │
│         │                        │                        │                   │
│         │                        │                        │                   │
│         ▼                        ▼                        ▼                   │
│  Mobile/Desktop            Local SQLite           Crowdsource SQLite          │
│  Interface                 Database               Database                    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Tier 1: User Frontend

**Location:** `user-app/`

The Flutter application provides the user interface for:
- Radar HUD visualization
- Signal list and threat log viewing
- Intel Map with geohash grid overlay
- OPSEC controls (RF kill)
- Session management and data export

### Platforms
- Android (primary) - full RF scanning
- Linux (desktop) - WiFi, BLE, GPS
- iOS/macOS/Windows (planned) - graceful degradation

### Key Modules
```
user-app/lib/
├── core/                    # Shared constants, models, database
│   ├── constants/          # Magic numbers, channel names
│   ├── db/                 # SQLite DAOs, geohash, OUI lookup
│   ├── models/             # LBSignal, LBThreatEvent, LBSession
│   ├── platform/           # Platform detection utilities
│   └── services/           # Cell cache, OpenCellID lookup
├── modules/                 # Scanner implementations
│   ├── wifi/              # Wi-Fi AP scanning
│   ├── ble/               # Bluetooth LE scanning
│   ├── cell/              # Cellular tower detection (Android)
│   ├── gps/               # GPS position tracking
│   ├── shell/             # Shell command scanner (Linux)
│   ├── mqtt/              # MQTT signal ingestion (optional)
│   └── bt_classic/        # Classic Bluetooth scanning (Linux)
├── alerts/                 # Push notifications
├── analyzer/               # Stingray/rogue AP detection
├── opsec/                  # RF kill controls
└── ui/                     # Screens, widgets, themes
```

---

## Tier 2: User Backend

**Location:** `user-backend/`

A Dart service that handles:
- Scanning orchestration (continuous passive RF capture)
- Local SQLite database management
- Session data lifecycle (view, delete, archive)
- Metadata retention policies
- Upload to crowdsource server

### Purpose
The backend service decouples scanning from the UI, enabling:
- Headless operation (no display required)
- Persistent scanning on servers/Raspberry Pi
- User data management without mobile app
- Scheduled scans and automation

### Key Components
```
user-backend/lib/
├── main.dart               # CLI entry point
├── scan_service.dart       # ScanCoordinator wrapper
├── db/
│   └── lb_database.dart    # Local SQLite (shared with user-app)
├── api/
│   └── rest_api.dart       # HTTP API for user-app communication
└── sync/
    └── crowdsource_sync.dart  # Upload refined metadata to server
```

### Data Lifecycle
```
Raw Scan Data → Local DB → (User Controls) → Archive/Delete
                                     │
                                     ▼
                            Metadata Upload
                                     │
                                     ▼
                          Crowdsource Server
```

### Metadata Retention
| Data Type | Default Retention | User Control |
|-----------|-------------------|--------------|
| Raw observations | 7 days | Configurable |
| Threat events | 30 days | Configurable |
| GPS waypoints | 30 days | Auto-cleanup |
| Aggregated cells | Indefinite | Never deleted |
| Sessions | Until user deletes | View/Archive/Delete |

---

## Tier 3: Crowdsource Server

**Location:** `crowdsource-server/`

A server application that:
- Aggregates signal metadata from multiple users
- Validates and refines crowdsourced data
- Provides web dashboard for administration
- Manages trust scores and data provenance

### Components
```
crowdsource-server/lib/
├── main.dart               # Entry point
├── http_server.dart        # REST API + web dashboard
├── config.dart             # YAML configuration
├── db/
│   └── server_db.dart      # Crowdsource SQLite database
├── mqtt/
│   └── subscriber.dart     # MQTT broker subscriber
├── web/
│   └── dashboard.dart      # Web UI (served as HTML)
├── refinement/
│   ├── signal_processor.dart    # Data validation
│   ├── deduplication.dart      # Remove duplicate signals
│   └── trust_scoring.dart      # Source reputation
└── sync/
    └── peer_protocol.dart  # P2P sync protocol
```

### Trust Model
| Source | Default Weight | Description |
|--------|----------------|-------------|
| `local` | 1.0 | On-device scanning (highest trust) |
| `user_backend` | 0.9 | User-managed backend service |
| `crowdsourced_clean` | 0.8 | Pre-validated community data |
| `crowdsourced_dirty` | 0.3 | Raw data requiring validation |
| `mqtt` | 0.0 | External feeds (disabled by default) |

### Signal Refinement
The server refines crowdsourced metadata based on signal type:
- **Cell towers**: Triangulation from multiple observations
- **WiFi APs**: Deduplication by BSSID, geohash clustering
- **BLE devices**: Persistent device correlation across sources
- **Geographic bounds**: Confidence scoring based on observation spread

---

## Data Flow

### Local Scanning (User App/Backend)
```
1. ScanCoordinator.startScan()
2. Scanner modules emit signal batches
3. Signals geotagged with GPS position
4. Stored in local SQLite (lbscan.db)
5. Analyzer runs threat detection
6. Alerts pushed via AlertEngine
```

### Crowdsource Upload
```
1. User initiates sync (manual or scheduled)
2. Backend queries refined metadata from local DB
3. Metadata serialized to JSON
4. POST to crowdsource-server /api/sync
5. Server validates and applies trust scoring
6. Data merged into crowdsource database
```

### Crowdsource Ingestion
```
1. MQTT broker publishes signals to topic
2. Server subscriber receives on lb/signals/raw/*
3. Signal validated against schema
4. Stored in dirty table for review
5. Admin validates or rejects via dashboard
6. Validated signals merged into clean table
```

---

## Shared Components

**Location:** `packages/lb-models/`

Common data models shared between all tiers:
```dart
// Signal model
class LBSignal {
  String id;
  String signalType;     // wifi, ble, cell
  String identifier;     // MAC, BSSID, Cell ID
  String? displayName;   // SSID, device name
  int rssi;
  double? lat, lon;
  String? geohash;
  DateTime timestamp;
  Map<String, dynamic> metadata;
}

// Session model
class LBSession {
  String id;
  DateTime startedAt;
  DateTime? endedAt;
  int observationCount;
  int threatCount;
}

// Threat event model
class LBThreatEvent {
  String id;
  String sessionId;
  String threatType;     // stingray, rogue_ap, ble_tracker
  int severity;          // 1-5
  String? evidenceJson;
  DateTime detectedAt;
}
```

---

## Configuration

### User App/Backend
Configuration via `secrets.dart`:
- OpenCellID API key
- Privacy mode settings
- Scan intervals
- Alert thresholds

### Crowdsource Server
Configuration via `config.yaml`:
```yaml
server:
  port: 8080

mqtt:
  enabled: true
  host: localhost
  raw_port: 1883
  clean_port: 8883

database:
  dirty_retention_days: 7
  location_retention_days: 30

trust:
  defaults:
    local: 1.0
    crowdsourced_clean: 0.8
    crowdsourced_dirty: 0.3
    mqtt: 0.0
```

---

## Production Considerations

### Security
- TLS required for all client-server communication
- API key authentication for user backend connections
- Input validation on all crowdsourced data
- Rate limiting to prevent abuse

### Privacy
- Only metadata uploaded to crowdsource server (no raw capture)
- User-controllable data retention
- GDPR-compliant data handling
- Geographic fuzzing option for sensitive areas

### Scalability
- Database partitioning by region/date
- Horizontal scaling via load balancer
- CDN for static dashboard assets
- Redis caching for hot data

### Monitoring
- Health check endpoints
- Metrics export (Prometheus)
- Structured logging
- Alerting on anomaly detection

---

## Directory Structure

```
littlebrother/
├── docs/
│   └── ARCHITECTURE.md          # This file
│
├── packages/
│   └── lb-models/                # Shared Dart models
│       ├── lib/
│       │   └── lb_models.dart
│       └── pubspec.yaml
│
├── user-app/                     # Flutter frontend
│   ├── lib/
│   ├── android/, ios/, linux/
│   ├── pubspec.yaml
│   └── README.md
│
├── user-backend/                 # User backend service
│   ├── lib/
│   ├── pubspec.yaml
│   └── README.md
│
├── crowdsource-server/           # Aggregation server
│   ├── lib/
│   ├── pubspec.yaml
│   └── README.md
│
├── README.md                     # Root project README
├── CHANGELOG.md
├── TODO.md
└── LICENSE.txt
```

---

## Migration Notes

### v0.7 → v0.8
The project structure is being reorganized into a monorepo with three distinct components:

1. **User App** (formerly top-level `lib/`) - Flutter application
2. **User Backend** (new) - Dart service for headless operation
3. **Crowdsource Server** (formerly `server/`) - Aggregation server

Existing users should:
1. Pull latest changes
2. Review new directory structure
3. Update any custom scripts or integrations

The `server/` directory has been renamed to `crowdsource-server/` for clarity.
