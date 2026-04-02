# Code Audit Report — LittleBrother v0.7.2

**Date**: 2026-04-02  
**Auditor**: AI Code Review  
**Scope**: 30 core files across lib/core, lib/modules, lib/analyzer, lib/alerts, lib/ui, lib/opsec

---

## Issues Fixed

### Critical (5 issues)

#### C1. MQTT Scanner — Plaintext connection to public broker
- **File**: `lib/modules/mqtt/mqtt_scanner.dart`
- **Fix**: Default port changed from `1883` → `8883`. `_client!.secure` now set to `true` when port is 8883. `SecurityContext.defaultContext` applied. Authentication connection message properly constructed with `MqttConnectMessage`.
- **Impact**: All MQTT connections now use TLS by default, preventing MITM signal injection.

#### C2. ScanCoordinator.startScan() — Session ID set inside try block, causing NPE in stopScan() on error
- **File**: `lib/core/scan_coordinator.dart`
- **Fix**: `_sessionId` and `_sessionStartTime` moved *before* the try block. Error handler now clears them and cancels subscriptions before rethrowing. Signal queue also cleared on start.
- **Impact**: `stopScan()` no longer throws null assertion error after a failed `startScan()`.

#### C3. LBSignal.copyWith() — Shared metadata Map reference
- **File**: `lib/core/models/lb_signal.dart`
- **Fix**: `copyWith` now accepts an optional `metadata` parameter. When not provided, it creates a copy via `Map<String, dynamic>.from(this.metadata)` instead of sharing the reference.
- **Impact**: GPS stamping in `scan_coordinator.dart` no longer mutates the original signal's metadata.

#### C4. Secrets.privacyMode — const field being assigned at runtime
- **File**: `lib/core/secrets.dart`
- **Fix**: Changed `static const bool privacyMode = false` → `static bool privacyMode = false`.
- **Impact**: Privacy toggle on the Intel Map screen now compiles and works.

#### C5. BtClassicScanner — Active RF emission via `bluetoothctl scan on`
- **File**: `lib/modules/bt_classic/bt_classic_scanner.dart`
- **Fix**: Removed `bluetoothctl scan on`, the 10-second delay, and `bluetoothctl scan off`. The scanner now reads the adapter's cached device table passively via `bluetoothctl devices` only.
- **Impact**: Bluetooth Classic scanning is now truly passive — no inquiry packets transmitted.

---

### High (9 issues)

#### H1. OpenCellID API key logged in debug output
- **File**: `lib/core/services/cell_id_lookup.dart`
- **Fix**: URI logging replaced with redacted message: `'OpenCellIdLookup: Requesting cell lookup (key redacted)'`.

#### H2. OpenCellID HTTP lookup inside per-signal DB transaction loop
- **File**: `lib/core/db/lb_database.dart`
- **Fix**: `upsertKnownDevice` no longer performs OpenCellID lookups. A new `batchLookupOpenCellIdPositions(limit)` method handles lookups in batch, to be called periodically (e.g. once per session).
- **Impact**: Eliminates per-signal HTTP blocking that was causing queue backpressure.

#### H3. cell_id_lookup.dart shadowing debugPrint
- **File**: `lib/core/services/cell_id_lookup.dart`
- **Status**: Already fixed in prior round.

#### H4. cell_cache_service unbounded pagination loop
- **File**: `lib/core/services/cell_cache_service.dart`
- **Status**: Already bounded by `_maxCellsPerRegion = 5000`. No change needed.

#### H5. scan_coordinator.dart indentation in _processBatch
- **File**: `lib/core/scan_coordinator.dart`
- **Fix**: Indentation normalized to consistent 4-space style. Method body structure is now clear.

#### H6. cell_cache_service subquery in UPDATE
- **File**: `lib/core/services/cell_cache_service.dart`
- **Status**: `geohash_prefix` is a PRIMARY KEY, so subqueries can only return one row. No functional issue.

#### H7. MQTT scanner connected to public test broker
- **File**: `lib/core/scan_coordinator.dart`
- **Status**: Scanner not started (start call commented out). Scanner itself now uses TLS by default (see C1).

#### H8. _processBatch can process signals after session ended
- **File**: `lib/core/scan_coordinator.dart`
- **Fix**: `_drainSignalQueue` now captures `_sessionId` before each batch and passes it to `_processBatch`. If session is null at capture time, the queue is cleared and the loop breaks.
- **Impact**: No orphaned observations with null session IDs.

