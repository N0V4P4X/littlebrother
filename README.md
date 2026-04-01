# LittleBrother

Passive RF intelligence platform — Wi-Fi · BLE · Cellular · SIGINT · Evasion Automation

Version: 0.6.0 (2026-04-01)

> **Platform**: Android primary · Linux desktop · iOS/macOS/Windows planned

---

## Feature Roadmap

### Currently Supported

#### Android

| Signal Type | Hardware | Coverage |
|-------------|----------|----------|
| Wi-Fi APs | Built-in WiFi | 2.4 / 5 / 6 GHz |
| BLE Devices | Built-in Bluetooth | 2.4 GHz |
| Cellular (LTE/NR/GSM/UMTS/CDMA) | Built-in modem | 600 MHz – 6 GHz |
| GPS Position | Built-in GPS/GNSS | L1 band |

#### Linux Desktop

| Signal | Implementation | Notes |
|--------|---------------|-------|
| WiFi | `nmcli` (NetworkManager) | Works out of box |
| BLE | `flutter_blue_plus` (bluez) | Requires bluez system package |
| GPS | `geolocator` (geoclue) | Uses system location service |
| Cell | Stub | Not available (no cellular hardware) |

### Planned Signal Types

#### External SDR Hardware (RTL-SDR / HackRF / etc.)

These require a USB OTG-connected software-defined radio dongle. No active transmission — pure passive reception.

| Signal | Frequency | Use Case | Status |
|--------|-----------|----------|--------|
| **P25 / Project 25** | 150–174 / 450–470 / 800 MHz | Police, fire, EMS dispatch (LMR trunking) | Planned |
| **ADS-B** | 1090 MHz | Aircraft position, altitude, callsign | Planned |
| **AIS** | 161.975 / 162.025 MHz | Maritime vessel tracking | Planned |
| **DMR** | 136–174 / 400–470 MHz | Digital radio (Tier I/II/III) | Planned |
| **FM RDS** | 88–108 MHz | Emergency broadcast PI codes, TA/TP flags | Planned |
| **TETRA** | 380–400 / 410–430 MHz | European emergency services | Future |

Integration via NDK CMake builds of existing C/C++ decoder libraries (`dsd-neo` for P25/DMR/NXDN/D-STAR/ProVoice, `dump1090` for ADS-B, `rtl-sdr` / `libairspy` drivers). Flutter MethodChannel bridge streams I/Q samples to native decoders.

#### Proprietary Hardware (Future — LittleBrother RF)

Long-term roadmap: design and build dedicated RF capture hardware with form factor similar to Flipper Zero but purpose-built for wardriving / RF SIGINT / OPSEC assessment. Target capabilities:

- Multi-band receiver: VHF / UHF / SHF (~50 MHz – 6 GHz)
- Real-time spectrum analysis
- Integrated GPS for geolocation
- Hardware-level signal classification
- On-device decode: P25, DMR, ADS-B, AIS
- Passive-only (no transmission) to stay within legal bounds
- Open hardware / open source firmware
- Native USB-C + Bluetooth connectivity to phone app

This device would replace the phone's limited radio hardware and enable the full passive RF intelligence stack without external dongles.

#### Flipper Zero Integration (Planned)

Flipper Zero supports sub-GHz RF reception, NFC, IR, and iButton reading. LittleBrother will eventually integrate:

- **Sub-GHz RX**: Capture and replay 433 MHz and other sub-GHz signals
- **Flipper as SDR bridge**: Use Flipper as a front-end for the LittleBrother app (connect via Bluetooth Serial or USB CDC)
- **Combined session data**: Merge Flipper captures with phone-native WiFi/BLE/Cell data in a unified intel database

### Map Features (v0.6.0+)

- **Geohash Grid Overlay**: Density-based colored cells showing device concentration
  - Color by dominant type: WiFi (cyan), BLE (coral), Cell (orange)
  - Opacity scales with observation count (15% - 75%)
  - Threat borders: Clean (green), Watch (yellow), Hostile (red)
- **Precision Selector**: Switch between 6 (1km), 7 (150m), 8 (38m) char precision
- **Dynamic Precision**: Auto-adjusts based on zoom level (in progress)
- **Marker Clustering**: Deflock-style clusters for dense areas
  - Tap cluster to zoom in and reveal individual markers
  - Count badge shows device count
