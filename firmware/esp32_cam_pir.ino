#include <WiFi.h>
#include <WebServer.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>      // For JSON parsing
#include <EEPROM.h>
#include <Firebase_ESP_Client.h>  // Firebase library with Firestore support
#include <time.h>             // For time functions
#include <addons/TokenHelper.h>  // Firebase token generation helper
#include <addons/RTDBHelper.h>   // RTDB helper functions
#include <ESPmDNS.h>          // For OTA service discovery
#include <Update.h>           // For OTA updates
#include "esp_camera.h"       // ESP32 Camera library
#include "soc/soc.h"          // Disable brownout problems
#include "soc/rtc_cntl_reg.h" // Disable brownout problems

// Function Declarations
void readConfigFromEEPROM();
bool connectToWiFi();
void setupOTA();
void normalOperationMode();
void setupMode();
void handleRoot();
void handleConfigure();
void saveConfigToEEPROM();
void checkDeviceState();
void createInitialDocument();
void checkForFirmwareUpdates();
void setupCamera();
bool captureAndSendPhoto();
void handleMotionDetection();

// Constants
#define FIRMWARE_VERSION "1.0.0"  // Current firmware version
#define LED_PIN 33                // Onboard LED on ESP32-CAM
#define PIR_PIN 13                // PIR sensor pin
#define FLASH_PIN 4               // Flash pin
#define CONFIG_MODE_TIMEOUT 300000  // 5 minutes in milliseconds
#define EEPROM_SIZE 512
#define EEPROM_WIFI_SSID_ADDR 0
#define EEPROM_WIFI_PASS_ADDR 32
#define EEPROM_API_KEY_ADDR 96
#define EEPROM_DEVICE_NAME_ADDR 160
#define EEPROM_CONFIG_FLAG_ADDR 288
#define EEPROM_UPDATE_FLAG_ADDR 289

// Firebase configuration
#define API_KEY "AIzaSyA-UDYSkC6FhyN84yBTGy91EiMamiZmcK0"  // Replace with your Firebase API Key
#define PROJECT_ID "skynet-17582"  // Replace with your Firebase Project ID
#define STORAGE_BUCKET "skynet-17582.firebasestorage.app"  // Firebase Storage bucket name
#define USER_EMAIL "master@skynet.com"  // Replace with your Firebase Auth email
#define USER_PASSWORD "password"  // Replace with your Firebase Auth password

// Function declarations
void sendStatusUpdate();

// Variables
bool isConfigured = false;
char deviceName[32] = "";
char deviceId[40] = "";  // Store device ID
char wifiSSID[32] = "";
char wifiPassword[32] = "";
unsigned long setupModeStartTime = 0;
unsigned long lastStateCheckTime = 0;
const unsigned long STATE_CHECK_INTERVAL = 5000;  // Check state every 5 seconds

// Motion detection variables
bool motionDetected = false;
unsigned long lastMotionTime = 0;
const unsigned long MOTION_COOLDOWN = 10000;  // 10 seconds cooldown between motion detections

// Firebase objects
FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;
FirebaseJson content;

// Web server for configuration portal
WebServer webServer(80);

// LED blinking variables
unsigned long lastLedToggleTime = 0;
bool ledState = HIGH;

// EEPROM backup area - used to preserve settings during OTA updates
#define EEPROM_BACKUP_ADDR 350
#define EEPROM_BACKUP_SIZE 128  // Enough to store WiFi credentials and device name

// Camera pins for ESP32-CAM
#define PWDN_GPIO_NUM     32
#define RESET_GPIO_NUM    -1
#define XCLK_GPIO_NUM      0
#define SIOD_GPIO_NUM     26
#define SIOC_GPIO_NUM     27
#define Y9_GPIO_NUM       35
#define Y8_GPIO_NUM       34
#define Y7_GPIO_NUM       39
#define Y6_GPIO_NUM       36
#define Y5_GPIO_NUM       21
#define Y4_GPIO_NUM       19
#define Y3_GPIO_NUM       18
#define Y2_GPIO_NUM        5
#define VSYNC_GPIO_NUM    25
#define HREF_GPIO_NUM     23
#define PCLK_GPIO_NUM     22

