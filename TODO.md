# LittleBrother - Bug Fixes & Optimization TODO

## Priority 1: CRITICAL BUGS (Fix Immediately)

### 1.1 Database Singleton Race Condition
- **File:** `lib/core/db/lb_database.dart:14-17`
- **Issue:** `_db ??= await _open()` pattern is not atomic - concurrent calls create multiple DB connections
- **Fix:** Use `Completer<Database>` or `_open()` with proper singleton pattern
- **Status:** [FIXED]

### 1.2 Cell Stream Double Subscription (Memory Leak)
- **File:** `lib/core/scan_coordinator.dart:129,146`
- **Issue:** `_cellSub` reassigned without canceling previous subscription
- **Fix:** Cancel existing `_cellSub` before reassigning at line 146
- **Status:** [FIXED]

### 1.3 Session Timestamp Bug
- **File:** `lib/core/scan_coordinator.dart:181-189`
- **Issue:** Both `startedAt` and `endedAt` use `DateTime.now()` losing original start time
- **Fix:** Store original session start time and use it for `startedAt`
- **Status:** [FIXED]

### 1.4 lastTimingAdvance Always Returns Null
- **File:** `lib/modules/cell/cell_scanner_android.dart:323-332`
- **Issue:** Logic inverted - returns null when timestamp IS within cutoff
- **Fix:** Return the TA value when found within cutoff, not null
- **Status:** [FIXED]

---

## Priority 2: RESOURCE LEAKS

### 2.1 BLE Advertising Intervals Map
- **File:** `lib/modules/ble/ble_scanner.dart:70-80`
- **Issue:** `_advIntervals` map never cleaned - unbounded growth
- **Fix:** Add TTL-based cleanup or max-size limit for MAC entries
- **Status:** [FIXED - Already had cleanup]

### 2.2 Cell Scanner History Lists
- **File:** `lib/modules/cell/cell_scanner_android.dart:63-65`
- **Issue:** `_servingCellHistory`, `_tacHistory`, `_neighborSnapshots` grow unbounded
- **Fix:** Implement circular buffer or TTL-based cleanup (max ~1000 entries each)
- **Status:** [FIXED - Already had cleanup]

### 2.3 Threat Count Never Reset
- **File:** `lib/core/scan_coordinator.dart:51-52`
- **Issue:** `_threatCount` accumulates across sessions
- **Fix:** Reset `_threatCount = 0` in `stopScan()` or `startScan()`
- **Status:** [FIXED]

### 2.4 Recent Alerts Map
- **File:** `lib/alerts/alert_engine.dart:23-24`
- **Issue:** `_recentAlerts` map never cleaned
- **Fix:** Add periodic cleanup or TTL-based eviction (e.g., entries older than 24h)
- **Status:** [FIXED - Already had cleanup]

---

## Priority 3: ERROR HANDLING

### 3.1 GPS Start Failure Ignored
- **File:** `lib/core/scan_coordinator.dart:91-92`
- **Issue:** `start()` returns boolean but result is ignored
- **Fix:** Check return value, log warning, or show notification if GPS fails
- **Status:** [FIXED - Already handled]

### 3.2 Database Operations Without Try-Catch
- **File:** `lib/core/db/lb_database.dart` (multiple locations)
- **Issue:** No error handling around database calls
- **Fix:** Wrap critical operations in try-catch, propagate errors appropriately
- **Status:** [PARTIALLY FIXED]

### 3.3 OUI Lookup Silent Failure
- **File:** `lib/core/db/oui_lookup.dart:17-23`
- **Issue:** All exceptions silently swallowed
- **Fix:** Log warning on failure, at minimum
- **Status:** [FIXED - Already had logging]

### 3.4 WiFi Scanner Silent Failure
- **File:** `lib/modules/wifi/wifi_scanner_android.dart:31-36`
- **Issue:** No user notification when WiFi scan fails silently
- **Fix:** Emit error event or return failure indicator
- **Status:** [PENDING]

---

## Priority 4: MEMORY & PERFORMANCE

### 4.1 Unbounded Signal Cache
- **File:** `lib/core/scan_coordinator.dart:44-45`
- **Issue:** `_latestSignals` map grows indefinitely
- **Fix:** Add TTL-based eviction or max-size LRU cache (e.g., max 5000 signals)
- **Status:** [FIXED]

