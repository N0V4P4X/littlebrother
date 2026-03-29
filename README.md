# LittleBrother

Passive RF intelligence platform — Wi-Fi · BLE · Cellular · IMSI Detection · Evasion Automation

Version: 0.1.0-alpha (Phase 1–5 partial)

---

## Setup on Debian (N3XU5)

### 1. Install Flutter

```bash
cd ~/DevOps
git clone https://github.com/flutter/flutter.git -b stable
echo 'export PATH="$PATH:$HOME/DevOps/flutter/bin"' >> ~/.bashrc
source ~/.bashrc
flutter doctor
```

### 2. Android SDK (if not already present)

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

scripts/
└── gen_oui.py                         # IEEE OUI table generator (run once)
```

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
- [ ] **P5** — Intel Timeline screen (session history, export)
- [ ] **P6** — Cell map overlay
- [ ] **P6** — OpenCelliD sync
- [ ] **P6** — PhysicalChannelConfig listener (band + channel width telemetry)
- [ ] **P7** — iOS port
- [ ] **P7** — Desktop (Linux) port

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

---

## Legal

LittleBrother operates in passive receive-only mode. No signals are transmitted,
injected, spoofed, or jammed. Active RF interference is illegal under 18 U.S.C. § 1362
and FCC Part 97. The "RF kill" feature affects only the user's own device radios.

GPL-3.0 License — see LICENSE


### 1. Install Flutter

```bash
cd ~/DevOps
git clone https://github.com/flutter/flutter.git -b stable
echo 'export PATH="$PATH:$HOME/DevOps/flutter/bin"' >> ~/.bashrc
source ~/.bashrc
flutter doctor
```

### 2. Android SDK (if not already present)

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
└── WakeLockHandler.kt                 # Partial wakelock for background scan

scripts/
└── gen_oui.py                         # IEEE OUI table generator (run once)
```

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
- [ ] **P5** — Intel Timeline screen (session history, export)
- [ ] **P6** — Cell map overlay
- [ ] **P6** — OpenCelliD sync
- [ ] **P7** — iOS port
- [ ] **P7** — Desktop (Linux) port

---

## Legal

LittleBrother operates in passive receive-only mode. No signals are transmitted,
injected, spoofed, or jammed. Active RF interference is illegal under 18 U.S.C. § 1362
and FCC Part 97. The "RF kill" feature affects only the user's own device radios.

GPL-3.0 License — see LICENSE