void setup() {
  Serial.begin(115200);
  delay(1000); // Give serial monitor time to start
  
  // Disable brownout detector
  WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0);
  
  // Initialize LED pin
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, HIGH);    // Turn LED off initially

  pinMode(FLASH_PIN, OUTPUT);
  digitalWrite(FLASH_PIN, LOW); 
  
  // Initialize PIR sensor pin
  pinMode(PIR_PIN, INPUT);
  
  // Initialize EEPROM
  EEPROM.begin(EEPROM_SIZE);
  
  // Check if device is already configured
  isConfigured = (EEPROM.read(EEPROM_CONFIG_FLAG_ADDR) == 1);
  
  if (isConfigured) {
    // Read configuration from EEPROM
    readConfigFromEEPROM();
    
    // Try to connect to WiFi
    if (connectToWiFi()) {
      Serial.println("Connected to WiFi, entering normal operation mode");
      
      // Initialize Firebase
      config.api_key = API_KEY;
      config.service_account.data.project_id = PROJECT_ID;
      
      // Configure authentication
      auth.user.email = USER_EMAIL;
      auth.user.password = USER_PASSWORD;
      
      // Assign the callback function for the long running token generation task
      config.token_status_callback = tokenStatusCallback; // This function is defined in TokenHelper.h
      
      // Initialize Firebase with authentication
      Firebase.begin(&config, &auth);
      Firebase.reconnectWiFi(true);
      
      // Sign in to Firebase
      Serial.println("Signing in to Firebase...");
      
      // Verify sign in
      Serial.println("Getting user UID...");
      while (auth.token.uid == "") {
        Serial.print(".");
        delay(1000);
      }
      
      // Print successful authentication
      Serial.println();
      Serial.print("User UID: ");
      Serial.println(auth.token.uid.c_str());
      
      // Configure time
      configTime(0, 0, "pool.ntp.org", "time.nist.gov");
      
      Serial.println("Waiting for time sync...");
      while (time(nullptr) < 1510644967) {
        delay(100);
        Serial.print(".");
      }
      Serial.println("\nTime synchronized!");
      
      // Initialize camera
      setupCamera();
      
      // Setup OTA updates
      setupOTA();
      
      normalOperationMode();
      return;
    } else {
      Serial.println("Failed to connect to saved WiFi, entering setup mode");
      isConfigured = false;
    }
  }
  
  // Enter setup mode
  setupMode();
}

void loop() {
  // This will only run if we're in setup mode
  webServer.handleClient();
  
  // Fast blinking LED in setup mode (100ms on, 100ms off)
  unsigned long currentMillis = millis();
  static unsigned long previousLedMillis = 0;
  
  if (currentMillis - previousLedMillis >= 100) {
    previousLedMillis = currentMillis;
    ledState = !ledState;
    digitalWrite(LED_PIN, ledState ? HIGH : LOW);
  }
  
  // Check if setup mode has timed out
  if (millis() - setupModeStartTime > CONFIG_MODE_TIMEOUT) {
    Serial.println("Setup mode timed out, restarting device");
    ESP.restart();
  }
}

void setupCamera() {
  camera_config_t config;
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = Y2_GPIO_NUM;
  config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;
  config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;
  config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;
  config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk = XCLK_GPIO_NUM;
  config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href = HREF_GPIO_NUM;
  config.pin_sscb_sda = SIOD_GPIO_NUM;
  config.pin_sscb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;
  config.xclk_freq_hz = 20000000;
  config.pixel_format = PIXFORMAT_JPEG;
  
  // Use lower resolution and quality to save memory
  if (psramFound()) {
    config.frame_size = FRAMESIZE_VGA; // 640x480
    config.jpeg_quality = 12;  // 0-63 lower number means higher quality
    config.fb_count = 1;
  } else {
    config.frame_size = FRAMESIZE_CIF; // 352x288
    config.jpeg_quality = 12;
    config.fb_count = 1;
  }
  
  // Camera init
  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("Camera init failed with error 0x%x", err);
    delay(1000);
    ESP.restart();
  }
  
  Serial.println("Camera initialized successfully");
}

