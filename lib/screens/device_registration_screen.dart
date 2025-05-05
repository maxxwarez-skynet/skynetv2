import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:skynet/services/database_service.dart';
import 'package:provider/provider.dart';

class DeviceRegistrationScreen extends StatefulWidget {
  final String response;

  const DeviceRegistrationScreen({super.key, required this.response});

  @override
  State<DeviceRegistrationScreen> createState() => _DeviceRegistrationScreenState();
}

class _DeviceRegistrationScreenState extends State<DeviceRegistrationScreen> {
  bool _isLoading = false;
  String _deviceName = '';
  String? _errorMessage;
  Map<String, dynamic>? _parsedData;

  @override
  void initState() {
    super.initState();
    _parseResponse();
  }

  void _parseResponse() {
    try {
      // Print the raw response for debugging
      print('Raw response: ${widget.response}');
      
      // Try to parse the JSON
      _parsedData = json.decode(widget.response);
      print('Parsed data: $_parsedData');
      
      // If parsing succeeded but no chipID, set an error
      if (_parsedData == null || !_parsedData!.containsKey('chipID')) {
        setState(() {
          _errorMessage = 'No chip ID found in the response';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error parsing response: $e';
        print('JSON parse error: $e');
        print('Response that failed to parse: ${widget.response}');
      });
    }
  }

  Future<void> _registerDevice() async {
    if (_deviceName.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a device name';
      });
      return;
    }

    final user = Provider.of<User?>(context, listen: false);
    if (user == null) {
      setState(() {
        _errorMessage = 'You must be logged in to register a device';
      });
      return;
    }

    if (_parsedData == null || !_parsedData!.containsKey('chipID')) {
      setState(() {
        _errorMessage = 'No valid chip ID found';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final databaseService = DatabaseService();
      await databaseService.registerDevice(
        user,
        _parsedData!['chipID'].toString(),
        _deviceName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Device registered successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        // Navigate all the way back to the home screen
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to register device: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get the chip ID from the parsed data
    String chipID = _parsedData != null ? _parsedData!['chipID']?.toString() ?? 'No chipID found' : 'No data';
    
    return Scaffold(
      appBar: AppBar(title: const Text('Device Registration')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.devices, size: 64, color: Colors.blue),
                  const SizedBox(height: 24),
                  const Text(
                    'Register Your Device',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Device Information',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const Text('Chip ID:', style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  chipID,
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ),
                            ],
                          ),
                          if (_parsedData != null && _parsedData!.containsKey('status')) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Text('Status:', style: TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(width: 8),
                                Text(_parsedData!['status'].toString()),
                              ],
                            ),
                          ],
                          if (_parsedData != null && _parsedData!.containsKey('message')) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Text('Message:', style: TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(width: 8),
                                Expanded(child: Text(_parsedData!['message'].toString())),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red.shade800),
                      ),
                    ),
                  const SizedBox(height: 24),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Device Name',
                      hintText: 'Enter a name for your device',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.edit),
                    ),
                    onChanged: (value) => _deviceName = value,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: _registerDevice,
                    child: const Text('Register Device', style: TextStyle(fontSize: 18)),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
    );
  }
}