- **Privacy Mode**: Reduces visibility at high precision (6+ chars)
- **Multiple Tile Providers**: OSM, CartoDB Voyager, CartoDB Dark, OpenTopoMap
- **Legend Overlay**: Shows color key for threat levels and device types

---

## Device Intel Map

A map-based view of all detected devices, time-stamped and geolocated — similar to DeFlock but for all RF signals.

### Purpose

Isolate persistent static nodes (cell towers, fixed BLE beacons, static rogue APs) vs. mobile nodes (phones, vehicles). When a malicious static node is present in an area, it will be visible from multiple GPS coordinates within its broadcast radius as you walk/drive — providing triangulated evidence of its location.

### Signal-specific broadcast radii for geolocation heuristics:

| Signal Type | Typical Range | Indicates if Static |
|-------------|---------------|--------------------|
| **Cell (LTE/5G)** | 1–25 km (rural), 200m–2km (urban) | If seen consistently across geohash changes |
| **Wi-Fi AP** | 20–100m indoor, 100–250m outdoor | Static if geohash stable across sessions |
| **BLE** | 0–50m (normal), 50–100m (high TX) | If seen >50m: likely a phone/car, not a fixed beacon |
| **P25 / LMR** | 5–50 km (high-site tower) | Static tower if triangulated from 2+ positions |
| **ADS-B** | 200–400 km (airborne), 0–100 km (ground) | N/A — aircraft are always mobile |

### Map Features

- **Pin map** (Google Maps / OpenStreetMap) with color-coded signal clusters
- **Time slider**: scrub through a session or across all historical data
- **Signal trail**: draw breadcrumb lines for mobile nodes across GPS fixes
- **Persistence heatmap**: overlay showing how frequently each area was scanned
- **Triangulation view**: for static signals seen from 2+ GPS points, draw intersection circles and highlight centroid
- **Filter panel**: filter by signal type, MAC/BSSID/Cell ID, time range, threat level, favorites
- **Favorites / Watchlist**: star devices of interest; auto-flag if re-encountered at new location
- **Static vs. Mobile classification**: algorithm compares GPS fixes across detections to classify
  - Static: device seen across ≥3 distinct geohashes, GPS centroid stddev < 50m
  - Mobile: device seen across ≥3 distinct geohashes, GPS centroid stddev > 100m
  - Inconclusive: too few detections to classify
- **Cluster analysis**: DBSCAN or similar to identify repeated static nodes in a walk/drive session
- **Export**: KML/CSV of pinned devices with full metadata for use in external GIS tools

---

### Linux (Primary Desktop Target)

- **BLE**: ✅ `flutter_blue_plus` via BlueZ
- **Wi-Fi AP scan**: ✅ `nmcli device wifi list` CLI wrapper
- **GPS**: ✅ `geolocator` via GeoClue
- **Cell**: ❌ No cellular hardware — stub with diagnostic message
- **Notifications**: ✅ `flutter_local_notifications`
- **OPSEC (airplane mode)**: ❌ No system control — stub with log warning

Platform-specific implementations use Dart conditional imports: Android impl + Linux impl + stub for all unsupported platforms. Code that calls native channels is gated behind `LBPlatform` capability flags — no crashes on non-Android.

### macOS

- **BLE**: ✅ `flutter_blue_plus` via CoreBluetooth
- **Wi-Fi AP scan**: ⚠️ `networksetup -getairportnetwork` or Airport framework CLI
- **GPS**: ✅ `geolocator` via CoreLocation
- **Cell**: ❌ No cellular hardware — stub
- **Notifications**: ✅ `flutter_local_notifications`
- **OPSEC**: ❌ No system control — stub

### Windows

- **BLE**: ✅ `flutter_blue_plus` via WinRT/Bluetooth LE APIs (hardware-dependent)
- **Wi-Fi AP scan**: ⚠️ `netsh wlan show networks mode=ssid` or WMI
- **GPS**: ✅ `geolocator` via Windows Location API
- **Cell**: ❌ No cellular hardware — stub
- **Notifications**: ✅ `flutter_local_notifications`
- **OPSEC**: ❌ No system control — stub

### iOS

- **BLE**: ✅ `flutter_blue_plus` via CoreBluetooth
- **Wi-Fi AP scan**: ❌ Requires special entitlements from Apple; not available to 3rd-party apps
- **GPS**: ✅ `geolocator` via CoreLocation
- **Cell**: ❌ No public API for tower info; App Store policy prohibits this
- **Notifications**: ✅ `flutter_local_notifications`
- **OPSEC**: ❌ No system control — stub

