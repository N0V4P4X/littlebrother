# LittleBrother Server

LAN Control Panel and Crowdsourced Data Hub for LittleBrother.

## Features

- **System Tray** - Quick access controls from desktop system tray
- **Web Dashboard** - Browser-based control panel accessible from any device on LAN
- **MQTT Integration** - Connect to local Mosquitto broker for crowdsourced data
- **Signal Validation** - Review and validate incoming signals from external sources
- **Peer Sync** - Share clean signal data with trusted LAN peers

## Requirements

- Flutter SDK >= 3.3.0
- Mosquitto MQTT broker (optional, for crowdsourcing)
- Linux desktop (Debian 13 tested)

## Setup

1. **Install dependencies:**
   ```bash
   cd server
   flutter pub get
   ```

2. **Configure:**
   ```bash
   cp config.yaml.example config.yaml
   # Edit config.yaml with your settings
   ```

3. **Run:**
   ```bash
   flutter run
   ```

Or build for release:
```bash
flutter build linux --release
```

## Configuration

Edit `config.yaml`:

| Setting | Description | Default |
|---------|-------------|---------|
| `server.port` | HTTP server port | 8080 |
| `mqtt.enabled` | Enable MQTT ingestion | false |
| `mqtt.host` | Mosquitto host | localhost |
| `mqtt.raw_port` | Raw data port | 1883 |
| `mqtt.clean_port` | Clean data port | 8883 |
| `database.dirty_retention_days` | Days to keep unvalidated signals | 7 |
| `database.location_retention_days` | Days to keep location history | 30 |
| `trust.defaults.local` | Trust weight for local scanning | 1.0 |
| `trust.defaults.crowdsourced_clean` | Trust for validated community data | 0.8 |
| `trust.defaults.crowdsourced_dirty` | Trust for raw community data | 0.3 |
| `trust.defaults.mqtt` | Trust for MQTT feeds | 0.0 |

## Mosquitto Setup (Optional)

To enable crowdsourced data:

1. Install Mosquitto:
   ```bash
   sudo apt install mosquitto mosquitto-clients
   ```

2. Start Mosquitto:
   ```bash
   sudo systemctl start mosquitto
   sudo systemctl enable mosquitto
   ```

3. Configure topics in `config.yaml`:
   ```yaml
   mqtt:
     enabled: true
     host: localhost
   ```

4. Publish signals to:
   - `lb/signals/raw/wifi` - Raw WiFi signals
   - `lb/signals/raw/ble` - Raw BLE signals  
   - `lb/signals/raw/cell` - Raw cell signals

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/status` | GET | Server status |
| `/api/scan/start` | POST | Start scanning |
| `/api/scan/stop` | POST | Stop scanning |
| `/api/crowdsource` | GET | Crowdsource status |
| `/api/crowdsource/dirty` | GET | Unvalidated signals |
| `/api/crowdsource/validate/<id>` | POST | Validate signal |
| `/api/crowdsource/reject/<id>` | POST | Reject signal |
| `/api/peers` | GET | List peers |
| `/api/peers/add` | POST | Add peer |
| `/api/peers/sync/<id>` | POST | Sync with peer |
| `/api/settings` | GET | Get settings |
| `/api/db/stats` | GET | Database statistics |

## Dashboard

Access the web dashboard at `http://localhost:8080` from any device on the LAN.

Features:
- Real-time signal counts
- MQTT configuration
- Signal validation controls
- Peer management
- Settings

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    LittleBrother Server                      │
├─────────────────────────────────────────────────────────────┤
│  Tray Manager  │  HTTP Server  │  SQLite Database           │
│  (system tray)│  (port 8080)  │  (clean/dirty separation)  │
└─────────────────────────────────────────────────────────────┘
        │              │                    │
        ▼              ▼                    ▼
   OS Tray        Web Browser         Local Data
   Controls      Dashboard UI       Storage
```

## Trust Weights

| Source | Default Weight | Description |
|--------|----------------|-------------|
| `local` | 1.0 | On-device scanning |
| `crowdsourced_clean` | 0.8 | Pre-validated community data |
| `crowdsourced_dirty` | 0.3 | Raw data requiring validation |
| `mqtt` | 0.0 | Disabled by default |

## Future Plans

- [ ] Real-time WebSocket updates
- [ ] Peer-to-peer sync
- [ ] Archive management with compression
- [ ] Import/export databases
- [ ] Location fuzzing for privacy
- [ ] Threat definition DSL
