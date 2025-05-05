import 'package:cloud_firestore/cloud_firestore.dart';

class DeviceDataModel {
  final String deviceId;
  final Map<String, dynamic> sensorData;
  final DateTime timestamp;
  final String status;
  final bool state;  // New field for ON/OFF state
  final String reportedBy; // Device or user ID that reported this data

  DeviceDataModel({
    required this.deviceId,
    required this.sensorData,
    required this.timestamp,
    required this.status,
    this.state = false,  // Default to OFF
    required this.reportedBy,
  });

  // Create a DeviceDataModel from a Firestore document
  factory DeviceDataModel.fromFirestore(Map<String, dynamic> data) {
    // Handle timestamp that might be null or of different types
    DateTime timestampDate = DateTime.now();
    if (data['timestamp'] is Timestamp) {
      timestampDate = (data['timestamp'] as Timestamp).toDate();
    }

    return DeviceDataModel(
      deviceId: data['deviceId'] ?? '',
      sensorData: data['sensorData'] is Map 
          ? Map<String, dynamic>.from(data['sensorData'] as Map) 
          : {},
      timestamp: timestampDate,
      status: data['status'] ?? 'unknown',
      state: data['state'] ?? false,  // Default to OFF if not present
      reportedBy: data['reportedBy'] ?? '',
    );
  }

  // Convert DeviceDataModel to a Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'deviceId': deviceId,
      'sensorData': sensorData,
      'timestamp': Timestamp.fromDate(timestamp),
      'status': status,
      'state': state,
      'reportedBy': reportedBy,
    };
  }
}