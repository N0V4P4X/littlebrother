# LittleBrother Crowdsource Server

LAN Control Panel and Crowdsourced Data Hub for LittleBrother.

> **Note:** This directory was renamed from `server/` to `crowdsource-server/` as part of the three-tier architecture refactoring. See [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) for details.

## Features

- **System Tray** - Quick access controls from desktop system tray
- **Web Dashboard** - Browser-based control panel accessible from any device on LAN
- **MQTT Integration** - Connect to local Mosquitto broker for crowdsourced data
- **Signal Validation** - Review and validate incoming signals from external sources
- **Peer Sync** - Share clean signal data with trusted LAN peers
- **Trust Scoring** - Weighted aggregation based on data source reputation

## Requirements

- Flutter SDK >= 3.3.0
- Mosquitto MQTT broker (optional, for crowdsourcing)
- Linux desktop (Debian 13 tested)

## Setup

### Development (Local)

```bash
cd crowdsource-server
flutter pub get
cp config.yaml.example config.yaml
# Edit config.yaml with your settings
flutter run
```

### Production

```bash
flutter build linux --release
./build/linux/x64/release/bundle/littlebrother_server
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
| `/api/scan/start` | POST | Start scanning (IPC stub) |
| `/api/scan/stop` | POST | Stop scanning (IPC stub) |
| `/api/crowdsource` | GET | Crowdsource status |
| `/api/crowdsource/dirty` | GET | Unvalidated signals |
| `/api/crowdsource/validate/<id>` | POST | Validate signal |
| `/api/crowdsource/reject/<id>` | POST | Reject signal |
| `/api/peers` | GET | List peers |
| `/api/peers/add` | POST | Add peer |
| `/api/peers/sync/<id>` | POST | Sync with peer |
| `/api/settings` | GET | Get settings |
| `/api/db/stats` | GET | Database statistics |
| `/api/sync` | POST | Receive sync from user backend |

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
│                  LittleBrother Crowdsource Server             │
├─────────────────────────────────────────────────────────────┤
│  Tray Manager  │  HTTP Server  │  SQLite Database           │
│  (system tray)│  (port 8080)  │  (clean/dirty separation)│
└─────────────────────────────────────────────────────────────┘
        │              │                    │
        ▼              ▼                    ▼
   OS Tray        Web Browser         Local Data
   Controls      Dashboard UI       Storage
```

## Trust Weights

| Source | Default Weight | Description |
|--------|----------------|-------------|
| `local` | 1.0 | On-device scanning (highest trust) |
| `user_backend` | 0.9 | User-managed backend service |
| `crowdsourced_clean` | 0.8 | Pre-validated community data |
| `crowdsourced_dirty` | 0.3 | Raw data requiring validation |
| `mqtt` | 0.0 | External feeds (disabled by default) |

---

## Production Deployment

### Security Considerations

1. **TLS/SSL** - Enable HTTPS for production:
   ```yaml
   server:
     port: 8443
     ssl_cert: /path/to/cert.pem
     ssl_key: /path/to/key.pem
   ```

2. **Authentication** - Add API key validation:
   ```yaml
   auth:
     enabled: true
     api_keys:
       - name: "user-backend-1"
         key: "hash_of_secret_key"
         permissions: ["sync", "read"]
   ```

3. **Rate Limiting** - Prevent abuse:
   ```yaml
   rate_limit:
     enabled: true
     requests_per_minute: 60
     burst: 10
   ```

4. **Input Validation** - Sanitize all incoming data:
   - Validate coordinate bounds (-90 to 90 lat, -180 to 180 lon)
   - Reject malformed MAC/BSSID formats
   - Limit metadata field sizes

### Database

- **Backups** - Schedule regular backups:
  ```bash
  # Daily backup at 3 AM
  0 3 * * * cp /var/lib/littlebrother/server.db /backup/server-$(date +\%Y\%m\%d).db
  ```

- **Cleanup** - Automatic purging of old data:
  - Dirty signals: 7 days (configurable)
  - Location history: 30 days (configurable)
  - Clean signals: retained indefinitely

### Monitoring

Add health check endpoint for load balancer:
```
GET /api/health → 200 OK with {"status": "healthy"}
```

### Scaling

For larger deployments:
- Use PostgreSQL instead of SQLite for concurrent writes
- Deploy behind nginx reverse proxy
- Add Redis cache for hot data
- Separate MQTT subscriber as independent service

## Future Plans

- [ ] Real-time WebSocket updates
- [ ] Peer-to-peer sync protocol
- [ ] Archive management with compression
- [ ] Import/export databases
- [ ] Location fuzzing for privacy
- [ ] Threat definition DSL
- [ ] Signal refinement algorithms
- [ ] Geographic deduplication
- [ ] Mobile app for server management
