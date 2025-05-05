// This is a stub file to allow conditional imports for WiFi functionality
// It provides empty implementations for platforms that don't support WiFi_IoT

// Stub class to match WiFiForIoTPlugin
class WiFiForIoTPlugin {
  static Future<bool> setEnabled(bool enabled) async => false;
  static Future<List<WifiNetwork>> loadWifiList() async => [];
  static Future<bool> connect(String ssid, {String? password, NetworkSecurity? security}) async => false;
  static Future<bool> isConnected() async => false;
  static Future<String?> getSSID() async => null;
  static Future<bool?> isEnabled() async => false;
}

// Stub class to match WifiNetwork
class WifiNetwork {
  final String ssid;
  final String bssid;
  final int level;
  final int frequency;
  final NetworkSecurity security;

  WifiNetwork({
    this.ssid = '',
    this.bssid = '',
    this.level = 0,
    this.frequency = 0,
    this.security = NetworkSecurity.NONE,
  });
}

// Stub enum to match NetworkSecurity
enum NetworkSecurity { NONE, WEP, WPA, WPA2, WPA3 }