bool captureAndSendPhoto() {
  camera_fb_t *fb = NULL;
  bool success = false;
  
  // Take a photo
  Serial.println("Taking a photo...");
  digitalWrite(FLASH_PIN, HIGH);
  fb = esp_camera_fb_get();
  digitalWrite(FLASH_PIN, LOW);
  if (!fb) {
    Serial.println("Camera capture failed");
    return false;
  }
  
  // Image captured successfully
  Serial.printf("Image captured, size: %zu bytes\n", fb->len);
  
  // Create a timestamp for the image
  time_t now;
  time(&now);
  char timestamp[30];
  strftime(timestamp, sizeof(timestamp), "%Y%m%d_%H%M%S", localtime(&now));
  
  // Create a document in Firestore with image metadata only (no image data)
  String documentPath = "devices/" + String(deviceId) + "/images/" + String(timestamp);
  
  content.clear();
  content.set("fields/timestamp/stringValue", String(timestamp));
  content.set("fields/deviceId/stringValue", String(deviceId));
  content.set("fields/deviceName/stringValue", String(deviceName));
  content.set("fields/imageSize/integerValue", String(fb->len));
  content.set("fields/width/integerValue", String(fb->width));
  content.set("fields/height/integerValue", String(fb->height));
  content.set("fields/motionDetected/booleanValue", "true");
  content.set("fields/imageStatus/stringValue", "captured");
  
  // Send metadata to Firestore
  Serial.println("Sending image metadata to Firestore...");
  if (Firebase.Firestore.createDocument(&fbdo, PROJECT_ID, "", documentPath, content.raw())) {
    Serial.println("Image metadata sent to Firestore successfully!");
    
    // Now upload the actual image data to Firebase Storage
    // This is more efficient than storing the base64 in Firestore
    if (Firebase.ready()) {
      // Create a child path for the upload
      String storagePath = "images/" + String(deviceId) + "/" + String(timestamp) + ".jpg";
      
      Serial.println("Uploading image to Firebase Storage...");
      Serial.print("Storage bucket: ");
      Serial.println(STORAGE_BUCKET);
      Serial.print("Storage path: ");
      Serial.println(storagePath);
      
      // For Firebase ESP Client library
      if (Firebase.Storage.upload(&fbdo, STORAGE_BUCKET, 
                                 (uint8_t*)fb->buf, fb->len, 
                                 storagePath.c_str(),
                                 "image/jpeg" /* mime type */,
                                 nullptr /* progress callback */)) {
        Serial.println("Image uploaded successfully");
        
        // Update the document with the storage URL
        content.clear();
        
        // Get the download URL - format may vary based on library version
        String downloadURL = fbdo.downloadURL();
        Serial.print("Download URL: ");
        Serial.println(downloadURL);
        
        content.set("fields/imageUrl/stringValue", downloadURL);
        content.set("fields/imageStatus/stringValue", "uploaded");
        
        if (Firebase.Firestore.patchDocument(&fbdo, PROJECT_ID, "", documentPath, content.raw(), "imageUrl,imageStatus")) {
          Serial.println("Image URL updated in Firestore");
          success = true;
        } else {
          Serial.println("Failed to update image URL in Firestore");
          Serial.println("Reason: " + fbdo.errorReason());
        }
      } else {
        Serial.println("Image upload failed");
        Serial.println("Reason: " + fbdo.errorReason());
      }
    }
  } else {
    Serial.println("Failed to send image metadata to Firestore");
    Serial.println("Reason: " + fbdo.errorReason());
  }
  
  // Return the frame buffer back to the driver for reuse
  esp_camera_fb_return(fb);
  
  return success;
}