**iOS philosophy**: Full graceful degradation. App runs and provides BLE + GPS intel. Cell/WiFi scan features are Android-only with a clear diagnostic message explaining why.

### Cross-Platform Architecture

Platform-specific code is isolated behind abstract interfaces:

```
ScanCoordinator
├── WifiScanner      → WifiScannerAndroid / WifiScannerLinux / *_Stub
├── BleScanner       → flutter_blue_plus (cross-platform)
├── CellScanner      → CellScannerAndroid / CellScannerLinux / CellScannerStub
├── GpsTracker       → GeolocatorWrapper (cross-platform)
├── AlertEngine      → cross-platform
└── OpsecController  → OpsecControllerAndroid / OpsecControllerLinux / OpsecControllerStub
```

Detection algorithms (stingray, rogue AP, BLE tracker) are platform-agnostic and run identically everywhere.

---

## Phase Completion Status

---

## Known Issues & Limitations

### Platform-Specific

| Issue | Platform | Status |
|-------|----------|--------|
| Wi-Fi scan returns empty | iOS | Expected - no public API for Wi-Fi enumeration |
| Cell scanning non-functional | iOS/Linux/macOS/Windows | Expected - no cellular hardware APIs available |
| RF kill (OPSEC) toggle | Linux/macOS/Windows | Stub - no system control APIs |
| Wi-Fi scan silently fails | Android | May fail if NEARBY_WIFI_DEVICES permission not granted |

### General

- **Signal cache**: Unbounded cache can grow large over long sessions (mitigated with 5000 signal limit)
- **Aggregate map**: Limited to 200 cells for performance
- **Timeline export**: Large sessions may take time to generate CSV
- **Intel Map debug mode**: Debug builds show GPS status and observation statistics in toolbar (visible in `flutter run` or debug APK)

### Reporting Bugs

Please open an issue at https://github.com/N0V4P4X/littlebrother/issues using the [bug report template](.github/ISSUE_TEMPLATE/bug_report.md):
- Device model and Android version
- Steps to reproduce
- Relevant log output (adb logcat | grep LB_)

---

## Troubleshooting the Intel Map (GRID Layer)

If the gridded map shows "NO DATA" after running scan sessions, follow these diagnostic steps.

---

## Scanners & Providers

LittleBrother supports multiple scanning sources (providers) that can run concurrently:

### Built-in Scanners

| Scanner | Platform | Description |
|---------|----------|-------------|
| **WiFi** | All | Discovers nearby WiFi access points |
| **BLE** | All | Scans for Bluetooth Low Energy devices |
| **Cell** | Android | Detects cellular towers and neighbors |
| **GPS** | All | Tracks device location for geotagging |

### Extended Providers (Linux)

| Provider | Description |
|----------|-------------|
| **Shell Scanner** | Executes shell commands and parses output as signals. Currently configured for `arp -a` (network devices) and `iwlist scan` (WiFi details). |
| **MQTT Scanner** | Subscribes to an MQTT broker for external signal data. Configurable broker URL, port, credentials, and topics. |
| **Bluetooth Classic** | Uses `bluetoothctl` to discover classic Bluetooth (BR/EDR) devices on Linux. |

### Running with Debug Output

Use the debug script to see terminal output:

```bash
./scripts/run_debug.sh
```

This launches the app in debug mode so you can observe scanner activity and troubleshoot issues.

---

### Understanding the Debug Output

In debug builds (debug APK or `flutter run`), the Intel Map toolbar displays diagnostic information:

```
GPS: ✓ {lat: 37.7749, lon: -122.4194}
Data: 1500 total, 1200 with lat/lon, 800 with geohash
```

Or if there's a problem:

```
GPS: ✗ (running=false, error=Permission denied)
Data: 0 total, 0 with lat/lon, 0 with geohash
```

### Common Issues and Solutions

#### 1. GPS: ✗ (running=false, error=Permission denied)

**Problem:** Location permission not granted.

**Solution:**
1. Go to Settings → Apps → LittleBrother → Permissions
2. Grant Location permission (Allow all the time for best results)
3. Restart the app

#### 2. GPS: ✗ (running=false, error=null)

**Problem:** GPS service not started or hardware unavailable.

**Solution:**
1. Ensure Location is enabled in system settings
2. Check device has GPS hardware
3. Restart the app to retry GPS initialization

#### 3. GPS: ✓ but Data shows 0 total observations