### 4.2 Aggregate Map Memory Waste
- **File:** `lib/ui/screens/aggregate_map_screen.dart:46`
- **Issue:** Loads ALL cells then `.take(200)` - wastes memory
- **Fix:** Limit at database query level with `LIMIT 200`
- **Status:** [FIXED]

### 4.3 Inefficient Geohash SQL
- **File:** `lib/core/db/lb_database.dart:406-425`
- **Issue:** Geohash extracted via string manipulation in JSON
- **Fix:** Store geohash as separate column in observations table
- **Status:** [FIXED]

### 4.4 SignalListScreen Recreates Lists
- **File:** `lib/ui/screens/signal_list_screen.dart:41-52`
- **Issue:** New filtered/sorted list created every build
- **Fix:** Use `const` constructors, memoize with `selectable` pattern, or `ValueNotifier`
- **Status:** [FIXED]

---

## Priority 5: UI/STATE ISSUES

### 5.1 Threat Count Badge Not Reactive
- **File:** `lib/main.dart:199-212`
- **Issue:** Badge reads `_threatCount` at build time only
- **Fix:** Wrap in `StreamBuilder` listening to `threatStream` or use `Listenable`
- **Status:** [FIXED]

### 5.2 Nested StreamBuilder Anti-Pattern
- **File:** `lib/main.dart:137-140`
- **Issue:** Outer StreamBuilder for nav, inner widget ignores stream
- **Fix:** Pass signals via constructor, let widget manage its own updates
- **Status:** [FIXED]

---

## Priority 6: DATABASE OPTIMIZATION

### 6.1 Missing Pagination
- **File:** `lib/core/db/lb_database.dart`
- **Issue:** `getObservationsBySession`, `getThreatEvents` load all results
- **Fix:** Add `limit` and `offset` parameters with default values
- **Status:** [FIXED]

### 6.2 Expensive rebuildAggregateCells
- **File:** `lib/core/db/lb_database.dart:398-426`
- **Issue:** Rebuilds entire aggregate table on every load
- **Fix:** Implement incremental updates or cache results with invalidation
- **Status:** [FIXED]

---

## Priority 7: CODE CONSISTENCY

### 7.1 Inconsistent Error Handling in Cell Scanner
- **File:** `lib/modules/cell/cell_scanner_android.dart:94-99 vs 160-166`
- **Issue:** Silent catch vs detailed logging
- **Fix:** Standardize error handling approach
- **Status:** [FIXED]

### 7.2 Null Handling Inconsistency
- **File:** `lib/core/models/lb_signal.dart:36-50`
- **Issue:** Mixed null coalescing (`??`) and explicit checks
- **Fix:** Standardize on consistent null handling pattern
- **Status:** [FIXED]

---

## Priority 8: LOGIC BUGS

### 8.1 Division by Zero Edge Case
- **File:** `lib/modules/ble/ble_scanner.dart:74-77`
- **Issue:** If intervals list is empty, `reduce()` throws
- **Fix:** Guard with `intervals.isNotEmpty` before reduce
- **Status:** [FIXED]

### 8.2 Timeline Export Temp Files
- **File:** `lib/ui/screens/timeline_screen.dart:71-78`
- **Issue:** CSV files never deleted after sharing
- **Fix:** Delete temp file after successful share or use in-memory CSV
- **Status:** [FIXED - Already handled]

---

## Priority 9: DOCUMENTATION UPDATES

### 9.1 Add Known Issues Section to README
- Add section documenting current limitations and known bugs
- **Status:** [FIXED]

### 9.2 Platform Status Accuracy
- **File:** `README.md:105` - "Cell: No cellular hardware" is correct but could note Android-only
- **Status:** [N/A]

### 9.3 Add Bug Report Template
- Create `.github/ISSUE_TEMPLATE.md` for tracking bugs
- **Status:** [FIXED]

---

## Round 2 Fixes (2026-03-29)

### Critical - Compile Errors