void handleMotionDetection() {
  int pirValue = digitalRead(PIR_PIN);
  unsigned long currentMillis = millis();
  
  // Check if motion is detected and cooldown period has passed
  if (pirValue == HIGH && !motionDetected && (currentMillis - lastMotionTime > MOTION_COOLDOWN)) {
    Serial.println("Motion detected!");
    motionDetected = true;
    lastMotionTime = currentMillis;
    
    // Blink LED rapidly to indicate motion detection
    for (int i = 0; i < 5; i++) {
      digitalWrite(LED_PIN, LOW);  // LED on
      delay(100);
      digitalWrite(LED_PIN, HIGH); // LED off
      delay(100);
    }
    
    // Capture and send photo to Firebase
    if (captureAndSendPhoto()) {
      Serial.println("Photo captured and sent successfully");
    } else {
      Serial.println("Failed to capture or send photo");
    }
    
    // Reset motion flag after a short delay
    delay(1000);
    motionDetected = false;
  }
}

void normalOperationMode() {
  Serial.println("Entering normal operation mode");
  
  // Initial state check
  checkDeviceState();
  
  // Main operation loop
  while (true) {
    // Check WiFi connection and reconnect if needed
    if (WiFi.status() != WL_CONNECTED) {
      Serial.println("WiFi connection lost, reconnecting...");
      connectToWiFi();
    }
    
    // Handle OTA updates
    webServer.handleClient();
    
    // Get current time
    unsigned long currentMillis = millis();
    
    // Blink the onboard LED to indicate normal operation
    // LED ON for 1 second, OFF for 2 seconds
    if (currentMillis - lastLedToggleTime >= (ledState == LOW ? 1000 : 2000)) {
      lastLedToggleTime = currentMillis;
      ledState = (ledState == LOW) ? HIGH : LOW;
      digitalWrite(LED_PIN, ledState);
    }
    
    // Check for device state changes in Firebase
    if (currentMillis - lastStateCheckTime >= STATE_CHECK_INTERVAL) {
      lastStateCheckTime = currentMillis;
      checkDeviceState();
    }
    
    // Send status update periodically (every 30 seconds)
    static unsigned long lastStatusUpdateTime = 0;
    if (currentMillis - lastStatusUpdateTime >= 30000) {
      lastStatusUpdateTime = currentMillis;
      sendStatusUpdate();
    }
    
    // Check for firmware updates in Firebase
    static unsigned long lastUpdateCheckTime = 0;
    if (currentMillis - lastUpdateCheckTime >= 300000) { // 5 minutes
      lastUpdateCheckTime = currentMillis;
      checkForFirmwareUpdates();
    }
    
    // Handle motion detection
    handleMotionDetection();
    
    // Allow the ESP to handle other tasks
    yield();
  }
}

void setupMode() {
  Serial.println("Entering setup mode");
  setupModeStartTime = millis();
  
  // Start AP with a simple name
  WiFi.mode(WIFI_AP);
  WiFi.softAP("ESP32-CAM-Setup");
  
  Serial.print("AP IP: ");
  Serial.println(WiFi.softAPIP());
  
  // Setup web server
  webServer.on("/", handleRoot);
  webServer.on("/configure", handleConfigure);
  webServer.on("/update", HTTP_GET, []() {
    webServer.sendHeader("Connection", "close");
    webServer.send(200, "text/html", 
      "<html><body><form method='POST' action='/update' enctype='multipart/form-data'>"
      "<input type='file' name='update'><input type='submit' value='Update'></form></body></html>");
  });
  webServer.onNotFound(handleRoot);
  
  webServer.begin();
  
  Serial.println("Setup mode active");
}

void handleRoot() {
  String html = "<html><head><meta name='viewport' content='width=device-width, initial-scale=1'></head><body>";
  html += "<h1>Camera Setup</h1>";
  html += "<form action='/configure' method='post'>";
  html += "<label>WiFi Network:</label><br>";
  html += "<select name='ssid'>";

  int n = WiFi.scanNetworks();
  for (int i = 0; i < n && i < 10; ++i) { // Limit to 10 networks to save memory
    html += "<option value='" + WiFi.SSID(i) + "'>" + WiFi.SSID(i) + "</option>";
  }

  html += "</select><br>";
  html += "<label>Password:</label><br>";
  html += "<input type='password' name='password'><br>";
  html += "<input type='submit' value='Connect'>";
  html += "</form>";
  html += "<p><a href='/update'>Update Firmware</a></p>";
  html += "</body></html>";

  webServer.send(200, "text/html", html);
}



