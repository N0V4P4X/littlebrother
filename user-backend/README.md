# LittleBrother User Backend

Headless scanning service and data management backend for LittleBrother.

## Purpose

The user backend service handles:
- **Scanning orchestration** - Continuous passive RF capture without UI
- **Local database management** - SQLite storage for observations and sessions
- **Data lifecycle management** - View, archive, delete raw data while preserving metadata
- **Crowdsource sync** - Upload refined metadata to the crowdsource server

## Features

- Headless operation (no display required)
- Persistent scanning on servers or Raspberry Pi
- REST API for integration with user frontend
- Scheduled scans and automation support
- User data management (view, archive, delete)
- Metadata upload to crowdsource server

## Setup

### Prerequisites

- Flutter SDK >= 3.3.0
- For BLE scanning: BlueZ on Linux
- For WiFi scanning: NetworkManager on Linux

### Installation

```bash
cd user-backend
flutter pub get

# Generate OUI table
python3 ../scripts/gen_oui.py

# Copy assets
mkdir -p assets/oui
cp ../assets/oui/oui_table.json assets/oui/
```

### Configuration

Edit `lib/config.dart` or use environment variables:

```bash
export LB_BACKEND_PORT=8081
export LB_DB_PATH=/path/to/data.db
export LB_CROWDSOURCE_URL=http://localhost:8080
```

### Running

```bash
# Development
flutter run

# Production
flutter build linux --release
./build/linux/x64/release/bundle/littlebrother_backend
```

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/status` | GET | Service status |
| `/api/scan/start` | POST | Start scanning session |
| `/api/scan/stop` | POST | Stop scanning session |
| `/api/sessions` | GET | List all sessions |
| `/api/sessions/<id>` | GET | Get session details |
| `/api/sessions/<id>/delete` | POST | Delete session |
| `/api/sessions/<id>/archive` | POST | Archive session |
| `/api/sync/crowdsource` | POST | Upload to crowdsource server |
| `/api/stats` | GET | Database statistics |

## Data Retention

| Data Type | Default | User Control |
|-----------|---------|--------------|
| Raw observations | 7 days | Configurable |
| Threat events | 30 days | Configurable |
| GPS waypoints | 30 days | Auto-cleanup |
| Aggregated cells | Indefinite | Never deleted |
| Sessions | Until user deletes | View/Archive/Delete |

## Architecture

```
user-backend/
├── lib/
│   ├── main.dart              # CLI entry point
│   ├── backend_service.dart   # Main service orchestrator
│   ├── db/
│   │   └── backend_db.dart   # Database operations
│   ├── api/
│   │   └── rest_api.dart     # HTTP API server
│   └── sync/
│       └── crowdsource_sync.dart  # Upload to crowdsource server
└── pubspec.yaml
```

## Connecting to User Frontend

The user backend exposes a REST API that the user frontend can connect to:

```dart
// Example: User frontend connects to backend
final response = await http.get('http://localhost:8081/api/status');
```

Or use Unix socket for local communication:

```dart
final socket = await UnixSocket.connect('/var/run/littlebrother.sock');
```

## Crowdsource Sync

Upload refined metadata to the crowdsource server:

```bash
curl -X POST http://localhost:8081/api/sync/crowdsource \
  -H "Content-Type: application/json" \
  -d '{"since": "2026-04-01T00:00:00Z"}'
```

The backend will:
1. Query refined metadata from local database
2. Serialize to JSON
3. POST to crowdsource server `/api/sync`
4. Handle authentication and retries

## Status

**Development** - The user backend structure is being defined. Core scanning logic is currently in the user-app.
