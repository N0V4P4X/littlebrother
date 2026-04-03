/// Known privacy-breaking and captive portal SSIDs that pose risks:
/// - Captive portals (mitm risk, data harvesting)
/// - Mobile hotspot impersonation (evil twin)
/// - Known malicious/rogue patterns
library;

class KnownPrivacyAps {
  /// SSID prefixes that indicate captive portal / commercial WiFi
  static const List<String> captivePortalPrefixes = [
    'xfinity',
    'xfinitywifi',
    'attwifi',
    'attwifi',
    'cablewifi',
    'coxwifi',
    'optimumwifi',
    'spectrumwifi',
    'verizon',
    'tmobile',
    't-mobile',
    'boostmobile',
    'starbucks',
    'mcdonalds',
    'mcdonalds_wifi',
    'google Starbucks',
    'Google Starbucks',
    'ubifree',
    'ubiquiti',
    'linksys',
    'netgear',
    'dlink',
    'tp-link',
    'tplink',
    'wireless',
    'wifi',
    'free wifi',
    'free_wifi',
    'public wifi',
    'public_wifi',
    'guest',
    'guest network',
  ];

  /// SSID patterns that are commonly spoofed
  static const List<String> commonlySpoofedSsids = [
    'home',
    'home wifi',
    'home network',
    'home wifi 5g',
    'homewifi',
    'my wifi',
    'mywifi',
    'my network',
    'mynetwork',
    'wifi',
    'wireless',
    'default',
    'free wifi',
    'free_public',
  ];

  /// Known rogue/honeypot SSID patterns
  static const List<String> honeypotPatterns = [
    'free wifi',
    'free_wifi',
    'free public wifi',
    'public free wifi',
    'totally free wifi',
    'free_internet',
    'free internet',
    'no password',
    'no password wifi',
    'open wifi',
    'free access',
    'welcome',
    'airport free wifi',
    'hotel wifi',
    'airline wifi',
    'gogo internet',
    'delta wifi',
    'united wifi',
    'american wifi',
  ];

  /// Captive portal domains (for network inspection correlation)
  static const List<String> captivePortalDomains = [
    'captive.apple.com',
    'clients3.google.com',
    'connect.starbucks.com',
    'wireless.comcast.com',
    'attwifi.com',
    'xfinity.com',
    'cox.net',
    'optimum.net',
  ];

  /// Check if SSID matches privacy-breaking patterns
  static PrivacyRisk checkSsid(String ssid) {
    if (ssid.isEmpty) return PrivacyRisk.none;
    
    final lower = ssid.toLowerCase();
    
    // Check exact matches for captive portal prefixes
    for (final prefix in captivePortalPrefixes) {
      if (lower.startsWith(prefix) || lower.contains(prefix)) {
        return PrivacyRisk.captivePortal;
      }
    }
    
    // Check honeypot patterns
    for (final pattern in honeypotPatterns) {
      if (lower.contains(pattern)) {
        return PrivacyRisk.honeypot;
      }
    }
    
    return PrivacyRisk.none;
  }

  /// Check if this looks like a spoofed home network
  static bool isLikelySpoofedHome(String ssid) {
    final lower = ssid.toLowerCase();
    for (final pattern in commonlySpoofedSsids) {
      if (lower == pattern || lower.startsWith('$pattern ') || lower.endsWith(' $pattern')) {
        return true;
      }
    }
    return false;
  }

  /// Get risk level name
  static String riskName(PrivacyRisk risk) {
    switch (risk) {
      case PrivacyRisk.none:
        return 'Clean';
      case PrivacyRisk.captivePortal:
        return 'Captive Portal';
      case PrivacyRisk.honeypot:
        return 'Honeypot';
      case PrivacyRisk.spoofed:
        return 'Spoofed Network';
      case PrivacyRisk.evilTwin:
        return 'Evil Twin';
    }
  }
}

enum PrivacyRisk {
  none,
  captivePortal,
  honeypot,
  spoofed,
  evilTwin,
}
