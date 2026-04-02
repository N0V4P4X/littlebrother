import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

/// Resolves MAC address prefixes to vendor names via embedded OUI table.
/// Table is loaded once and cached for the app lifetime.
class OuiLookup {
  OuiLookup._();
  static final OuiLookup instance = OuiLookup._();

  Map<String, String>? _table;
  Completer<void>? _initCompleter;

  Future<void> init() async {
    if (_table != null) return;
    if (_initCompleter != null) {
      // Another caller is already loading — wait for it.
      return _initCompleter!.future;
    }
    _initCompleter = Completer<void>();
    try {
      final raw = await rootBundle.loadString('assets/oui/oui_table.json');
      _table = Map<String, String>.from(jsonDecode(raw) as Map);
      _initCompleter!.complete();
    } catch (e) {
      debugPrint('LB_OUI failed to load OUI table: $e');
      _table = {};
      _initCompleter!.complete();
    }
  }

  /// Resolve a MAC address (any format) to vendor name.
  /// Returns empty string if unknown.
  String resolve(String mac) {
    if (_table == null || _table!.isEmpty) return '';
    final normalized = _normalizeMac(mac);
    if (normalized.length < 6) return '';

    // Try 24-bit (3-byte) OUI first
    final oui24 = normalized.substring(0, 6).toUpperCase();
    if (_table!.containsKey(oui24)) return _table![oui24]!;

    // Try 28-bit MA-S prefix
    if (normalized.length >= 7) {
      final oui28 = normalized.substring(0, 7).toUpperCase();
      if (_table!.containsKey(oui28)) return _table![oui28]!;
    }

    return '';
  }

  /// Detect if a MAC address appears to be locally administered (randomized).
  /// Bit 1 of the first octet set = locally administered = likely randomized.
  bool isRandomized(String mac) {
    final normalized = _normalizeMac(mac);
    if (normalized.length < 2) return false;
    final firstOctet = int.tryParse(normalized.substring(0, 2), radix: 16);
    if (firstOctet == null) return false;
    return (firstOctet & 0x02) != 0;
  }

  String _normalizeMac(String mac) =>
    mac.replaceAll(RegExp(r'[:\-\.]'), '').toLowerCase();
}