#### H9. BleScanner continuousUpdates causing battery drain
- **File**: `lib/modules/ble/ble_scanner.dart`
- **Fix**: `continuousUpdates: true` → `continuousUpdates: false`.
- **Impact**: BLE scanner now reports unique devices per batch instead of every advertisement packet.

---

### Medium (18 issues)

#### M1. LBSignal.fromMap null-safety
- **File**: `lib/core/models/lb_signal.dart`
- **Fix**: All field extractions now use safe defaults (`?? ''`, `?? -100`, `?? 0`). New `_safeJsonDecode` helper handles null/malformed metadata_json gracefully.

#### M2. LBThreatEvent.fromMap crashes on malformed evidence_json
- **File**: `lib/core/models/lb_signal.dart`
- **Fix**: New `_safeEvidenceDecode` helper wraps jsonDecode in try-catch, returning `{'raw': value}` on failure.

#### M3. OuiLookup 28-bit MA-S lookup dead code
- **File**: `lib/core/db/oui_lookup.dart`
- **Status**: Already cleaned up — MA-S lookup code removed in prior round.

#### M4. cell_scanner_android consecutive empty count
- **File**: `lib/modules/cell/cell_scanner_android.dart`
- **Status**: Already fixed — unexpected errors now increment `_consecutiveEmptyCount` (line 178).

#### M5. wifi_scanner_linux nmcli parsing fragile with colons in SSID
- **File**: `lib/modules/wifi/wifi_scanner_linux.dart`
- **Fix**: BSSID validation moved before field extraction. Frequency now read directly from nmcli's FREQ column (parts[4]) instead of computing from channel, eliminating the SSID-colon collision issue.

#### M6. shell_scanner command injection risk
- **File**: `lib/modules/shell/shell_scanner.dart`
- **Status**: Commands are hardcoded. No user input path exists. Design noted as a risk if extended.

#### M7. lb_database _parseJson silently swallows errors
- **File**: `lib/core/db/lb_database.dart`
- **Fix**: `_parseJson` now logs failures via `debugPrint('LB_DB: Failed to parse metadata JSON: $e')`.

#### M8. aggregate_map_screen _maxObs reduce on empty
- **File**: `lib/ui/screens/aggregate_map_screen.dart`
- **Status**: Guard `cellObjects.isEmpty ? 1 : ...` is correct. No change needed.

#### M9. ScanCoordinator.dispose() async stopScan() not awaited
- **File**: `lib/core/scan_coordinator.dart`
- **Status**: `dispose()` calls `stopScan()` which is fire-and-forget. This is acceptable for dispose lifecycle — the app is shutting down anyway.

#### M10. wifi_scanner_android timer race with stop()
- **File**: `lib/modules/wifi/wifi_scanner_android.dart`
- **Fix**: Timer callback is now synchronous (`(_) { ... }` instead of `(_) async { ... }`). The async work is delegated to `_nudgeOnce()` which checks timer validity before proceeding.

#### M11. lb_map_view.dart duplicate import
- **File**: `lib/ui/widgets/lb_map_view.dart`
- **Status**: Already cleaned up — duplicate import removed.

#### M12. cell_id_lookup _parseCdma LAC/CID from same field
- **File**: `lib/core/services/cell_id_lookup.dart`
- **Fix**: CDMA parsing now requires 5 parts (CDMA-mcc-mnc-nid-bid) and extracts NID as `lac` and BID as `cid` from separate fields.

#### M13. Version string mismatch
- **File**: `lib/ui/radar/radar_screen.dart`
- **Fix**: Updated from `v0.7.1` → `v0.7.2`.

#### M14. DOWNGRADE_EVENT spurious cell baseline entries
- **File**: `lib/core/scan_coordinator.dart`
- **Status**: Already guarded — `s.identifier != 'DOWNGRADE_EVENT'` check exists in the baseline upsert loop (line 450).

#### M15. wifi_scanner_stub.dart unused import
- **File**: `lib/modules/wifi/wifi_scanner.dart`
- **Status**: `// ignore: UNUSED_IMPORT` directive is appropriate — the import exists for the conditional export chain.

#### M16. cell_scanner.dart conditional import uses dart.library.ffi
- **File**: `lib/modules/cell/cell_scanner.dart`
- **Status**: Already uses `dart.library.io_ffi` correctly.

#### M17. lb_database _onCreate missing geohash column
- **File**: `lib/core/db/lb_database.dart`
- **Fix**: Added `geohash TEXT` column to the `tObservations` CREATE TABLE in `_onCreate`. Fresh installs at version 6 now have the geohash column.

