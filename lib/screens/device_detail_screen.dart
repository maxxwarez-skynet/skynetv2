import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:skynet/models/device_data_model.dart';
import 'package:skynet/models/user_model.dart';
import 'package:skynet/services/database_service.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DeviceDetailScreen extends StatefulWidget {
  final DeviceModel device;

  const DeviceDetailScreen({
    super.key,
    required this.device,
  });

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  final DatabaseService _database = DatabaseService();
  
  // Streams
  Stream<Map<String, dynamic>>? _deviceStream;
  Stream<Map<String, dynamic>>? _latestDataStream;
  Stream<List<Map<String, dynamic>>>? _historyStream;
  
  @override
  void initState() {
    super.initState();
    _setupStreams();
    
    // Also load data once for initial state
    _loadDeviceData();
  }
  
  @override
  void dispose() {
    // No need to cancel streams as they're automatically closed when the widget is disposed
    super.dispose();
  }
  
  void _setupStreams() {
    try {
      // Set up the device details stream
      _deviceStream = _database.getDeviceDetailsStream(widget.device.id);
      
      // Set up the latest data stream
      _latestDataStream = _database.getLatestDeviceDataStream(widget.device.id);
      
      // Set up the history stream
      _historyStream = _database.getDeviceDataHistoryStream(widget.device.id, limit: 20);
      
      print('Streams set up for device: ${widget.device.id}');
      
      // Force a rebuild to ensure the streams are used
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('Error setting up streams: $e');
    }
  }
  
  // Legacy method for initial data loading
  Future<void> _loadDeviceData() async {
    setState(() {
    });
    
    try {
      // Get the device details
      
      // Get the latest device data and convert to DeviceDataModel
      Map<String, dynamic> latestDataMap = await _database.getLatestDeviceData(widget.device.id);

      // Get the device data history and convert each item to DeviceDataModel
      
      setState(() {
      });
    } catch (e) {
      print('Error loading device data: $e');
      setState(() {
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    Provider.of<User?>(context);
    
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.name),
        backgroundColor: Colors.blue,
      ),
      body: _deviceStream == null || _latestDataStream == null || _historyStream == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDeviceData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Device Info Card with real-time updates
                      StreamBuilder<Map<String, dynamic>>(
                        stream: _deviceStream,
                        initialData: {
                          'id': widget.device.id,
                          'name': widget.device.name,
                          'status': widget.device.status,
                          'state': widget.device.state,
                          'lastActive': widget.device.lastActive != null 
                              ? Timestamp.fromDate(widget.device.lastActive!) 
                              : null,
                          'settings': {},
                        },
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            print('Device stream error: ${snapshot.error}');
                            return Card(
                              elevation: 4,
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Text('Error: ${snapshot.error}'),
                              ),
                            );
                          }
                          
                          if (!snapshot.hasData) {
                            print('Device stream has no data');
                            return const Card(
                              elevation: 4,
                              child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Center(child: CircularProgressIndicator()),
                              ),
                            );
                          }
                          
                          print('Device stream data received: ${snapshot.data}');
                          
                          // Make sure the data has all required fields for DeviceModel
                          Map<String, dynamic> deviceData = Map<String, dynamic>.from(snapshot.data!);
                          if (!deviceData.containsKey('settings')) {
                            deviceData['settings'] = {};
                          }
                          
                          // Convert the data to a DeviceModel
                          DeviceModel device = DeviceModel.fromMap(deviceData);
                          
                          return Card(
                            elevation: 4,
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Flexible(
                                        child: Text(
                                          'Device Information',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _buildStatusIndicator(device.status, device.state),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  _buildInfoRow('ID', device.id),
                                  _buildInfoRow('Name', device.name),
                                  _buildInfoRow('Status', device.status),
                                  _buildInfoRow('State', device.state ? 'Active' : 'Inactive'),
                                  if (device.lastActive != null)
                                    _buildInfoRow(
                                      'Last Active',
                                      DateFormat('MMM d, yyyy HH:mm').format(device.lastActive!),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Latest Data Card with real-time updates
                      StreamBuilder<Map<String, dynamic>>(
                        stream: _latestDataStream,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            print('Latest data stream error: ${snapshot.error}');
                            return Card(
                              elevation: 4,
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Text('Error loading sensor data: ${snapshot.error}'),
                              ),
                            );
                          }
                          
                          if (!snapshot.hasData) {
                            print('Latest data stream has no data');
                            return const Card(
                              elevation: 4,
                              child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Center(child: CircularProgressIndicator()),
                              ),
                            );
                          }
                          
                          print('Latest data stream received: ${snapshot.data}');
                          
                          // Convert the data to a DeviceDataModel
                          DeviceDataModel latestData = DeviceDataModel.fromFirestore(snapshot.data!);
                          
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Latest Sensor Data',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Card(
                                elevation: 4,
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildInfoRow(
                                        'Timestamp',
                                        DateFormat('MMM d, yyyy HH:mm:ss').format(latestData.timestamp),
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'Sensor Values',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      ...latestData.sensorData.entries.map((entry) => 
                                        _buildSensorValueRow(entry.key, entry.value.toString())
                                      ),
                                      if (latestData.sensorData.isEmpty)
                                        const Text(
                                          'No sensor data available',
                                          style: TextStyle(
                                            fontStyle: FontStyle.italic,
                                            color: Colors.grey,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Data History with real-time updates
                      StreamBuilder<List<Map<String, dynamic>>>(
                        stream: _historyStream,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            print('History stream error: ${snapshot.error}');
                            return Card(
                              elevation: 4,
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Text('Error loading history: ${snapshot.error}'),
                              ),
                            );
                          }
                          
                          print('History stream connection state: ${snapshot.connectionState}');
                          if (snapshot.hasData) {
                            print('History stream received ${snapshot.data?.length} items');
                          }
                          
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Data History',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (!snapshot.hasData || snapshot.data!.isEmpty)
                                const Card(
                                  elevation: 2,
                                  child: Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: Center(
                                      child: Text(
                                        'No data history available',
                                        style: TextStyle(
                                          fontStyle: FontStyle.italic,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              else
                                ...snapshot.data!.map((data) => 
                                  _buildDataHistoryItem(DeviceDataModel.fromFirestore(data))
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
  
  Widget _buildStatusIndicator(String status, bool deviceState) {
    bool isOnline = status.toLowerCase() == 'online';
    Color statusColor = isOnline ? Colors.green : Colors.red;
    
    return Row(
      mainAxisSize: MainAxisSize.min, // Ensure the row takes only the space it needs
      children: [
        // Status indicator (online/offline)
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: statusColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          status,
          style: TextStyle(
            fontSize: 14,
            color: statusColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 20),
        // Wrap the Switch in a Material widget to ensure proper compositing
        Material(
          type: MaterialType.transparency,
          child: Switch(
            value: deviceState,
            onChanged: (value) {
              _toggleDeviceState(value);
            },
            activeColor: Colors.green,
            activeTrackColor: Colors.green.shade100,
            inactiveThumbColor: Colors.grey,
            inactiveTrackColor: Colors.grey.shade300,
          ),
        ),
      ],
    );
  }
  
  Future<void> _toggleDeviceState(bool isOn) async {
    final user = Provider.of<User?>(context, listen: false);
    if (user != null) {
      // Show a loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 20, 
                  height: 20, 
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  )
                ),
                const SizedBox(width: 16),
                Text('Turning device ${isOn ? 'ON' : 'OFF'}...'),
              ],
            ),
            duration: const Duration(seconds: 1),
          ),
        );
      }
      
      try {
        print('Toggling device state to ${isOn ? 'ON' : 'OFF'} for device ${widget.device.id}');
        
        // Force a delay to ensure the loading indicator is shown
        await Future.delayed(const Duration(milliseconds: 300));
        
        // Call the database service to update the device state
        await _database.setDeviceState(user.uid, widget.device.id, isOn);
        
        print('Device state updated successfully in Firestore');
        
        // Show a success snackbar
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Device turned ${isOn ? 'ON' : 'OFF'}'),
              backgroundColor: isOn ? Colors.green : Colors.red,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        print('Error toggling device state: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to toggle device state: ${e.toString()}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } else {
      print('User is null, cannot toggle device state');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: Not logged in'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  // Keep the original method for backward compatibility
  
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSensorValueRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 3,
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDataHistoryItem(DeviceDataModel data) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 8.0),
      child: ExpansionTile(
        title: Text(
          DateFormat('MMM d, yyyy HH:mm:ss').format(data.timestamp),
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Status: ${data.status}',
              style: TextStyle(
                fontSize: 12,
                color: data.status.toLowerCase() == 'online' ? Colors.green : Colors.red,
              ),
            ),
            Text(
              'State: ${data.state ? 'ON' : 'OFF'}',
              style: TextStyle(
                fontSize: 12,
                color: data.state ? Colors.green : Colors.red,
              ),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sensor Values',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ...data.sensorData.entries.map((entry) =>
                  _buildSensorValueRow(entry.key, entry.value.toString())
                ),
                if (data.sensorData.isEmpty)
                  const Text(
                    'No sensor data available',
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: Colors.grey,
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Reported by: ${data.reportedBy}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}