**Problem:** No scan sessions have been run yet.

**Solution:**
1. Go to the RADAR screen
2. Start a scan session and let it run for a minute
3. Return to the Intel Map and refresh

#### 4. Data shows observations but 0 with lat/lon

**Problem:** Signals were captured but GPS wasn't providing location at scan time.

**Solution:**
1. Ensure GPS has a fresh fix (fresh location within last 30 seconds)
2. Start scan sessions while GPS is actively tracking
3. Check the debug log: `adb logcat | grep -i "coord"` for "Skipping geotag" messages

#### 5. Data shows observations with lat/lon but 0 with geohash

**Problem:** Old observations from before the geohash column was added.

**Solution:**
1. The app automatically migrates geohash on map load
2. If still showing 0, try a fresh scan session
3. For existing data, force rebuild: the aggregate rebuild runs automatically but has a 5-minute cache

#### 6. Grid shows cells but map is blank

**Problem:** Cells exist but aren't being rendered properly.

**Solution:**
1. Try changing precision (RES selector): coarse (1.2km), standard (150m), fine (38m)
2. Check filter settings (TIME, THREAT filters may be too restrictive)
3. Try TimeRange: ALL to see all historical data

### Force Refresh the Aggregate Data

The aggregate cells are rebuilt with a 5-minute cache to avoid expensive recomputation. To force a refresh:

1. Wait 5 minutes since last map view, OR
2. Modify the time filter (change from ALL to 24h and back) which triggers a reload, OR
3. Kill and restart the app (cache is stored in memory only)

### Manual Database Inspection

To inspect the database directly:

```bash
# Pull the database from Android device
adb pull /data/data/art.n0v4.littlebrother/files/lbscan.db ./lbscan.db

# Inspect with sqlite3
sqlite3 lbscan.db

# Check observation counts
SELECT COUNT(*) FROM observations;
SELECT COUNT(*) FROM observations WHERE lat IS NOT NULL;
SELECT COUNT(*) FROM observations WHERE geohash IS NOT NULL;

# Check aggregate cells
SELECT COUNT(*) FROM aggregate_cells;
SELECT * FROM aggregate_cells LIMIT 10;

# Check GPS metadata in observations
SELECT id, signal_type, lat, lon, geohash FROM observations LIMIT 5;
```

### Signal Flow for Geotagging

```
1. GpsTracker.start() → begins location stream
2. ScanCoordinator._onSignals() → receives signal batch
3. If GpsTracker.hasFreshFix (fix < 30 sec old):
   - Copy lat/lon from lastPosition to each signal
   - Compute geohash from lat/lon
   - Store in signal.metadata['geohash']
4. LBSignal.toMap() → writes to database (lat, lon, geohash columns)
5. rebuildAggregateCells() → groups by geohash, creates grid cells
```

If any step fails, the signal won't have coordinates and won't appear on the grid.

### Precision Levels

The grid supports three geohash precision levels:

| Precision | Characters | Approximate Size | Use Case |
|-----------|-------------|------------------|----------|
| Coarse    | 6           | 1.2 km × 0.6 km  | Wide-area surveys, sparse data |
| Standard  | 7           | 150 m × 75 m     | Normal wardriving (default) |
| Fine      | 8           | 38 m × 19 m      | Dense urban areas, detailed mapping |

Lower precision = fewer, larger cells = more likely to have data. If coarse works but fine shows nothing, your data is sparse.

---

## Setup on Debian (N3XU5)

### 1. Install build dependencies

```bash
# lld-19 is required by Flutter's native assets build step.
# Without it, `flutter build linux` fails with:
# "Failed to find any of [ld.lld, ld] in LocalDirectory: '/usr/lib/llvm-19/bin'"
sudo apt install -y lld-19
```

### 2. Install Flutter

```bash
cd ~/DevOps
git clone https://github.com/flutter/flutter.git -b stable
echo 'export PATH="$PATH:$HOME/DevOps/flutter/bin"' >> ~/.bashrc
source ~/.bashrc
flutter doctor
```

### 3. Android SDK (if not already present)

```bash
# Install via Android Studio or:
sudo apt install -y android-sdk
flutter config --android-sdk /usr/lib/android-sdk
```

Accept licenses:
```bash
flutter doctor --android-licenses
```

### 3. Clone and set up project

```bash
cd ~/DevOps
git clone git@github.com:N0V4P4X/littlebrother.git
cd littlebrother
```

