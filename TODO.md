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
9. [x] Documentation #9.1 - #9.3 (maintenance)

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
| **Total** | | **27** | **27** |
