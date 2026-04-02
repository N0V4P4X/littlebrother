# Changelog

All notable changes to this project will be documented in this file.

## [0.7.1] - 2026-04-02

### Fixed (Round 6 — external code review, first pass)
- **`classifyDeviceMovement` wrong distance metric** — missing `sqrt`, hardcoded longitude scaling (`lib/core/db/lb_database.dart`)
- **`BtClassicScanner` emitted `bluetoothctl discoverable on`** — OPSEC violation (`lib/modules/bt_classic/bt_classic_scanner.dart`)
- **`cell_id_lookup.dart` missing `debugPrint` import** — compile error (`lib/core/services/cell_id_lookup.dart`)
- **`AggregateMapScreen` GPS timer leaked + no `dispose()`** (`lib/ui/screens/aggregate_map_screen.dart`)
- **`LBDb.name` mismatch with README / adb pull docs** — `littlebrother.db` → `lbscan.db` (`lib/core/constants/lb_constants.dart`)
- **Missing `secrets.dart`** — project uncompilable without it (`lib/core/secrets.dart` created)
- **Signal batches silently dropped under scanner contention** — replaced `_processingSignals` flag with `ListQueue` drain loop (`lib/core/scan_coordinator.dart`)

### Fixed (Round 7 — external code review, second pass)
- **`RadarScreen` displayed stale hardcoded version `v0.1.0`** — updated to `v0.7.1` (`lib/ui/radar/radar_screen.dart`)
- **`RadarPainter.shouldRepaint` missed blip content changes** — a blip gaining a threat flag or changing RSSI would not trigger a repaint if blip count was unchanged (`lib/ui/radar/radar_painter.dart`)
- **`SignalListScreen._filtered` cache never invalidated on new signals** — cache key only tracked sort order; new signal batches from parent served stale sorted list (`lib/ui/screens/signal_list_screen.dart`)
- **CSV export had duplicate RSSI column** — header `RSSI,dBm` both mapped to `o.rssi`; merged to `RSSI (dBm)` with one value column (`lib/ui/screens/timeline_screen.dart`)
- **`OuiLookup.init()` concurrent-call race** — second concurrent caller saw `_loading = true`, returned early, and called `resolve()` on a null table; replaced `bool _loading` flag with `Completer<void>` so all callers await the same load (`lib/core/db/oui_lookup.dart`)
- **`PermissionGate` SKIP button was a no-op** — `setState(() {})` cannot advance past the gate because `_requiredGranted` is still false; added `_skipped` flag and wired button correctly (`lib/ui/screens/permission_gate.dart`)

### Fixed

- **`classifyDeviceMovement` wrong distance metric** (`lib/core/db/lb_database.dart`)
  The bounding-box diagonal was computed as `latM² + lonM²` (units: metres²) instead of
  `sqrt(latM² + lonM²)` (metres). Every device appeared static unless it moved >700 m;
  mobile classification never triggered below ~22 km. Fixed to use `math.sqrt(...)`.
  Also replaced the hardcoded `0.7` longitude scaling factor with the correct
  `cos(midLat × π/180)` so results are accurate at all latitudes, not just ±45°.

- **`BtClassicScanner` emitted `bluetoothctl discoverable on`** (`lib/modules/bt_classic/bt_classic_scanner.dart`)
  Making the device discoverable is active RF emission — a direct OPSEC violation for a
  passive SIGINT tool. `bluetoothctl devices` does not require discoverable mode; it lists
  the adapter's cached device table. Line removed.

- **`cell_id_lookup.dart` missing `debugPrint` import** (`lib/core/services/cell_id_lookup.dart`)
  Five `debugPrint()` calls existed with no `import 'package:flutter/foundation.dart'`.
  This caused a compile-time `undefined name 'debugPrint'` error.

- **`AggregateMapScreen` GPS timer leaked on dispose** (`lib/ui/screens/aggregate_map_screen.dart`)
  `_startGpsUpdates()` called `Timer.periodic` but discarded the return value.
  `_AggregateMapScreenState` had no `dispose()` override. Added `_gpsTimer` field,
  stored the timer handle, and added `dispose()` cancelling both the timer and
  `_mapController`.

- **`LBDb.name` mismatch with README / adb pull docs** (`lib/core/constants/lb_constants.dart`)
  Constant was `'littlebrother.db'`; all README, `adb pull`, and `sqlite3` debugging
  instructions reference `lbscan.db`. Constant corrected to `'lbscan.db'`.

- **Missing `secrets.dart`** (`lib/core/secrets.dart` — created)
  Four files imported `package:littlebrother/core/secrets.dart` but it was absent from
  the repository, making the project uncompilable. Created a compilable stub with
  `Secrets.openCellIdApiKey`, `Secrets.hasOpenCellIdKey`, `Secrets.effectiveApiKey`,
  and `Secrets.privacyMode`, matching all usages across the codebase.

- **Signal batches silently dropped under scanner contention** (`lib/core/scan_coordinator.dart`)
  The `_processingSignals` boolean guard discarded entire scan batches when the previous
  batch was still being processed (DB writes + analyzer). Replaced with a `ListQueue`-based
  drain loop: batches are enqueued and processed in FIFO order. No observation is ever
  silently dropped. Also clears the queue on `stopScan()` so stale batches cannot bleed
  into the next session. Added `dart:collection` import.

### Added
- **CellCacheService**: New service for bulk loading cells from OpenCellID for visited regions (county/city level)
- **Signal trail visualization**: SignalPoint class and PolylineLayer for tracking mobile devices
- **Cached cells table**: Database schema v6 adds `cached_cells` and `visited_regions` tables
- **Malformed cell key filtering**: Android scanner now validates cell keys and filters invalid MCC/MNC/TAC/CID values

### Fixed
- **Grid overlay crash**: Fixed polygon rendering crashes on map pan/zoom by disabling auto-precision
- **OpenCellID API**: Fixed incorrect endpoint (`/data` → `/cell/get`) and parameter (`cell` → `cellid`), added radio parameter
- **Invalid cell keys**: Phone returning `-2147483647` (INT32_MIN) for TAC/CID now filtered at scanner level

### Changed
- **Version**: Bumped to 0.7.0
- **README**: Added Known Issues section documenting cell tower mapping limitations

---

## [0.5.1] - 2026-03-31

### Changed
- **Map tiles**: Switched to OpenStreetMap (free, no API key required)
- **Removed test layer**: Complete removal of TestThreat and MockCommunityData from aggregate map
- **Model cleanup**: Removed MapLayer.test enum value, simplified layer selection

### Fixed
- **Database type casts**: Fixed type casting issues in CellTower, WifiDevice, and BleDevice fromMap methods when handling nullable metadata JSON fields

### Removed
- Debug-only test data layer that was only visible in debug mode
- All TestThreat-related UI components (markers, detail sheets, legend items)

---

## [0.5.0] - 2026-03-29

### Added
- Initial release with Wi-Fi, BLE, and Cellular scanning
- Aggregate map with grid, tower, WiFi, BLE, and test layers
- GPS integration for position tracking
- Database persistence for scan observations

### Known Issues
- DNS resolution issues on some Android devices (workaround: use different tile provider)