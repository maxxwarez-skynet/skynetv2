import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';

// Custom WiFiInfoHelper class to get WiFi SSID information
class WiFiInfoHelper {
  Future<String?> getWifiName() async {
    try {
      // Use the NetworkInfo class from network_info_plus package
      final networkInfo = NetworkInfo();
      return await networkInfo.getWifiName();
    } catch (e) {
      print('Error getting WiFi name: $e');
      return null;
    }
  }
}

/// A service to handle WiFi connection functionality
class WiFiService {
  static final WiFiService _instance = WiFiService._internal();
  static const MethodChannel _channel = MethodChannel('com.example.garden_helper/wifi');

  factory WiFiService() {
    return _instance;
  }

  WiFiService._internal();

  /// Check if the device is connected to WiFi
  Future<bool> isConnectedToWifi() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult == ConnectivityResult.wifi;
  }

  /// Connect to a specific WiFi network
  ///
  /// On Android, this will attempt to guide the user to WiFi settings
  /// On iOS, this will show a dialog with instructions
  Future<bool> connectToWifi(BuildContext context, String ssid) async {
    if (Platform.isAndroid) {
      // On Android, we can try to open WiFi settings
      return _openAndroidWifiSettings();
    } else if (Platform.isIOS) {
      // On iOS, we need to show manual instructions
      _showIosConnectionDialog(context, ssid);
      return false;
    }
    return false;
  }

  /// Open Android WiFi settings using the Settings.Panel.ACTION_WIFI intent
  Future<bool> _openAndroidWifiSettings() async {
    if (Platform.isAndroid) {
      try {
        // Try to use the method channel to open the WiFi panel
        final bool result = await _channel.invokeMethod('openWifiSettings');
        return result;
      } catch (e) {
        // If the method channel fails, fall back to the URL launcher approaches
        return _fallbackOpenWifiSettings();
      }
    }
    return false;
  }

  /// Fallback methods to open WiFi settings if the method channel fails
  Future<bool> _fallbackOpenWifiSettings() async {
    // Try different approaches to open WiFi settings
    
    // Try the standard Android settings URI for WiFi settings
    try {
      final uri = Uri.parse('android-settings:wifi');
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      // Ignore and try next method
      print('Failed to launch android-settings:wifi: $e');
    }

    // Try the intent URI approach
    try {
      final uri = Uri.parse('android.settings.WIFI_SETTINGS');
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      // Ignore and try next method
      print('Failed to launch android.settings.WIFI_SETTINGS: $e');
    }
    
    // Try the package-based approach
    try {
      final uri = Uri.parse('package:android.settings/wifi');
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      // Ignore and try next method
      print('Failed to launch package:android.settings/wifi: $e');
    }

    // Fallback to a more generic approach - open main settings
    try {
      final uri = Uri.parse('package:android.settings/settings');
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      print('Failed to launch package:android.settings/settings: $e');
      return false;
    }

    return false;
  }
  
  /// Show a dialog with instructions for iOS users
  void _showIosConnectionDialog(BuildContext context, String ssid) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Connect to Device WiFi"),
        content: Text(
          "Please follow these steps to connect to the device:\n\n"
          "1. Go to Settings > WiFi\n"
          "2. Connect to '$ssid'\n"
          "3. Return to this app when connected"
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }
  
  // We no longer need the openCaptivePortal method as we're using WebView instead
  
  /// Check if connected to the device's WiFi by making a request to the device's IP
  /// Returns true if the device is reachable, false otherwise
  Future<bool> isConnectedToDeviceWifi() async {
    // First check if connected to any WiFi
    final isConnected = await isConnectedToWifi();
    if (!isConnected) {
      print('Not connected to any WiFi network');
      return false;
    }
    
    // Check if we're connected to a network with the expected SSID
    // Note: This is only available on Android and requires location permissions
    if (Platform.isAndroid) {
      try {
        // Try to get the current SSID using the network_info_plus plugin
        // This requires location permissions on Android
        final networkInfo = NetworkInfo();
        final ssid = await networkInfo.getWifiName();
        print('Current WiFi SSID: $ssid');
        
        // Check if the SSID contains our expected device name
        // Note: Android prefixes SSIDs with double quotes
        if (ssid != null && 
            (ssid.contains('Skynet-AutoConnect') || 
             ssid.contains('"Skynet-AutoConnect"'))) {
          print('Connected to Skynet-AutoConnect WiFi');
          return true;
        }
      } catch (e) {
        print('Error getting WiFi SSID: $e');
        // Fall back to the HTTP request method if we can't get the SSID
      }
    }
    
    // Try multiple IP addresses that the device might be using
    final possibleIPs = [
      'http://192.168.4.1/',
      'http://192.168.4.1:80/',
      'http://192.168.1.1/',
      'http://192.168.0.1/'
    ];
    
    for (final ip in possibleIPs) {
      try {
        print('Trying to connect to $ip');
        // Set a short timeout to avoid hanging the UI
        final response = await http.get(
          Uri.parse(ip),
        ).timeout(const Duration(seconds: 2));
        
        // If we get any response, consider it a success
        if (response.statusCode >= 200 && response.statusCode < 400) {
          print('Successfully connected to $ip with status code ${response.statusCode}');
          return true;
        } else {
          print('Received status code ${response.statusCode} from $ip');
        }
      } catch (e) {
        // If there's an error, try the next IP
        print('Failed to connect to $ip: $e');
      }
    }
    
    // If all HTTP requests fail, check if the network SSID contains our device name
    // This is a fallback method that might work even if the HTTP requests fail
    try {
      final connectivity = Connectivity();
      final connectivityResult = await connectivity.checkConnectivity();
      
      if (connectivityResult == ConnectivityResult.wifi) {
        // On some devices, we might be able to get WiFi info
        final networkInfo = NetworkInfo();
        final wifiInfo = await networkInfo.getWifiName();
        print('WiFi name from NetworkInfo: $wifiInfo');
        
        if (wifiInfo != null && 
            (wifiInfo.contains('Skynet-AutoConnect') || 
             wifiInfo.contains('"Skynet-AutoConnect"'))) {
          print('Connected to Skynet-AutoConnect WiFi based on name');
          return true;
        }
      }
    } catch (e) {
      print('Error checking WiFi info: $e');
    }
    
    print('Not connected to device WiFi');
    return false;
  }
}

// Simplified NetworkSecurity enum for compatibility
enum NetworkSecurity { NONE, WEP, WPA, WPA2, WPA3 }