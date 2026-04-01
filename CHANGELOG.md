# Changelog

All notable changes to this project will be documented in this file.

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