### 4. Generate OUI table (first time only)

```bash
python3 scripts/gen_oui.py
```

This downloads the IEEE OUI registry (~2.5 MB) and writes `assets/oui/oui_table.json`.

### 5. Get dependencies

```bash
flutter pub get
```

### 6. Connect device and run

```bash
# Enable USB debugging on S25 Ultra:
# Settings → About → tap Build Number 7× → Developer Options → USB Debugging ON

flutter devices
flutter run --release
```

---

## Linux Desktop Build

### Prerequisites

```bash
# Install system dependencies
sudo apt install -y bluez libbluetooth-dev network-manager geoclue-2.0 libgeoclue-2-0

# Clone and setup
cd ~/DevOps
git clone git@github.com:N0V4P4X/littlebrother.git
cd littlebrother

# Enable Linux desktop support
flutter config --enable-linux-desktop

# Generate OUI table (first time only)
python3 scripts/gen_oui.py
```

### Build and Run

```bash
flutter pub get
flutter build linux
./build/linux/x64/release/bundle/littlebrother
```

### Linux Feature Support

| Signal | Implementation | Status |
|--------|---------------|--------|
| WiFi | `nmcli` (NetworkManager) | ✅ Works |
| BLE | `flutter_blue_plus` (via bluez) | ✅ Works |
| GPS | `geolocator` (via geoclue) | ✅ Works |
| Cell | Stub (no cellular hardware) | N/A |

**Note:** Cell scanning is not available on Linux desktop since there's no cellular modem. The app will run with WiFi, BLE, and GPS scanning only.

### Intel Map Layers

The aggregate map supports multiple visualization layers:

| Layer | Description |
|-------|-------------|
| GRID | Geohash-based density grid of all detected signals |
| TOWERS | Cell tower positions with threat coloring |
| WIFI | WiFi access point positions |
| BLE | Bluetooth LE device positions |
| TEST | Development test data (see below) |

**TEST Layer (Development Only):** This layer displays mock community data for UI testing. All markers are clearly labeled as `[TEST]` and display a warning banner. This layer will be removed before release builds.

---

## Samsung S25 / Android 12+ Notes

Samsung Galaxy S25 runs Android 15 (API 35). A few quirks to be aware of:

**Permission grant order matters.** The `PermissionGate` enforces the required sequence: Location (foreground) → Background Location → Nearby Wi-Fi. Tapping "GRANT ALL" handles this automatically. If you grant them out of order via Settings, Background Location may show as denied until you revisit the gate.

**`NEARBY_WIFI_DEVICES` is required for Wi-Fi scan results.** On Android 12+ `wifi_scan` returns empty results without this permission. It is declared without `neverForLocation` in the manifest so the OS can attach the location association Android requires for AP enumeration. Without it the scan API silently returns `[]`.

**Background Location is a separate dialog.** After granting foreground location the OS shows a second dialog for "Allow all the time." The native channel handles this cleanly on Samsung One UI (the `permission_handler` package has a known Samsung quirk on this dialog that the native fallback works around).

**Airplane Mode toggle (OPSEC kill) requires WRITE_SETTINGS.** The app will prompt you to grant this in System Settings the first time you use the RF kill feature.

---

## Project Structure

