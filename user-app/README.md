# LittleBrother User App

Flutter mobile/desktop application for passive RF intelligence collection.

> **Part of the three-tier LittleBrother system.** See [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) for full architecture.

## Features

- **Radar HUD** - Animated radar display with real-time signal blips
- **Signal Scanning** - Wi-Fi, BLE, Cellular, GPS capture
- **Threat Detection** - Stingray, rogue AP, and BLE tracker detection
- **Intel Map** - Geohash grid overlay with marker clustering
- **OPSEC Controls** - RF kill switch for evasion automation
- **Data Export** - CSV export for external analysis

## Supported Platforms

| Platform | Status | Signals |
|----------|--------|---------|
| Android | Primary | Wi-Fi, BLE, Cellular, GPS |
| Linux | Tested | Wi-Fi, BLE, GPS |
| iOS | Planned | BLE, GPS (Wi-Fi/Cell unavailable) |
| macOS | Planned | TBD |
| Windows | Planned | TBD |

## Setup

### Prerequisites

- Flutter SDK >= 3.3.0
- For Android: Android SDK with API 21+
- For Linux: BlueZ, NetworkManager, GeoClue

### Installation

```bash
cd user-app
flutter pub get

# Generate OUI table (first time only)
python3 ../scripts/gen_oui.py

# Connect device and run
flutter devices
flutter run --release
```

### Linux Desktop

```bash
# Install system dependencies
sudo apt install -y bluez libbluetooth-dev network-manager geoclue-2.0 libgeoclue-2-0

# Enable Linux desktop
flutter config --enable-linux-desktop

# Build and run
flutter build linux --release
./build/linux/x64/release/bundle/littlebrother
```

### Android

1. Enable USB debugging on your device
2. Connect via USB
3. Run `flutter run`

## Project Structure

```
user-app/
├── lib/
│   ├── core/              # Core modules
│   │   ├── constants/    # Magic numbers, channel names
│   │   ├── db/          # SQLite DAOs, geohash, OUI lookup
│   │   ├── models/      # Signal, session, threat models
│   │   ├── platform/    # Platform detection
│   │   └── services/    # Cell cache, OpenCellID
│   ├── modules/          # Scanner implementations
│   │   ├── wifi/        # Wi-Fi AP scanning
│   │   ├── ble/         # Bluetooth LE scanning
│   │   ├── cell/        # Cellular tower detection (Android)
│   │   ├── gps/         # GPS position tracking
│   │   ├── shell/       # Shell command scanner (Linux)
│   │   ├── mqtt/        # MQTT ingestion (optional)
│   │   └── bt_classic/   # Classic Bluetooth (Linux)
│   ├── analyzer/         # Threat detection
│   ├── alerts/           # Push notifications
│   ├── opsec/            # RF kill controls
│   └── ui/               # Screens, widgets, themes
├── android/              # Android platform code
├── ios/                  # iOS platform code
├── linux/                # Linux desktop code
└── pubspec.yaml
```

## Data Storage

| Data | Location | Retention |
|------|----------|-----------|
| Signals | `lbscan.db` (SQLite) | Until user deletes |
| Sessions | `lbscan.db` | Until user deletes |
| Threat Events | `lbscan.db` | Until user deletes |
| Aggregated Cells | `lbscan.db` | Indefinite |

## Contributing

1. Follow existing code patterns
2. Use conditional imports for platform-specific code
3. Add stubs for unsupported platforms
4. Test on at least Android and Linux

## License

GPL-3.0 - See LICENSE.txt