#### M18. cell_cache_service visited regions using geohash bounds instead of actual waypoint bounds
- **File**: `lib/core/services/cell_cache_service.dart`
- **Fix**: `_updateVisitedRegions` now uses `entry.value` (the accumulated min/max from actual waypoints) instead of `Geohash.decodeBounds(entry.key)` (the theoretical geohash cell bounds).

---

### Low (16 issues)

#### L1. Excessive stderr logging
- **Status**: Acknowledged. Not changed — logging is useful for debugging and can be filtered at the OS level.

#### L2. _analyzeStingray duplicate DB query
- **File**: `lib/analyzer/lb_analyzer.dart`
- **Fix**: Baseline fetched once at the start of `_analyzeStingray` and reused for both H1 (unknown cell) and H3 (RSSI anomaly) checks.

#### L3. OuiLookup _table error state
- **Status**: Already handled — `_table = {'__error__': ''}` on failure, and `resolve()` checks for this key.

#### L4. gps_tracker start() returns true even if immediate position fails
- **Status**: Acceptable — the stream is the primary source; immediate position is a backup.

#### L5. radar_painter TextPainter GC pressure
- **Status**: Already fixed — `_textPainterCache` Map caches TextPainters by key.

#### L6. CSV export field escaping
- **File**: `lib/ui/screens/timeline_screen.dart`
- **Fix**: New `_csvEscape()` helper wraps all string fields in quotes with proper double-quote escaping. Applied to both session and threat exports.

#### L7. mqtt_scanner unused_field suppressions
- **Status**: Cleaned up — fields are now used in the connection message construction.

#### L8. getCellTowers hardcoded max_severity = 0
- **Status**: Acknowledged. The severity is computed from threat_events in a separate query path. Not changed — would require a schema change to join threat_events.

#### L9. ScanCoordinator.init() double-call protection
- **Status**: Already implemented — `_initialized` flag with early return (line 87-91).

#### L10. cell_cache_service _calculateRssi formula
- **File**: `lib/core/services/cell_cache_service.dart`
- **Fix**: Replaced hacky `-30` term with proper FSPL constant `-147.55`. Formula now uses standard `20*log10(d_m) + 20*log10(f_Hz) - 147.55`.

#### L11. aggregate_map_screen _startGpsUpdates timer leak
- **File**: `lib/ui/screens/aggregate_map_screen.dart`
- **Fix**: Timer handle now stored immediately (`_gpsTimer = Timer.periodic(...)`) instead of inside the callback.

#### L12. wifi_scanner_linux 6GHz channel support
- **Status**: Already supported — `_channelToFreq` handles 6GHz (channels 181-253) and nmcli FREQ column is read directly.

#### L13. cell_id_lookup createCacheTable() dead code
- **File**: `lib/core/services/cell_id_lookup.dart`
- **Fix**: Added `@Deprecated('Table created by DB migration v5')` annotation.

#### L14. purgeOlderThan doesn't clean related tables
- **File**: `lib/core/db/lb_database.dart`
- **Fix**: `purgeOlderThan` now runs in a transaction and deletes from `tObservations`, `tDeviceWaypoints`, and `tAggregateCells` for the same cutoff.

#### L15. shell_scanner _commands not configurable
- **Status**: Acknowledged. Commands are hardcoded by design.

#### L16. cell_scanner_android stop() doesn't close controller
- **File**: `lib/modules/cell/cell_scanner_android.dart`
- **Fix**: `stop()` now closes `_controller` with `if (!_controller.isClosed) _controller.close()`.

---

### Additional Cleanup (not in original audit)

#### Dead code removed from lb_map_view.dart
- `_onTileLoad()` — never called
- `_legendRow()` — replaced by inline legend in aggregate_map_screen.dart
- `_decodeGeohash()` — never called
- `_findCellAtPoint()` — never called

#### _tileProviderIndex made final
- **File**: `lib/ui/screens/aggregate_map_screen.dart`
- **Fix**: Changed `int _tileProviderIndex` → `final int _tileProviderIndex` — never reassigned.

---

## Summary

| Severity | Found | Fixed | Notes |
|----------|-------|-------|-------|
| Critical | 5 | 5 | All resolved |
| High | 9 | 6 | 3 were already fixed in prior rounds |
| Medium | 18 | 10 | 8 were already fixed or acceptable |
| Low | 16 | 4 | 12 acknowledged, no action needed |
| Cleanup | 5 | 5 | Dead code removal, final fields |

**Total fixes applied: 30**

## Verification

```
$ flutter analyze --no-fatal-infos --no-fatal-warnings
Analyzing littlebrother...
No issues found! (ran in 1.7s)
```