```
lib/
├── core/
│   ├── constants/lb_constants.dart    # All magic numbers + channel names
│   ├── models/lb_signal.dart          # LBSignal, LBThreatEvent, LBSession
│   ├── db/
│   │   ├── lb_database.dart           # SQLite — all DAOs
│   │   ├── oui_lookup.dart            # IEEE OUI vendor resolution
│   │   └── geohash.dart               # Pure Dart geohash encoder
│   └── scan_coordinator.dart          # Central orchestrator
├── modules/
│   ├── wifi/wifi_scanner.dart         # Wi-Fi AP scanning + normalization
│   ├── ble/ble_scanner.dart           # BLE passive scan + tracker ID
│   ├── cell/cell_scanner.dart         # Cellular via Kotlin channel
│   └── gps/gps_tracker.dart           # GPS position stream
├── analyzer/lb_analyzer.dart          # Stingray + rogue AP + BLE heuristics
├── alerts/alert_engine.dart           # Threat routing + push notifications
├── opsec/opsec_controller.dart        # RF kill + evasion automation
└── ui/
    ├── theme/lb_theme.dart            # Colors, text styles, MaterialTheme
    ├── radar/
    │   ├── radar_painter.dart         # CustomPainter — animated radar HUD
    │   └── radar_screen.dart          # Radar screen widget
    ├── screens/
    │   ├── signal_list_screen.dart    # Tabbed signal list
    │   ├── threat_log_screen.dart     # Threat events with evidence
    │   ├── opsec_screen.dart          # RF kill + automation controls
    │   └── permission_gate.dart       # Permission onboarding flow
    └── widgets/
        └── signal_tile.dart           # Signal list row widget

android/app/src/main/kotlin/art/n0v4/littlebrother/
├── MainActivity.kt                    # Flutter entry + channel registration
├── CellChannelHandler.kt              # TelephonyManager → Dart bridge
├── PermissionChannelHandler.kt        # Native permission requests (Samsung-safe)
└── WakeLockHandler.kt                 # Partial wakelock for background scan

ios/
├── Runner/
│   ├── Info.plist                     # Permission strings (Bluetooth, Location, Local Network)
│   └── Runner.entitlements            # wifi-info + app-groups entitlements
└── Podfile                            # iOS deployment target (13.0)

linux/
├── CMakeLists.txt                     # Linux desktop build (CMake + Ninja)
├── runner/                            # GTK application entry point
└── flutter/                           # Flutter plugin registration

scripts/
└── gen_oui.py                         # IEEE OUI table generator (run once)

tool/
└── lb_cli.dart                        # Gridland CLI/TUI entry point (planned)
```

---

## Data Transfer Between Clients

Scan data is portable across all LittleBrother clients (Android, Linux, macOS, Windows). Sessions, signals, and threat logs are stored in a local SQLite database — transfer it between devices to consolidate intel from multiple capture points.

**Database location:**
- Android / Linux / macOS: `{app_documents_dir}/lbscan.db`
- Windows: `%APPDATA%\littlebrother\lbscan.db`

**Transfer options:**

1. **Copy the DB file** — stop the app, copy `lbscan.db` to the target device, replace the local DB. All sessions, threat events, and GPS breadcrumbs transfer as-is.

2. **Export to CSV** — the Intel Timeline screen exports per-session CSV: timestamp, signal type, MAC/BSSID/Cell ID, RSSI, GPS coordinates, threat verdict. Useful for ingestion into external GIS or SIEM tools.

3. **SQLite direct** — the DB schema is in `lib/core/db/lb_database.dart`. Any SQLite client (sqlite3, DBeaver, etc.) can query or migrate data.

The DB schema uses `LBSession` as the top-level container. Each session owns its signals and threat events — moving a session record and its joined rows transfers a complete intel snapshot.

---

## Gridland CLI/TUI

> **Planned** — Gridland (gridland.io) is not yet production-ready. This section describes the intended architecture.

LittleBrother will ship a terminal-based companion tool built with **Gridland**, a cross-platform TUI framework that also renders in the browser. This enables:

- **Headless wardriving** on a Raspberry Pi or laptop — passive RF capture without a display
- **Server-side session processing** — ingest DB files, run analysis, output reports
- **CI/CD integration** — run stingray/rogue-AP heuristics against exported data in pipelines

**Architecture:** The CLI shares the core Dart modules with the Flutter app (`lib/core`, `lib/modules`, `lib/analyzer`, `lib/db`) via a separate entry point at `tool/lb_cli.dart`. Only the UI layer and platform-specific code diverge. Detection algorithms, signal models, and the DB layer are identical in both the Flutter app and the CLI.

```bash
# Planned usage
lb --db /path/to/lbscan.db --session 2026-03-29-wardrive analyze
lb --db /path/to/lbscan.db export-csv --output report.csv
lb --db /path/to/lbscan.db map --geojson out.geojson
```

Integration will begin once Gridland stabilizes beyond v0.

---

## Phase Completion Status