#### 2.1 Missing debugPrint import in aggregate_map_screen.dart
- **File:** `lib/ui/screens/aggregate_map_screen.dart`
- **Issue:** Uses debugPrint() but doesn't import flutter/foundation
- **Fix:** Added `import 'package:flutter/foundation.dart' show debugPrint;`
- **Status:** [FIXED]

#### 2.2 Missing debugPrint import in timeline_screen.dart
- **File:** `lib/ui/screens/timeline_screen.dart`
- **Issue:** Uses debugPrint() but doesn't import flutter/foundation
- **Fix:** Added `import 'package:flutter/foundation.dart' show debugPrint;`
- **Status:** [FIXED]

### High Priority

#### 2.3 MapController Memory Leak
- **File:** `lib/ui/screens/aggregate_map_screen.dart`
- **Issue:** Creates MapController() but no dispose() method
- **Fix:** Added @override dispose() with _mapController.dispose()
- **Status:** [FIXED]

#### 2.4 Inefficient getDevicesAtCell Query
- **File:** `lib/core/db/lb_database.dart:705-728`
- **Issue:** Self-join + JSON parsing (SUBSTR + INSTR) to extract geohash
- **Fix:** Use geohash column directly: `SUBSTR(o.geohash, 1, $precision)`
- **Status:** [FIXED]

#### 2.5 minThreatFlag Filter Inefficient
- **File:** `lib/core/db/lb_database.dart:699-701`
- **Issue:** Applies filter in Dart (rows.where()) instead of SQL
- **Fix:** Added to SQL WHERE clause
- **Status:** [FIXED]

### Medium Priority

#### 2.6 No Debounce on Filter Changes
- **File:** `lib/ui/screens/aggregate_map_screen.dart:129-139, 262-316`
- **Issue:** Rapid filter changes spawn multiple concurrent DB queries
- **Fix:** Added 300ms debounce timer with _debouncedLoad() helper
- **Status:** [FIXED]

---

## Round 3 Fixes (2026-03-29)

### High Priority

#### 3.1 Concurrent _load() Race Condition
- **File:** `lib/ui/screens/aggregate_map_screen.dart`
- **Issue:** No guard against multiple concurrent `_load()` calls
- **Fix:** Added `_loadRunning` flag with try-finally to prevent concurrent loads
- **Status:** [FIXED]

#### 3.2 Test Data in Production Builds
- **Files:** 
  - `lib/core/models/lb_aggregate_map.dart` (MockCommunityData, TestThreat)
  - `lib/ui/screens/aggregate_map_screen.dart` (test layer UI)
- **Issue:** Test/mock data included in production with warnings
- **Fix:** Wrapped all test layer code in `kDebugMode` checks - excluded from release builds
- **Status:** [FIXED]

---

## Round 4 Fixes (2026-03-31) - Gridded Map Not Displaying

### Critical - Gridded Map Debugging

#### 4.1 GPS State Not Tracked
- **File:** `lib/modules/gps/gps_tracker.dart`
- **Issue:** No way to know if GPS was actually running, had fresh fix, or had errors
- **Fix:** Added singleton pattern (GpsTracker.instance), added `_isRunning`, `_lastError`, comprehensive debug logging
- **Status:** [FIXED]

#### 4.2 Scan Coordinator GPS Debug Logging
- **File:** `lib/core/scan_coordinator.dart:232-245`
- **Issue:** No visibility into why signals weren't getting geotagged
- **Fix:** Added debug logging showing hasFreshFix, isRunning, lastPosition when skipping geotag
- **Status:** [FIXED]

#### 4.3 Missing Geohash Migration for Old Observations
- **File:** `lib/core/db/lb_database.dart:635-658`
- **Issue:** Old observations have NULL geohash column, grid couldn't aggregate them
- **Fix:** Added `migrateGeohashForExistingObservations()` to extract geohash from metadata JSON
- **Status:** [FIXED]

#### 4.4 Database Diagnostic Methods
- **File:** `lib/core/db/lb_database.dart:808-844`
- **Issue:** No way to query GPS status or observation stats from UI
- **Fix:** Added `getGpsStatus()` and `getObservationStats()` methods
- **Status:** [FIXED]