void handleConfigure() {
  if (webServer.method() != HTTP_POST) {
    webServer.send(405, "text/plain", "Method Not Allowed");
    return;
  }
  
  String ssid = webServer.arg("ssid");
  String password = webServer.arg("password");
  
  if (ssid.length() == 0 || password.length() == 0) {
    webServer.send(400, "text/plain", "Missing required fields");
    return;
  }
  
  // Store WiFi credentials
  ssid.toCharArray(wifiSSID, sizeof(wifiSSID));
  password.toCharArray(wifiPassword, sizeof(wifiPassword));
  
  // Generate device ID from chip ID
  String chipIdStr = String((uint32_t)(ESP.getEfuseMac() >> 32));
  chipIdStr.toCharArray(deviceId, sizeof(deviceId));
  
  // Send confirmation page
  String html = "<html><body><h1>Connecting to WiFi</h1>";
  html += "<p>Device is connecting to " + ssid + "</p>";
  html += "<p>The device will restart if connection is successful.</p></body></html>";
  webServer.send(200, "text/html", html);
  
  // Wait a moment for the response to be sent
  delay(1000);
  
  // Try to connect to the provided WiFi
  WiFi.mode(WIFI_STA);
  WiFi.begin(wifiSSID, wifiPassword);
  
  Serial.println("Connecting to WiFi...");
  
  // Wait up to 20 seconds for connection
  int timeout = 20;
  while (WiFi.status() != WL_CONNECTED && timeout > 0) {
    delay(1000);
    Serial.print(".");
    timeout--;
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("Connected to WiFi!");
    
    // Save configuration to EEPROM
    saveConfigToEEPROM();
    
    // Set configured flag
    EEPROM.write(EEPROM_CONFIG_FLAG_ADDR, 1);
    EEPROM.commit();
    
    // Restart the device to apply new configuration
    ESP.restart();
  } else {
    Serial.println("Failed to connect to WiFi");
    // Stay in setup mode
  }
}

void readConfigFromEEPROM() {
  Serial.println("Reading configuration from EEPROM");
  
  // Read WiFi SSID
  for (int i = 0; i < 32; i++) {
    wifiSSID[i] = EEPROM.read(EEPROM_WIFI_SSID_ADDR + i);
  }
  
  // Read WiFi password
  for (int i = 0; i < 32; i++) {
    wifiPassword[i] = EEPROM.read(EEPROM_WIFI_PASS_ADDR + i);
  }
  
  // Read device name
  for (int i = 0; i < 32; i++) {
    deviceName[i] = EEPROM.read(EEPROM_DEVICE_NAME_ADDR + i);
  }
  
  // Generate device ID from chip ID (not stored in EEPROM)
  String chipIdStr = String((uint32_t)(ESP.getEfuseMac() >> 32));
  chipIdStr.toCharArray(deviceId, sizeof(deviceId));
  
  Serial.println("Configuration read from EEPROM:");
  Serial.print("WiFi SSID: ");
  Serial.println(wifiSSID);
  Serial.print("Device Name: ");
  Serial.println(deviceName);
  Serial.print("Device ID: ");
  Serial.println(deviceId);
}

void saveConfigToEEPROM() {
  Serial.println("Saving configuration to EEPROM");
  
  // Save WiFi SSID
  for (int i = 0; i < 32; i++) {
    EEPROM.write(EEPROM_WIFI_SSID_ADDR + i, wifiSSID[i]);
  }
  
  // Save WiFi password
  for (int i = 0; i < 32; i++) {
    EEPROM.write(EEPROM_WIFI_PASS_ADDR + i, wifiPassword[i]);
  }
  
  // Save device name (if empty, use "Camera-" + last 4 digits of chip ID)
  if (strlen(deviceName) == 0) {
    String defaultName = "Camera-" + String((uint32_t)(ESP.getEfuseMac() & 0xFFFF), HEX);
    defaultName.toCharArray(deviceName, sizeof(deviceName));
  }
  
  for (int i = 0; i < 32; i++) {
    EEPROM.write(EEPROM_DEVICE_NAME_ADDR + i, deviceName[i]);
  }
  
  // Set configured flag
  EEPROM.write(EEPROM_CONFIG_FLAG_ADDR, 1);
  
  // Commit changes to EEPROM
  EEPROM.commit();
  
  Serial.println("Configuration saved to EEPROM");
}