- [x] **P1** — Flutter scaffold, SQLite schema, platform channels, permission flow
- [x] **P1** — Radar HUD (CustomPainter, animated sweep, blips, threat flash)
- [x] **P2** — Wi-Fi scanner (normalization, risk scoring, OUI lookup)
- [x] **P2** — BLE scanner (passive, tracker signatures, interval estimation)
- [x] **P3** — Cell scanner (Kotlin, full LTE/NR/GSM/UMTS field capture)
- [x] **P3** — Signal list screen (tabbed, sortable)
- [x] **P4** — Analyzer (stingray heuristics, rogue AP, BLE tracker)
- [x] **P4** — Alert engine (push notifications, OPSEC auto-trigger)
- [x] **P5 partial** — Threat log screen with evidence detail
- [x] **P5 partial** — OPSEC panel (RF kill, automation toggle)
- [x] **P5 partial** — Intel Timeline screen (session history, export)
- [x] **P5 partial** — Cell scanner diagnostics + permission status UI
- [x] **P5 partial** — Enhanced Stingray heuristics (H6: TA anomaly, H7: neighbor stability, H4 weight fix)
- [ ] **P5** — Cell tab UI (full cell signal detail view)
- [x] **P6** — Cell map overlay (OpenStreetMap / flutter_map)
- [ ] **P6** — OpenCelliD sync (seed baseline from public cell tower DB)
- [ ] **P6** — PhysicalChannelConfig listener (band + channel width telemetry)
- [x] **P7 partial** — Cross-platform stubs (wake_lock, opsec_controller, cell_scanner, wifi_scanner) with conditional imports — Android + Linux + stub pattern
- [x] **P7 partial** — PermissionGate platform guard (Android: full permission flow; non-Android: feature availability notice + continue)
- [x] **P7 partial** — ScanCoordinator platform-awareness (gates Android-only features via LBPlatform flags)
- [x] **P7 partial** — Linux scaffold + build (BLE via BlueZ, Wi-Fi via nmcli, GPS via Geolocator/GeoClue, cell stub)
- [x] **P7 partial** — iOS files (Info.plist, entitlements, Podfile) with graceful degradation
- [ ] **P7** — iOS port (full graceful degradation)
- [ ] **P7** — macOS / Windows port
- [ ] **P8** — P25 / LMR scanner (RTL-SDR + dsd-neo NDK build)
- [ ] **P8** — ADS-B aircraft tracker (RTL-SDR + Mode S decoder)
- [ ] **P8** — Flipper Zero integration (sub-GHz RX + Bluetooth bridge)
- [ ] **P8** — FM RDS emergency broadcast detection
- [x] **P9** — Device Intel Map (geohash grid, mobile/stationary classification, cell detail)
- [ ] **P9** — OpenStreetMap / DeFlock-style tile overlay for the Intel Map
- [ ] **P9** — Threat modeling tools: classification rules, entity correlation, pattern-of-life analysis
- [ ] **P9** — Hardware: LittleBrother RF device (VHF–SHF SDR, multi-band, open hardware)

---

## Bug Fixes

### Round 1 — Permissions (v6)

**Scanning returning no results on S25** — three root causes fixed:

1. `NEARBY_WIFI_DEVICES` had `neverForLocation` flag in `AndroidManifest.xml`. Android 12+ requires location association for AP enumeration; `wifi_scan` silently returns `[]` without it. Flag removed.

2. `PermissionChannelHandler` used a single `pendingResult` / `pendingCode` field pair. Back-to-back permission requests (background location then nearby wifi in `_requestAll`) would overwrite the pending callback; `onRequestPermissionsResult` would compare against the wrong code and drop the result. Fixed by replacing with a `Map<Int, Result>` keyed by `requestCode`.

3. `NEARBY_WIFI_DEVICES` was marked `optional` in `PermissionGate`, so the app would skip past the permission gate and start scanning even without it — resulting in empty Wi-Fi results with no error. Now marked required.

**Sequential native permission requests** — `_requestAll` in `PermissionGate` now awaits each native channel call and calls `_checkAll()` between phases so the state is consistent before the next request fires.

### Round 2 — Scanner results (post-v6)

**Wi-Fi scanner reads empty results** — `getScannedResults()` was called immediately after `startScan()` with no delay. On Android 12+ the hardware scan is async — you get the previous cycle's (empty) cache. Fixed with a 500ms yield after `startScan`. Also added `canGetScannedResults()` guard before reading (throws on Samsung when location services toggle). When OS throttles `startScan` (4 scans/2min limit), now falls through to read cached results instead of returning nothing.

**Wake lock never acquired** — `WakeLockHandler` was fully wired in `MainActivity` but nothing in Dart ever called `acquire`. On Samsung One UI, `Timer.periodic` scan callbacks are killed within ~30s of screen-off by App Standby. Added `lib/core/wake_lock.dart` wrapper and wired `acquire`/`release` into `ScanCoordinator.startScan`/`stopScan`.

**Signal list shows stale snapshot** — `SignalListScreen` was passed `_coordinator.latestSignals` once at construction and never updated. Wrapped in a `StreamBuilder` in `main.dart` so it rebuilds on every signal batch.