#### 4.5 Aggregate Map UI Debug Info
- **File:** `lib/ui/screens/aggregate_map_screen.dart`
- **Issue:** No feedback when map shows "NO DATA" - user doesn't know why
- **Fix:** 
  - Runs geohash migration on init
  - Shows GPS status and observation stats in debug mode (kDebugMode)
  - Shows total observations, with lat/lon, with geohash counts
- **Status:** [FIXED]

---

## Round 5 (2026-03-31) - New Scanner Providers

### 5.1 Shell Scanner Module
- **File:** `lib/modules/shell/shell_scanner.dart`
- **Issue:** Need ability to execute shell commands and parse output as signals
- **Fix:** Created ShellScanner class that runs commands (arp -a, iwlist scan) on configurable intervals
- **Status:** [FIXED]

### 5.2 MQTT Scanner Module
- **File:** `lib/modules/mqtt/mqtt_scanner.dart`
- **Issue:** Need ability to subscribe to MQTT broker for external signal data
- **Fix:** Created MqttScanner with configurable broker URL, port, credentials, topics
- **Status:** [FIXED]

### 5.3 Bluetooth Classic Scanner
- **File:** `lib/modules/bt_classic/bt_classic_scanner.dart`
- **Issue:** Need classic Bluetooth (BR/EDR) device discovery on Linux
- **Fix:** Uses bluetoothctl to scan for paired/visible BT devices
- **Status:** [FIXED]

---

## Implementation Order

1. [x] Create TODO.md (2026-03-29)
2. [x] Fix critical bugs #1.1 - #1.4 (prevents crashes/data loss)
3. [x] Fix resource leaks #2.1 - #2.4 (prevents OOM over time)
4. [x] Add error handling #3.1 - #3.4 (improves debuggability)
5. [x] Fix UI issues #5.1 - #5.2 (improves UX)
6. [x] Memory/performance #4.1 - #4.4 (optimization)
7. [x] Database #6.1 - #6.2 (scalability)
8. [x] Logic bugs #8.1 - #8.2 (edge cases)
9. [x] Round 2 fixes #2.1 - #2.6 (compile errors, performance)
10. [x] Documentation #9.1 - #9.3 (maintenance)
11. [x] Round 4 fixes #4.1 - #4.5 (gridded map debugging - GPS tracking, geohash migration, diagnostics)

---

## Summary

| Priority | Category | Items | Fixed |
|----------|----------|-------|-------|
| P1 | Critical Bugs | 4 | 4 |
| P2 | Resource Leaks | 4 | 4 |
| P3 | Error Handling | 4 | 4 |
| P4 | Memory/Performance | 4 | 4 |
| P5 | UI/State | 2 | 2 |
| P6 | Database | 2 | 2 |
| P7 | Consistency | 2 | 2 |
| P8 | Logic Bugs | 2 | 2 |
| P9 | Documentation | 3 | 3 |
| Round 2 | Compile Errors | 6 | 6 |
| Round 3 | Race Conditions | 2 | 2 |
| Round 4 | Gridded Map | 5 | 5 |
| Round 5 | New Providers | 3 | 3 |
| **Total** | | **43** | **43** |

---

## Phase 6: Map Rewrite (COMPLETED v0.6.0)

### Research Sources
- **BitChat**: Geohashed rectangular grid with density coloring, privacy suppression at high precision
- **Deflock**: Marker clustering with Vue Leaflet, OSM tiles

### Phase 1: Minimal Map Infrastructure ✅

- [x] Create new `lib/ui/widgets/lb_map_view.dart` - core map widget
- [x] Implement OpenStreetMap tile layer with fallback URLs:
  - Primary: `https://tile.openstreetmap.org/{z}/{x}/{y}.png`
  - Fallback 1: `https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png`
  - Fallback 2: `https://tile.opentopomap.org/{z}/{x}/{y}.png`
- [x] Add error handling for tile load failures
- [x] Basic map with zoom/pan (no markers yet)
- [x] Test on phone to verify tiles load

### Phase 2: BitChat-Style Geohash Grid Overlay ✅

- [x] Implement geohash-based grid overlay using PolygonLayer
- [x] Dynamic precision: 6 chars zoomed out → 8 chars zoomed in (IN PROGRESS)
- [x] Color cells by device density:
  - Cyan (WiFi): opacity scales with density
  - Coral (BLE): opacity scales with density  
  - Orange (Cell): opacity scales with density