bool connectToWiFi() {
  Serial.print("Connecting to WiFi SSID: ");
  Serial.println(wifiSSID);
  
  WiFi.mode(WIFI_STA);
  WiFi.begin(wifiSSID, wifiPassword);
  
  // Wait for connection, timeout after 20 seconds
  int timeout = 20;
  while (WiFi.status() != WL_CONNECTED && timeout > 0) {
    delay(1000);
    Serial.print(".");
    timeout--;
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("");
    Serial.print("Connected to WiFi. IP address: ");
    Serial.println(WiFi.localIP());
    return true;
  } else {
    Serial.println("");
    Serial.println("Failed to connect to WiFi");
    return false;
  }
}

void setupOTA() {
  // Set up mDNS responder
  String hostname = "skynet-camera-" + String((uint32_t)(ESP.getEfuseMac() & 0xFFFF), HEX);
  if (MDNS.begin(hostname.c_str())) {
    Serial.println("mDNS responder started");
    Serial.print("Device can be reached at: ");
    Serial.print(hostname);
    Serial.println(".local");
  }
  
  // Set up HTTP server for OTA updates
  webServer.on("/update", HTTP_GET, []() {
    webServer.sendHeader("Connection", "close");
    webServer.send(200, "text/html", 
      "<html><body><form method='POST' action='/update' enctype='multipart/form-data'>"
      "<input type='file' name='update'><input type='submit' value='Update'></form></body></html>");
  });
  
  webServer.on("/update", HTTP_POST, []() {
    webServer.sendHeader("Connection", "close");
    webServer.send(200, "text/plain", (Update.hasError()) ? "Update failed!" : "Update successful! Rebooting...");
    delay(1000);
    ESP.restart();
  }, []() {
    HTTPUpload& upload = webServer.upload();
    if (upload.status == UPLOAD_FILE_START) {
      Serial.printf("Update: %s\n", upload.filename.c_str());
      if (!Update.begin(UPDATE_SIZE_UNKNOWN)) {
        Update.printError(Serial);
      }
    } else if (upload.status == UPLOAD_FILE_WRITE) {
      if (Update.write(upload.buf, upload.currentSize) != upload.currentSize) {
        Update.printError(Serial);
      }
    } else if (upload.status == UPLOAD_FILE_END) {
      if (Update.end(true)) {
        Serial.printf("Update Success: %u\n", upload.totalSize);
      } else {
        Update.printError(Serial);
      }
    }
  });
}

void checkDeviceState() {
  Serial.println("Checking device state in Firestore...");
  
  // Document path in Firestore
  String documentPath = "devices/" + String(deviceId);
  
  // Check if Firebase is ready
  if (Firebase.ready()) {
    // Get the document from Firestore
    if (Firebase.Firestore.getDocument(&fbdo, PROJECT_ID, "", documentPath, "")) {
      Serial.println("Got document from Firestore");
      
      // Parse the response
      FirebaseJson payload;
      payload.setJsonData(fbdo.payload().c_str());
      
      // Check if document exists
      FirebaseJsonData jsonData;
      payload.get(jsonData, "fields", true);
      
      if (jsonData.success) {
        // Document exists, check for device name
        payload.get(jsonData, "fields/name/stringValue");
        if (jsonData.success && jsonData.stringValue.length() > 0) {
          // Update device name if different
          if (strcmp(deviceName, jsonData.stringValue.c_str()) != 0) {
            Serial.print("Updating device name from ");
            Serial.print(deviceName);
            Serial.print(" to ");
            Serial.println(jsonData.stringValue.c_str());
            
            // Update device name
            jsonData.stringValue.toCharArray(deviceName, sizeof(deviceName));
            
            // Save to EEPROM
            for (int i = 0; i < 32; i++) {
              EEPROM.write(EEPROM_DEVICE_NAME_ADDR + i, deviceName[i]);
            }
            EEPROM.commit();
          }
        }
      } else {
        // Document doesn't exist, create it
        Serial.println("Device document not found, creating initial document");
        createInitialDocument();
      }
    } else {
      Serial.println("Failed to get document from Firestore");
      Serial.println("Reason: " + fbdo.errorReason());
      
      // If document doesn't exist, create it
      if (fbdo.errorReason().indexOf("NOT_FOUND") >= 0) {
        Serial.println("Creating initial document");
        createInitialDocument();
      }
    }
  } else {
    Serial.println("Firebase not ready");
  }
}