### Round 3 — Blank UI / database / scanner fixes (v7+)

**SQLite PRAGMA failure on Android 15** — `openDatabase` used `onConfigure` to run `PRAGMA journal_mode = WAL`. On Samsung S25 / One UI 7 / Android 15, the `onConfigure` callback cannot execute PRAGMA statements — it threw `DatabaseException: Queries can be performed using SQLiteDatabase query or rawQuery methods only`. This exception was uncaught, causing `startScan()` to fail silently. Fixed by moving the PRAGMA from `onConfigure` to inside `_onCreate` with a try-catch wrapper.

**BLE RSSI filter bug** — `ble_scanner.dart` filtered out `rssi == 0` as "invalid" — but 0 is a valid RSSI value. Fixed condition to only filter negative values.

**Wi-Fi scanner throttling** — `CanStartScan.throttled` was never a valid enum value (it doesn't exist in the enum), so the throttle detection would not compile. Reimplemented throttle detection using a `throttledStream` that tracks time-based throttle state internally.

**Cell network type never reset** — When no serving cell was detected, `_currentNetworkType` stayed at the last known value instead of resetting to `'---'`. Fixed in `scan_coordinator.dart`.

**Timeline `_load()` hangs on error** — No error handling in `_load()`. If DB failed to open, `await db.getSessions()` threw and `_loading` was never set to `false`. Fixed with try-catch.

**R8/ProGuard build failure** — Release build failed with `Missing classes` for Google Play Core splitcompat. Fixed by adding `-dontwarn` rules to `proguard-rules.pro`.

**Wi-Fi `channelWidth` JSON serialization** — `'channel_width_mhz': ap.channelWidth ?? -1` returned the `WiFiChannelWidth` enum object (not an integer) when non-null, causing `jsonEncode` to fail with `Converting object to an encodable object failed`. Fixed with `?.index ?? -1`.

**Cell scanner `Map` type cast** — `raw as Map` → `raw as Map<Object?, Object?>` in `cell_scanner.dart` line 51.

**`debugPrint` not imported** — Added `import 'package:flutter/foundation.dart' show debugPrint;` to `alert_engine.dart`.

**Notifications made non-fatal** — Both `AlertEngine.init()` and `_pushNotification()` now catch exceptions so notification failures don't crash the app. Icon reference also removed to avoid startup failures.

**Notification icon unresolved** — `flutter_local_notifications` cannot find `ic_notification` despite it being present in the APK. The plugin runs in a different application context than the main app. Notifications are non-fatal as a workaround.

**Intel Timeline screen** — New screen (`timeline_screen.dart`) showing session history, recent threats, and CSV export. Added to bottom navigation.

**Throttling UI indicator** — RADAR nav item now shows an amber dot when Wi-Fi scanner is throttled.

### Round 4 — Notification icon fix

**Notification icon not showing (v8+)** — Three root causes:

1. R8/ProGuard was stripping `drawable/ic_notification` from release builds. Created `res/raw/keep.xml` to preserve it: `<resources tools:keep="@drawable/ic_notification" ...>`.

2. `ic_notification.png` was placed in `mipmap-*` directories (wrong resource type for `AndroidInitializationSettings`). Moved to `drawable/` as a vector drawable XML (`ic_notification.xml`). Status bar icons must be density-independent vector drawables, not bitmap mipmaps.

3. `AndroidInitializationSettings('ic_notification')` couldn't resolve the drawable name because the plugin runs in a different Android context. Fixed by removing `AndroidInitializationSettings` from `AlertEngine.init()` — notifications now fall back to the app's default icon, which is non-fatal. The `AndroidNotificationDetails.icon` field was set to `'ic_notification'` for per-notification icon selection. For expanded/large icon, `ByteArrayAndroidBitmap.fromBase64String()` is used, loading `assets/icons/ic_notification.png` via `rootBundle`. Resources verified present in APK: `res/drawable/ic_notification.xml`, `assets/flutter_assets/assets/icons/ic_notification.png`, `res/raw/keep.xml`.

---

## Legal

LittleBrother operates in passive receive-only mode. No signals are transmitted,
injected, spoofed, or jammed. Active RF interference is illegal under 18 U.S.C. § 1362
and FCC Part 97. The "RF kill" feature affects only the user's own device radios.

GPL-3.0 License — see LICENSE