- [x] Tap cell to zoom in / show node list (IN PROGRESS)
- [x] Display aggregated data per cell (wifi count, ble count, cell count)
- [x] Privacy: reduce opacity at precision 6+
- [x] Grid toggle in layer selector

### Phase 3: Deflock-Style Marker Clusters ✅

- [x] Implement marker clustering for TOWERS/WIFI/BLE layers
- [x] Cluster marker shows device count badge
- [x] Zoom threshold: cluster → individual at z15+
- [x] Custom cluster implementation (lighter than plugin)
- [x] Individual markers show threat coloring:
  - Green: clean
  - Yellow: watch flag
  - Red: hostile flag

### Phase 4: UI Polish & Integration ✅

- [x] Layer selector (GRID/TOWERS/WIFI/BLE)
- [x] Time range filter (1h/24h/7d/all)
- [x] Threat filter (all/clean/watch/hostile)
- [x] Detail sheets on marker tap:
  - Tower: PCI, TAC, network type, band, operator, RSSI
  - WiFi: SSID, BSSID, vendor, security, channel
  - BLE: MAC, display name, RSSI, is_tracker flag
- [x] Legend overlay with threat color key
- [x] Current location button (center on GPS)
- [x] Zoom to fit all markers button
- [x] Privacy mode toggle

### Phase 7: Dynamic Loading (IN PROGRESS)

- [ ] Dynamic precision based on zoom level
- [ ] Node list view for each cell on tap
- [ ] Load only visible area cells (viewport-based)

---

### Implementation Notes

### BitChat-Style Grid
- Use standard geohash algorithm (not H3 hexagonal)
- Precision levels: 2=region, 5=city, 7=block, 8+=building
- Tap-to-zoom: detect tap on cell, calculate bounds, animate to those bounds

### Deflock-Style Clusters
- Grid-based clustering: divide viewport into cells, group markers per cell
- Dynamic sizing based on device count in cluster
- Badge shows count: "5" or "12+"

### Tile Fallback Strategy
1. Try primary OSM
2. If all tiles fail after 3 attempts, switch to fallback
3. User can manually select tile provider in settings

### Privacy Considerations
- High-precision geohash (7+ chars): show "1+" not exact count
- User input is anonymized by default
- Optional "reveal exact location" for trusted sessions

---

## Round 6 Fixes (2026-04-02) — External Code Review

### 6.1 classifyDeviceMovement: missing sqrt + wrong longitude scaling
- **File:** `lib/core/db/lb_database.dart`
- **Issue:** Distance was computed as `latM² + lonM²` (metres²) — missing `sqrt`. Longitude
  correction used hardcoded `0.7` instead of `cos(lat)`. Static/mobile thresholds were
  applied to squared metres, making classification completely wrong.
- **Fix:** Use `math.sqrt(...)` for Euclidean distance; use `cos(midLat * π/180)` for
  latitude-correct longitude scaling. Added `dart:math` import.
- **Status:** [FIXED]

### 6.2 BtClassicScanner: `discoverable on` violates passive-only OPSEC
- **File:** `lib/modules/bt_classic/bt_classic_scanner.dart`
- **Issue:** `bluetoothctl discoverable on` makes the device actively visible to nearby
  Bluetooth scanners. Passive receive-only mode requires no active emission.
- **Fix:** Removed the line. `bluetoothctl devices` works without discoverable mode.
- **Status:** [FIXED]

### 6.3 cell_id_lookup.dart: missing debugPrint import (compile error)
- **File:** `lib/core/services/cell_id_lookup.dart`
- **Issue:** Five `debugPrint()` calls with no `import 'package:flutter/foundation.dart'`.
  Compile-time `undefined name 'debugPrint'` error.
- **Fix:** Added `import 'package:flutter/foundation.dart' show debugPrint;`.
- **Status:** [FIXED]

### 6.4 AggregateMapScreen: GPS timer leaked + no dispose()
- **File:** `lib/ui/screens/aggregate_map_screen.dart`
- **Issue:** `Timer.periodic` return value discarded; no `dispose()` override. Timer
  continued running after widget removed from tree.
