import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:skynet/shared/loading.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

import 'package:skynet/services/wifi_service.dart';
import 'package:skynet/screens/device_inappwebview_screen.dart';

class AddDeviceScreen extends StatefulWidget {
  const AddDeviceScreen({super.key});

  @override
  State<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends State<AddDeviceScreen> with WidgetsBindingObserver {
  int _currentStep = 0;
  static const int STEP_POWER_DEVICE = 0;
  static const int STEP_SEARCHING = 1;

  bool _isLoading = false;
  String? _errorMessage;
  bool _isScanning = false;
  bool _isWifiConnected = false;
  bool _isConnectedToDeviceWifi = false;

  final WiFiService _wifiService = WiFiService();
  static const String DEVICE_SSID = "Skynet-AutoConnect";
  static const String DEVICE_IP = 'http://192.168.4.1';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkWifiStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkWifiStatus();
    }
  }

  Future<void> _checkWifiStatus() async {
    setState(() {
      _errorMessage = null;
    });
    
    try {
      // First check if connected to any WiFi
      final isConnected = await _wifiService.isConnectedToWifi();
      
      // Then check if connected to the device WiFi specifically
      bool isConnectedToDevice = false;
      if (isConnected) {
        isConnectedToDevice = await _wifiService.isConnectedToDeviceWifi();
        print('WiFi connected: $isConnected, Connected to device: $isConnectedToDevice');
      }

      if (mounted) {
        setState(() {
          _isWifiConnected = isConnected;
          _isConnectedToDeviceWifi = isConnectedToDevice;
          
          // Clear error message if successfully connected
          if (isConnectedToDevice) {
            _errorMessage = null;
            print('Successfully connected to device WiFi');
          } else if (isConnected) {
            // Connected to WiFi but not to the device
            print('Connected to WiFi but not to the device WiFi');
          } else {
            // Not connected to any WiFi
            print('Not connected to any WiFi');
          }
        });
      }
    } catch (e) {
      print('Error checking WiFi status: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Error checking WiFi status: ${e.toString()}';
        });
      }
    }
  }

  Future<void> _handleOpenDeviceSetup(User? user) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.get(Uri.parse('$DEVICE_IP/'));

      if (response.statusCode == 200 && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const DeviceInAppWebViewScreen(deviceUrl: '$DEVICE_IP/'),
          ),
        );
      } else {
        _setError('Device responded with status ${response.statusCode}');
      }
    } catch (e) {
      _setError('Failed to connect to device: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _setError(String message) {
    if (mounted) {
      setState(() {
        _errorMessage = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<User?>(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add New Device'),
        backgroundColor: theme.colorScheme.primary,
      ),
      body: _isLoading ? const Loading() : _buildCurrentStep(user, theme),
    );
  }

  Widget _buildCurrentStep(User? user, ThemeData theme) {
    return _currentStep == STEP_POWER_DEVICE
        ? _buildPowerDeviceStep(theme)
        : _buildSearchingStep(user, theme);
  }

  Widget _buildPowerDeviceStep(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.power_settings_new, size: 80, color: Colors.blue),
          const SizedBox(height: 32),
          const Text('Power Up Your Device', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          const Text('Make sure your device is powered up and blinking before continuing.', style: TextStyle(fontSize: 16), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          const Card(
            elevation: 4,
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue),
                  SizedBox(height: 10),
                  Text('Setup Instructions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 10),
                  Text('1. Plug in your device to a power source\n2. Wait for the LED to start blinking blue\n3. Press the Next button below to continue',
                    style: TextStyle(fontSize: 14), textAlign: TextAlign.left),
                ],
              ),
            ),
          ),
          const Spacer(),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => setState(() => _currentStep = STEP_SEARCHING),
            child: const Text('Next', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchingStep(User? user, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(_isScanning ? Icons.search : Icons.wifi, size: 80, color: _isScanning ? Colors.green : Colors.blue),
          const SizedBox(height: 32),
          Text(_isScanning ? 'Scanning for Devices...' : 'Connect to Device WiFi',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 16.0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(_errorMessage!, style: TextStyle(color: Colors.red.shade800), textAlign: TextAlign.center),
              ),
            ),
          const SizedBox(height: 24),
          _buildConnectionCard(theme),
          const Spacer(),
          if (!_isLoading && !_isScanning && _isConnectedToDeviceWifi)
            _buildActionButton('Open Device Setup', Colors.green, () => _handleOpenDeviceSetup(user)),
          if (_isScanning)
            _buildActionButton('Stop Scanning', Colors.red, () => setState(() => _isScanning = false)),
          if (!_isLoading)
            Padding(
              padding: const EdgeInsets.only(top: 16.0),
              child: TextButton(
                onPressed: () => setState(() => _currentStep = STEP_POWER_DEVICE),
                child: const Text('Back'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildConnectionCard(ThemeData theme) {
    return Column(
      children: [
        Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wifi, color: _isWifiConnected ? Colors.green : Colors.grey),
                    const SizedBox(width: 8),
                    Text(DEVICE_SSID, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Steps to connect:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('1. Tap "Open WiFi Settings" below\n2. Connect to "$DEVICE_SSID" network\n3. Return to this app and tap "Scan Device" below',
                  style: TextStyle(fontSize: 14, color: Colors.black87), textAlign: TextAlign.left),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _isConnectedToDeviceWifi ? Colors.green.shade50 : Colors.amber.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _isConnectedToDeviceWifi ? Colors.green.shade200 : Colors.amber.shade200),
          ),
          child: _isConnectedToDeviceWifi
              ? _buildConnectedNotice()
              : _buildWifiInstructionsButton(),
        ),
        const SizedBox(height: 24),
        const Text('Once connected, we\'ll scan for available ESP devices.',
            style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: Colors.grey), textAlign: TextAlign.center),
      ],
    );
  }

  Widget _buildConnectedNotice() {
    return Row(
      children: [
        const Icon(Icons.check_circle, color: Colors.green),
        const SizedBox(width: 12),
        Expanded(
          child: Text('You are connected to the device WiFi network!\nTap "Open Device Setup" below to continue.',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade700)),
        ),
      ],
    );
  }

  Widget _buildWifiInstructionsButton() {
    return Column(
      children: [
        Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.amber),
            const SizedBox(width: 12),
            Expanded(
              child: Text('You must connect to the device\'s WiFi network before opening device setup',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade800)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          icon: Icon(_isConnectedToDeviceWifi ? Icons.check_circle : Icons.settings),
          label: Text(_isConnectedToDeviceWifi ? 'Connected to Device WiFi' : 'Open WiFi Settings'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _isConnectedToDeviceWifi ? Colors.green : Colors.blue,
            foregroundColor: Colors.white,
          ),
          onPressed: _isConnectedToDeviceWifi ? null : () async {
            setState(() => _isLoading = true);
            try {
              final success = await _wifiService.connectToWifi(context, DEVICE_SSID);
              if (!success && mounted) {
                _setError("Could not open WiFi settings automatically. Please open them manually by going to your device's Settings > WiFi.");
                
                // Show a more detailed dialog with instructions
                if (mounted) {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text("Open WiFi Settings Manually"),
                      content: const Text(
                        "We couldn't open your WiFi settings automatically. Please follow these steps:\n\n"
                        "1. Exit this app\n"
                        "2. Open your device's Settings app\n"
                        "3. Go to WiFi settings\n"
                        "4. Connect to the \"$DEVICE_SSID\" network\n"
                        "5. Return to this app"
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
              }
              await Future.delayed(const Duration(seconds: 5), _checkWifiStatus);
            } catch (e) {
              _setError("Error: ${e.toString()}");
            } finally {
              if (mounted) setState(() => _isLoading = false);
            }
          },
        ),
        const SizedBox(height: 16),
        // Add a manual refresh button
        OutlinedButton.icon(
          icon: const Icon(Icons.refresh),
          label: const Text('Check Connection Again'),
          onPressed: () async {
            setState(() => _isLoading = true);
            await _checkWifiStatus();
            setState(() => _isLoading = false);
          },
        ),
        const SizedBox(height: 16),
        // Add a manual override button
        if (!_isConnectedToDeviceWifi)
          TextButton.icon(
            icon: const Icon(Icons.warning, color: Colors.orange),
            label: const Text(
              'I\'m connected but app doesn\'t detect it',
              style: TextStyle(color: Colors.orange),
            ),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text("Manual Connection Override"),
                  content: const Text(
                    "If you're sure you're connected to the \"$DEVICE_SSID\" WiFi network but the app isn't detecting it, you can manually override and proceed.\n\n"
                    "Note: This will only work if you're actually connected to the device WiFi."
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: const Text("Cancel"),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        setState(() {
                          _isConnectedToDeviceWifi = true;
                          _isWifiConnected = true;
                          _errorMessage = null;
                        });
                      },
                      child: const Text("Yes, I'm Connected", style: TextStyle(color: Colors.orange)),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildActionButton(String text, Color color, VoidCallback onPressed) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 4,
      ),
      onPressed: onPressed,
      child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }
}