void createInitialDocument() {
  // Document path in Firestore
  String documentPath = "devices/" + String(deviceId);
  
  // Create JSON content for the document
  content.clear();
  content.set("fields/deviceId/stringValue", String(deviceId));
  content.set("fields/name/stringValue", String(deviceName));
  content.set("fields/type/stringValue", "camera");
  content.set("fields/firmware/stringValue", FIRMWARE_VERSION);
  content.set("fields/ip/stringValue", WiFi.localIP().toString());
  content.set("fields/mac/stringValue", WiFi.macAddress());
  content.set("fields/lastSeen/timestampValue", getISOTimestamp());
  content.set("fields/status/stringValue", "online");
  
  // Create the document in Firestore
  if (Firebase.Firestore.createDocument(&fbdo, PROJECT_ID, "", documentPath, content.raw())) {
    Serial.println("Initial document created successfully");
  } else {
    Serial.println("Failed to create initial document");
    Serial.println("Reason: " + fbdo.errorReason());
  }
}

void sendStatusUpdate() {
  // Document path in Firestore
  String documentPath = "devices/" + String(deviceId);
  
  // Create JSON content for the update
  content.clear();
  content.set("fields/lastSeen/timestampValue", getISOTimestamp());
  content.set("fields/status/stringValue", "online");
  content.set("fields/ip/stringValue", WiFi.localIP().toString());
  
  // Update the document in Firestore
  if (Firebase.Firestore.patchDocument(&fbdo, PROJECT_ID, "", documentPath, content.raw(), "lastSeen,status,ip")) {
    Serial.println("Status update sent successfully");
  } else {
    Serial.println("Failed to send status update");
    Serial.println("Reason: " + fbdo.errorReason());
  }
}

void checkForFirmwareUpdates() {
  Serial.println("Checking for firmware updates...");
  
  // Document path in Firestore
  String documentPath = "firmware/latest";
  
  // Check if Firebase is ready
  if (Firebase.ready()) {
    // Get the document from Firestore
    if (Firebase.Firestore.getDocument(&fbdo, PROJECT_ID, "", documentPath, "")) {
      // Parse the response
      FirebaseJson payload;
      payload.setJsonData(fbdo.payload().c_str());
      
      // Get firmware version
      FirebaseJsonData jsonData;
      payload.get(jsonData, "fields/version/stringValue");
      
      if (jsonData.success) {
        String latestVersion = jsonData.stringValue;
        Serial.print("Latest firmware version: ");
        Serial.println(latestVersion);
        
        // Compare with current version
        if (latestVersion != FIRMWARE_VERSION) {
          Serial.println("New firmware version available!");
          
          // Update firmware status in device document
          String devicePath = "devices/" + String(deviceId);
          content.clear();
          content.set("fields/firmware/stringValue", FIRMWARE_VERSION);
          content.set("fields/firmwareStatus/stringValue", "update_available");
          
          Firebase.Firestore.patchDocument(&fbdo, PROJECT_ID, "", devicePath, 
                                          content.raw(), "firmware,firmwareStatus");
        }
      }
    }
  }
}

String getISOTimestamp() {
  time_t now;
  time(&now);
  char buf[sizeof "2011-10-08T07:07:09Z"];
  strftime(buf, sizeof buf, "%Y-%m-%dT%H:%M:%SZ", gmtime(&now));
  return String(buf);
}