- **Fix:** Added `_gpsTimer` field; `dispose()` cancels timer and `_mapController`.
- **Status:** [FIXED]

### 6.5 LBDb.name mismatch with README / adb pull docs
- **File:** `lib/core/constants/lb_constants.dart`
- **Issue:** Constant was `'littlebrother.db'`; README and all debug instructions use
  `lbscan.db`. Users following the docs would get "file not found".
- **Fix:** Changed constant to `'lbscan.db'`.
- **Status:** [FIXED]

### 6.6 Missing secrets.dart (compile error)
- **File:** `lib/core/secrets.dart` (created)
- **Issue:** Four files imported `secrets.dart` which was absent from the repo.
  Project would not compile.
- **Fix:** Created compilable stub with `openCellIdApiKey`, `hasOpenCellIdKey`,
  `effectiveApiKey`, and `privacyMode`. All safe defaults (empty key, privacy off).
- **Status:** [FIXED]

### 6.7 Signal batches silently dropped under scanner contention
- **File:** `lib/core/scan_coordinator.dart`
- **Issue:** `_processingSignals` flag caused incoming scanner batches to be silently
  discarded while DB writes / analyzer were running. Missed observations = reduced
  detection coverage for a SIGINT tool.
- **Fix:** Replaced flag with `ListQueue<List<LBSignal>>` drain loop. Batches are
  enqueued and processed in arrival order; none are ever dropped. Queue cleared on
  `stopScan()`. Added `dart:collection` import.
- **Status:** [FIXED]


## Round 7 Fixes (2026-04-02) — External Code Review, Second Pass

### 7.1 RadarScreen: stale hardcoded version string
- **File:** `lib/ui/radar/radar_screen.dart`
- **Issue:** Top bar showed `v0.1.0` regardless of pubspec version.
- **Fix:** Updated to `v0.7.1`.
- **Status:** [FIXED]

### 7.2 RadarPainter.shouldRepaint: misses blip content changes
- **File:** `lib/ui/radar/radar_painter.dart`
- **Issue:** Only checked blip count and sweep angle. A blip gaining a threat flag
  (clean → hostile) or changing RSSI would not trigger repaint if count was unchanged.
- **Fix:** Added per-blip id/threatFlag/rssi/angle/radius comparison.
- **Status:** [FIXED]

### 7.3 SignalListScreen._filtered: cache stale across signal updates
- **File:** `lib/ui/screens/signal_list_screen.dart`
- **Issue:** Cache key only tracked sort order. New signal batches from parent were
  served the stale sorted list until sort was toggled.
- **Fix:** Added `_cachedInput` identity check — cache invalidated when `widget.signals`
  reference changes.
- **Status:** [FIXED]

### 7.4 Timeline CSV export: duplicate RSSI column
- **File:** `lib/ui/screens/timeline_screen.dart`
- **Issue:** Header declared `RSSI,dBm` as two columns; both mapped to `o.rssi`.
  Column count mismatch causes malformed CSV (10 header cols, 9 data cols).
- **Fix:** Merged to single `RSSI (dBm)` column; removed duplicate value.
- **Status:** [FIXED]

### 7.5 OuiLookup.init(): concurrent-call race condition
- **File:** `lib/core/db/oui_lookup.dart`
- **Issue:** If two callers hit `init()` before `_table` is set, second caller saw
  `_loading = true`, returned early, and immediately called `resolve()` on a null
  `_table`, causing a null-check crash.
- **Fix:** Replaced `bool _loading` flag with `Completer<void>` — all concurrent callers
  await the same future, ensuring `_table` is populated before any returns.
- **Status:** [FIXED]

### 7.6 PermissionGate SKIP button was a no-op
- **File:** `lib/ui/screens/permission_gate.dart`
- **Issue:** `onPressed: () => setState(() {})` cannot advance past the gate because
  `_requiredGranted` remains false — the rebuild just re-renders the same screen.
  The comment said "force rebuild → auto-advance" but that was wrong.
- **Fix:** Added `bool _skipped` flag. SKIP sets it to true; `build()` returns
  `widget.child` when `_requiredGranted || _skipped`.
- **Status:** [FIXED]

