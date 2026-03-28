# LittleBrother

Passive RF intelligence platform — Wi-Fi · BLE · Cellular · IMSI Detection · Evasion Automation

Version: 0.1.0-alpha (Phase 1 — Foundation + Radar HUD + Scanner Modules)

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
