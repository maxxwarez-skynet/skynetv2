import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:rxdart/rxdart.dart';

class DatabaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Collection references
  final CollectionReference usersCollection = FirebaseFirestore.instance.collection('users');
  final CollectionReference devicesCollection = FirebaseFirestore.instance.collection('devices');
  
  // Stream controllers for real-time updates
  Stream<DocumentSnapshot> getUserStream(String uid) {
    return usersCollection.doc(uid).snapshots();
  }
  
  Stream<DocumentSnapshot> getDeviceStream(String deviceId) {
    return devicesCollection.doc(deviceId).snapshots();
  }
  
  // Create a stream that combines user data with real-time device updates
  Stream<List<Map<String, dynamic>>> getUserDevicesStream(String uid) {
    // Get a stream of the user document to track device IDs
    return usersCollection.doc(uid).snapshots().switchMap((userSnapshot) {
      if (!userSnapshot.exists || userSnapshot.data() == null) {
        return Stream.value([]);
      }
      
      Map<String, dynamic> userData = userSnapshot.data() as Map<String, dynamic>;
      
      if (!userData.containsKey('devices') || userData['devices'] is! List || (userData['devices'] as List).isEmpty) {
        return Stream.value([]);
      }
      
      List<String> deviceIds = (userData['devices'] as List).cast<String>();
      print('Getting streams for ${deviceIds.length} devices: $deviceIds');
      
      // Create a stream for each device
      List<Stream<Map<String, dynamic>>> deviceStreams = deviceIds.map((deviceId) {
        return devicesCollection.doc(deviceId).snapshots().map((deviceSnapshot) {
          if (!deviceSnapshot.exists || deviceSnapshot.data() == null) {
            return <String, dynamic>{'id': deviceId, 'name': 'Unknown Device', 'status': 'offline', 'state': false};
          }
          
          Map<String, dynamic> deviceData = deviceSnapshot.data() as Map<String, dynamic>;
          // Ensure the ID is included in the data
          deviceData['id'] = deviceId;
          
          print('Device stream update for $deviceId: state=${deviceData['state']}');
          return deviceData;
        });
      }).toList();
      
      // Combine all device streams into a single stream of device lists
      if (deviceStreams.isEmpty) {
        return Stream.value([]);
      }
      
      return CombineLatestStream.list(deviceStreams);
    });
  }
  
  // Get a combined stream of user data and devices with real-time updates
  Stream<Map<String, dynamic>> getUserDataStream(User user) {
    // Combine the user document stream with the devices stream
    return CombineLatestStream.combine2(
      // Stream 1: User document
      usersCollection.doc(user.uid).snapshots().map((snapshot) {
        if (!snapshot.exists || snapshot.data() == null) {
          // Create a new user document if it doesn't exist
          Map<String, dynamic> userData = {
            'uid': user.uid,
            'email': user.email ?? '',
            'displayName': user.displayName ?? 'User',
            'photoURL': user.photoURL,
            'createdAt': FieldValue.serverTimestamp(),
            'lastLogin': FieldValue.serverTimestamp(),
            'preferences': {'theme': 'light', 'notifications': true},
            'devices': [],
          };
          
          // Schedule the creation of the user document
          usersCollection.doc(user.uid).set(userData);
          return userData;
        }
        
        return snapshot.data() as Map<String, dynamic>;
      }),
      
      // Stream 2: Devices list
      getUserDevicesStream(user.uid),
      
      // Combine function
      (Map<String, dynamic> userData, List<Map<String, dynamic>> devices) {
        // Create a copy of the user data
        Map<String, dynamic> result = Map<String, dynamic>.from(userData);
        // Replace the devices array with the full device details
        result['devices'] = devices;
        print('Combined stream update: User=${result['displayName']}, Devices=${devices.length}');
        return result;
      }
    );
  }

  Future<bool> addDevice(String uid, String deviceId, String deviceName) async {
    try {
      print('Adding new device: $deviceId, $deviceName');
      // First, add the device to the devices collection
      await devicesCollection.doc(deviceId).set({
        'deviceId': deviceId,
        'name': deviceName,
        'ownerId': uid,
        'status': 'active',
        'state': false,  // Default to OFF
        'createdAt': FieldValue.serverTimestamp(),
        'lastActive': FieldValue.serverTimestamp(),
        'type': 'default',
        'settings': {},
      });
      
      // Verify the device was added with the state field
      DocumentSnapshot deviceDoc = await devicesCollection.doc(deviceId).get();
      if (deviceDoc.exists) {
        Map<String, dynamic> data = deviceDoc.data() as Map<String, dynamic>;
        print('Device added successfully with state: ${data['state']}');
      }

      // Then, add only the device ID to the user's devices list
      DocumentSnapshot userDoc = await usersCollection.doc(uid).get();

      if (userDoc.exists && userDoc.data() != null) {
        Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;

        List<dynamic> devices = [];
        if (userData.containsKey('devices') && userData['devices'] is List) {
          devices = userData['devices'] as List<dynamic>;
        }

        // Add only the device ID
        devices.add(deviceId);

        await usersCollection.doc(uid).update({
          'devices': devices,
        });

        print('Device added successfully: $deviceId - $deviceName');
        return true;
      } else {
        print('User not found, cannot add device');
        // Try to delete the device document since we couldn't add it to the user
        await devicesCollection.doc(deviceId).delete();
        return false;
      }
    } catch (e) {
      print('Error adding device: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> getUserData(User user) async {
    try {
      print('Getting user data for uid: ${user.uid}');
      // Force a refresh from the server to get the latest data
      DocumentSnapshot userDoc = await usersCollection.doc(user.uid).get(const GetOptions(source: Source.server));

      if (userDoc.exists && userDoc.data() != null) {
        Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
        print('User document found with data: ${userData.keys}');

        // Fetch the full device details for each device ID
        List<Map<String, dynamic>> deviceDetails = await getUserDevices(user.uid);
        print('Fetched ${deviceDetails.length} device details');

        // Replace the devices array with the full device details
        userData['devices'] = deviceDetails;

        return userData;
      } else {
        print('User document not found, creating new user');
        // Create a new user document if it doesn't exist
        Map<String, dynamic> userData = {
          'uid': user.uid,
          'email': user.email ?? '',
          'displayName': user.displayName ?? 'User',
          'photoURL': user.photoURL,
          'createdAt': FieldValue.serverTimestamp(),
          'lastLogin': FieldValue.serverTimestamp(),
          'preferences': {'theme': 'light', 'notifications': true},
          'devices': [],
        };

        await usersCollection.doc(user.uid).set(userData);
        return userData;
      }
    } catch (e) {
      print('Error getting user data: $e');
      // Return an empty map instead of null
      return {};
    }
  }

  Future<void> updateDeviceStatus(String uid, String deviceId, String newStatus) async {
    try {
      // Update status only in the devices collection
      await devicesCollection.doc(deviceId).update({
        'status': newStatus,
        'lastActive': FieldValue.serverTimestamp(),
      });

      print('Device status updated to $newStatus for device: $deviceId');
    } catch (e) {
      print('Error updating device status: $e');
      rethrow; // Re-throw to handle in the UI
    }
  }
  
  // Method to update the device state (ON/OFF)
  Future<void> setDeviceState(String uid, String deviceId, bool isOn) async {
    print('DatabaseService.setDeviceState called with uid: $uid, deviceId: $deviceId, isOn: $isOn');
    try {
      // First check if the document exists
      DocumentSnapshot deviceDoc = await devicesCollection.doc(deviceId).get(const GetOptions(source: Source.server));
      if (!deviceDoc.exists) {
        print('Error: Device document does not exist: $deviceId');
        throw Exception('Device document does not exist');
      }
      
      print('Updating device state in Firestore...');
      
      // Create a map with the fields to update
      Map<String, dynamic> updateData = {
        'state': isOn,
        'lastActive': FieldValue.serverTimestamp(),
      };
      
      // Print the update data for debugging
      print('Update data: $updateData');
      
      // Update the state field (boolean for on/off)
      await devicesCollection.doc(deviceId).update(updateData);

      print('Device state updated to ${isOn ? "ON" : "OFF"} for device: $deviceId');
      
      // Add a small delay to ensure Firestore has time to process the update
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Verify the update with a server refresh to ensure we get the latest data
      DocumentSnapshot updatedDoc = await devicesCollection.doc(deviceId).get(const GetOptions(source: Source.server));
      Map<String, dynamic> data = updatedDoc.data() as Map<String, dynamic>;
      print('Verified state after update: ${data['state']}');
      
      // If the state in Firestore doesn't match what we tried to set, try again
      if (data['state'] != isOn) {
        print('State mismatch detected! Firestore has ${data['state']} but we set $isOn. Retrying...');
        
        // Try again with a different approach
        await devicesCollection.doc(deviceId).set({
          'state': isOn,
          'lastActive': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        
        // Add another delay
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Verify again
        updatedDoc = await devicesCollection.doc(deviceId).get(const GetOptions(source: Source.server));
        data = updatedDoc.data() as Map<String, dynamic>;
        print('After retry, state is: ${data['state']}');
        
        // If still not matching, one more attempt with transaction
        if (data['state'] != isOn) {
          print('Still mismatched after retry. Using transaction...');
          await _firestore.runTransaction((transaction) async {
            transaction.update(devicesCollection.doc(deviceId), {'state': isOn});
          });
          
          print('Transaction completed');
        }
      }
    } catch (e) {
      print('Error updating device state: $e');
      rethrow; // Re-throw to handle in the UI
    }
  }

  Future<void> deleteDeviceCompletely(String uid, String deviceId) async {
    try {
      // Delete from devices collection
      await devicesCollection.doc(deviceId).delete();

      // Remove device ID from user's devices list
      DocumentSnapshot userDoc = await usersCollection.doc(uid).get();

      if (userDoc.exists && userDoc.data() != null) {
        Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;

        if (userData.containsKey('devices') && userData['devices'] is List) {
          List<dynamic> devices = userData['devices'] as List<dynamic>;

          // Remove the device ID from the list
          devices.remove(deviceId);

          await usersCollection.doc(uid).update({
            'devices': devices,
          });
        }
      }

      print('Device deleted successfully: $deviceId');
    } catch (e) {
      print('Error deleting device: $e');
      rethrow; // Re-throw to handle in the UI
    }
  }

  // Get the latest device data (one-time fetch)
  Future<Map<String, dynamic>> getLatestDeviceData(String deviceId) async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('device_data')
          .where('deviceId', isEqualTo: deviceId)
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get(const GetOptions(source: Source.server));

      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs.first.data() as Map<String, dynamic>;
      }
    } catch (e) {
      print('Error getting latest device data: $e');
    }

    // Return default data if no data is found or an error occurs
    return {
      'deviceId': deviceId,
      'sensorData': {},
      'timestamp': Timestamp.now(),
      'status': 'unknown',
      'state': false,  // Include the state field with default value
      'reportedBy': '',
    };
  }

  // Stream of latest device data (real-time updates)
  Stream<Map<String, dynamic>> getLatestDeviceDataStream(String deviceId) {
    print('Setting up latest device data stream for deviceId: $deviceId');
    return _firestore
        .collection('device_data')
        .where('deviceId', isEqualTo: deviceId)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isNotEmpty) {
            Map<String, dynamic> data = snapshot.docs.first.data();
            print('Latest device data stream update: $deviceId, data: $data');
            return data;
          }
          
          // Return default data if no data is found
          Map<String, dynamic> defaultData = {
            'deviceId': deviceId,
            'sensorData': {},
            'timestamp': Timestamp.now(),
            'status': 'unknown',
            'state': false,
            'reportedBy': '',
          };
          print('No latest device data found, returning default: $defaultData');
          return defaultData;
        });
  }

  // Stream of device data history (real-time updates)
  Stream<List<Map<String, dynamic>>> getDeviceDataHistoryStream(String deviceId, {int limit = 20}) {
    print('Setting up device data history stream for deviceId: $deviceId, limit: $limit');
    return _firestore
        .collection('device_data')
        .where('deviceId', isEqualTo: deviceId)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          List<Map<String, dynamic>> dataList = snapshot.docs.map((doc) => doc.data()).toList();
          print('Device data history stream update: $deviceId, items: ${dataList.length}');
          return dataList;
        });
  }

  // Get device data history (one-time fetch)
  Future<List<Map<String, dynamic>>> getDeviceDataHistory(String deviceId, {int limit = 20}) async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('device_data')
          .where('deviceId', isEqualTo: deviceId)
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .get(const GetOptions(source: Source.server));

      return snapshot.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
    } catch (e) {
      print('Error getting device data history: $e');
    }

    // Return an empty list if no data is found or an error occurs
    return [];
  }

  // Get device details from the devices collection (one-time fetch)
  Future<Map<String, dynamic>> getDeviceDetails(String deviceId) async {
    print('Getting device details for deviceId: $deviceId');
    try {
      // Force a refresh from the server to get the latest data
      DocumentSnapshot deviceDoc = await devicesCollection.doc(deviceId).get(const GetOptions(source: Source.server));

      if (deviceDoc.exists && deviceDoc.data() != null) {
        Map<String, dynamic> deviceData = deviceDoc.data() as Map<String, dynamic>;
        print('Device document found: $deviceId');
        print('Raw device data: $deviceData');
        
        // Check if state field exists
        if (deviceData.containsKey('state')) {
          print('State field exists with value: ${deviceData['state']}');
        } else {
          print('State field does not exist in the document');
        }

        // Ensure the data has the expected format for DeviceModel
        Map<String, dynamic> formattedData = {
          'id': deviceId,
          'name': deviceData['name'] ?? 'Unknown Device',
          'status': deviceData['status'] ?? 'offline',
          'state': deviceData['state'] ?? false,  // Include the state field
          'lastActive': deviceData['lastActive'],
          'settings': deviceData['settings'] ?? {},
          'type': deviceData['type'] ?? 'default',
          'createdAt': deviceData['createdAt'],
        };
        
        print('Formatted device data: $formattedData');
        return formattedData;
      } else {
        print('Device document not found: $deviceId');
      }
    } catch (e) {
      print('Error getting device details: $e');
    }

    print('Returning default device data for: $deviceId');
    // Return default data if device not found or error occurs
    return {
      'id': deviceId,
      'name': 'Unknown Device',
      'status': 'offline',
      'state': false,  // Include the state field with default value
      'settings': {},
    };
  }
  
  // Get device details as a stream (real-time updates)
  Stream<Map<String, dynamic>> getDeviceDetailsStream(String deviceId) {
    print('Setting up device details stream for deviceId: $deviceId');
    return devicesCollection.doc(deviceId).snapshots().map((deviceDoc) {
      if (deviceDoc.exists && deviceDoc.data() != null) {
        Map<String, dynamic> deviceData = deviceDoc.data() as Map<String, dynamic>;
        print('Device stream update: $deviceId, state: ${deviceData['state']}');
        
        // Ensure the data has the expected format for DeviceModel
        Map<String, dynamic> formattedData = {
          'id': deviceId,
          'name': deviceData['name'] ?? 'Unknown Device',
          'status': deviceData['status'] ?? 'offline',
          'state': deviceData.containsKey('state') ? deviceData['state'] : false,  // Include the state field
          'lastActive': deviceData['lastActive'],
          'settings': deviceData['settings'] ?? {},
          'type': deviceData['type'] ?? 'default',
          'createdAt': deviceData['createdAt'],
        };
        
        print('Formatted device data for stream: $formattedData');
        return formattedData;
      } else {
        print('Device document not found in stream: $deviceId');
        // Return default data if device not found
        Map<String, dynamic> defaultData = {
          'id': deviceId,
          'name': 'Unknown Device',
          'status': 'offline',
          'state': false,  // Include the state field with default value
          'settings': {},
          'lastActive': null,
          'type': 'default',
          'createdAt': null,
        };
        print('Returning default device data for stream: $defaultData');
        return defaultData;
      }
    });
  }

  // Update the last login timestamp for a user
  Future<void> updateLastLogin(String uid) async {
    try {
      print('Updating last login timestamp for user: $uid');
      await usersCollection.doc(uid).update({
        'lastLogin': FieldValue.serverTimestamp(),
      });
      print('Last login timestamp updated successfully');
    } catch (e) {
      print('Error updating last login timestamp: $e');
    }
  }

  // Get all devices for a user by fetching each device from the devices collection
  Future<List<Map<String, dynamic>>> getUserDevices(String uid) async {
    try {
      print('Getting devices for user: $uid');
      // First get the user document to get the list of device IDs - force server refresh
      DocumentSnapshot userDoc = await usersCollection.doc(uid).get(const GetOptions(source: Source.server));

      if (userDoc.exists && userDoc.data() != null) {
        Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;

        if (userData.containsKey('devices') && userData['devices'] is List) {
          List<dynamic> deviceIds = userData['devices'] as List<dynamic>;
          print('Found ${deviceIds.length} device IDs for user: $deviceIds');
          List<Map<String, dynamic>> devices = [];

          // Fetch each device's details
          for (String deviceId in deviceIds) {
            Map<String, dynamic> deviceData = await getDeviceDetails(deviceId);
            devices.add(deviceData);
          }

          print('Returning ${devices.length} device details');
          return devices;
        }
      }
    } catch (e) {
      print('Error getting user devices: $e');
    }

    // Return an empty list if no devices found or error occurs
    print('No devices found for user: $uid');
    return [];
  }
  
  // Register a new device with the given chip ID and name
  Future<bool> registerDevice(User user, String chipId, String deviceName) async {
    try {
      print('Registering new device: $chipId, $deviceName for user: ${user.uid}');
      
      // Check if the device already exists
      DocumentSnapshot deviceDoc = await devicesCollection.doc(chipId).get();
      if (deviceDoc.exists) {
        print('Device already exists with ID: $chipId');
        
        // Check if it's already assigned to this user
        Map<String, dynamic> deviceData = deviceDoc.data() as Map<String, dynamic>;
        
        // If the device is already assigned to this user, return success
        if (deviceData['ownerId'] == user.uid) {
          print('Device already registered to this user');
          return true;
        } 
        // If the device has no owner (ownerId is empty or null), allow this user to claim it
        else if (deviceData['ownerId'] == null || deviceData['ownerId'] == '') {
          print('Device exists but has no owner, claiming it for this user');
          
          // Update the device with the new owner
          await devicesCollection.doc(chipId).update({
            'ownerId': user.uid,
            'name': deviceName,
            'lastActive': FieldValue.serverTimestamp(),
          });
          
          // Add the device ID to the user's devices list
          DocumentSnapshot userDoc = await usersCollection.doc(user.uid).get();
          if (userDoc.exists && userDoc.data() != null) {
            Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
            
            List<dynamic> devices = [];
            if (userData.containsKey('devices') && userData['devices'] is List) {
              devices = userData['devices'] as List<dynamic>;
            }
            
            // Add the device ID if it's not already in the list
            if (!devices.contains(chipId)) {
              devices.add(chipId);
              await usersCollection.doc(user.uid).update({
                'devices': devices,
              });
            }
            
            print('Device claimed successfully: $chipId - $deviceName');
            return true;
          } else {
            print('User not found, cannot claim device');
            return false;
          }
        } 
        // If the device is assigned to another user, throw an exception
        else {
          print('Device already registered to another user');
          throw Exception('This device is already registered to another account');
        }
      }
      
      // If the device doesn't exist, add it using the existing addDevice method
      bool result = await addDevice(user.uid, chipId, deviceName);
      
      // Force a refresh of the device data in Firestore cache
      await devicesCollection.doc(chipId).get(const GetOptions(source: Source.server));
      
      return result;
    } catch (e) {
      print('Error registering device: $e');
      rethrow; // Re-throw to handle in the UI
    }
  }
  
  // Firebase Storage reference
  final FirebaseStorage _storage = FirebaseStorage.instance;
  
  // Get a list of image URLs for a specific device
  Future<List<String>> getDeviceImages(String deviceId, {int limit = 10}) async {
    try {
      print('Fetching images for device: $deviceId');
      
      // Reference to the images folder for this device
      final storageRef = _storage.ref().child('images/$deviceId');
      
      try {
        // List all items in the folder
        final ListResult result = await storageRef.listAll();
        
        // Get download URLs for each item, sorted by name (which might contain timestamp)
        List<String> urls = [];
        
        // Process items in reverse order to get newest first (assuming filenames have timestamps)
        for (var item in result.items.reversed) {
          if (urls.length >= limit) break; // Respect the limit
          
          try {
            String url = await item.getDownloadURL();
            urls.add(url);
          } catch (e) {
            print('Error getting download URL for ${item.name}: $e');
            // Continue with the next item
          }
        }
        
        print('Found ${urls.length} images for device $deviceId');
        return urls;
      } catch (e) {
        print('Error listing images for device $deviceId: $e');
        // Return empty list if folder doesn't exist or other error
        return [];
      }
    } catch (e) {
      print('Error in getDeviceImages: $e');
      return [];
    }
  }
  
  // Stream of image URLs for a specific device
  Stream<List<String>> getDeviceImagesStream(String deviceId, {int limit = 10}) {
    // Create a BehaviorSubject to emit the latest image URLs
    final imagesSubject = BehaviorSubject<List<String>>();
    
    // Initial fetch
    getDeviceImages(deviceId, limit: limit).then((urls) {
      imagesSubject.add(urls);
    });
    
    // Set up a periodic refresh (every 30 seconds)
    Stream.periodic(const Duration(seconds: 30)).listen((_) {
      getDeviceImages(deviceId, limit: limit).then((urls) {
        imagesSubject.add(urls);
      });
    });
    
    return imagesSubject.stream;
  }
}
