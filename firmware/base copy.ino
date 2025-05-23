#include <ESP8266WiFi.h>
#include <ESP8266WebServer.h>
#include <ESP8266HTTPClient.h>
#include <ArduinoJson.h>      // For JSON parsing
#include <EEPROM.h>
#include <Firebase_ESP_Client.h>  // New Firebase library with Firestore support
#include <time.h>             // For time functions
#include <addons/TokenHelper.h>  // Firebase token generation helper
#include <addons/RTDBHelper.h>   // RTDB helper functions
#include <ESP8266HTTPUpdateServer.h> // For OTA updates via web interface
#include <ESP8266mDNS.h>      // For OTA service discovery
#include <ESP8266httpUpdate.h>  // For HTTP-based OTA updates

// Function Declarations
void readConfigFromEEPROM();
bool connectToWiFi();
void setupOTA();
void normalOperationMode();
void handleConfigure();
void saveConfigToEEPROM();
void checkDeviceState();
void createInitialDocument();
void updateSwitchState();
void handleOTAPage();
void checkForFirmwareUpdates();
void performAutomaticUpdate(String url, String version, String md5);
void handleResetPage();



// Constants
#define FIRMWARE_VERSION "1.0.8"  // Current firmware version
#define SWITCH_PIN 0
#define LED_PIN 2  // Onboard LED on ESP8266
#define CONFIG_MODE_TIMEOUT 300000  // 5 minutes in milliseconds
#define EEPROM_SIZE 512
#define EEPROM_WIFI_SSID_ADDR 0
#define EEPROM_WIFI_PASS_ADDR 32
#define EEPROM_API_KEY_ADDR 96
#define EEPROM_DEVICE_NAME_ADDR 160  // Re-enable device name storage
// Device ID no longer stored in EEPROM
#define EEPROM_CONFIG_FLAG_ADDR 288  // Flag to indicate if device is configured
#define EEPROM_UPDATE_FLAG_ADDR 289  // Flag to indicate if device just completed an update

// Firebase configuration
#define API_KEY "AIzaSyA-UDYSkC6FhyN84yBTGy91EiMamiZmcK0"  // Replace with your Firebase API Key
#define PROJECT_ID "skynet-17582"  // Replace with your Firebase Project ID
#define USER_EMAIL "master@skynet.com"  // Replace with your Firebase Auth email
#define USER_PASSWORD "password"  // Replace with your Firebase Auth password

// Function declarations
void sendStatusUpdate();
void updateFirmwareStatus(String status, String availableVersion);
void updateFirmwareStatusWithTimestamp(String status, String availableVersion);
void updateFirmwareStatusWithError(String errorMsg, String availableVersion);
void checkDeviceNameInFirebase();  // New function to check for name changes

// Variables
bool isConfigured = false;
char deviceName[32] = "";
char deviceId[40] = "";  // Store device ID instead of API key
char wifiSSID[32] = "";
char wifiPassword[32] = "";
unsigned long setupModeStartTime = 0;
bool currentState = false;  // Current state of the switch (ON/OFF)
unsigned long lastStateCheckTime = 0;
const unsigned long STATE_CHECK_INTERVAL = 5000;  // Check state every 5 seconds

// Firebase objects
FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;
FirebaseJson content;

// DNS Server for captive portal
const byte DNS_PORT = 53;

// Web webServer for configuration portal
ESP8266WebServer webServer(80);

// OTA update webServer
ESP8266HTTPUpdateServer httpUpdater;
const char* OTA_USERNAME = "admin";  // Username for OTA updates
const char* OTA_PASSWORD = "admin";  // Password for OTA updates
bool otaEnabled = false;             // Flag to indicate if OTA is enabled

// Auto update configuration
bool autoUpdateEnabled = true;       // Default value, will be read from EEPROM
#define AUTO_UPDATE_CHECK_INTERVAL 60000  // Check for updates every 5 minutes
unsigned long lastAutoUpdateCheck = 0;
bool updateInProgress = false;       // Flag to prevent multiple update attempts
bool justUpdated = false;           // Flag to indicate device just completed an update

// LED blinking variables
unsigned long lastLedToggleTime = 0;
bool ledState = HIGH;               // LED is active LOW on ESP8266

// EEPROM backup area - used to preserve settings during OTA updates
#define EEPROM_BACKUP_ADDR 350
#define EEPROM_BACKUP_SIZE 128  // Enough to store WiFi credentials and device name

// Function to backup important EEPROM data before OTA update
void setup() {
  Serial.begin(115200);
  pinMode(SWITCH_PIN, OUTPUT);
  digitalWrite(SWITCH_PIN, HIGH);  // Initialize switch to OFF
  
  // Initialize LED pin
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, HIGH);    // Turn LED off initially (active LOW)
  
  // Initialize EEPROM
  EEPROM.begin(EEPROM_SIZE);
  
  // Check if we're coming back from an update
  if (EEPROM.read(EEPROM_UPDATE_FLAG_ADDR) == 1) {
    Serial.println("Detected post-update boot");
    restoreEEPROMSettings();
    
    // Set a flag to update the firmware status once connected
    justUpdated = true;
  }
  
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
      
      // Note: Timeout settings are handled internally by the library in this version
      
      // Configure time
      configTime(0, 0, "pool.ntp.org", "time.nist.gov");
      
      // If we just completed an update, update the firmware status
      if (justUpdated) {
        Serial.println("Device just completed an update, updating status...");
        updateFirmwareStatusWithTimestamp("updated", FIRMWARE_VERSION);
        justUpdated = false;
      }
      Serial.println("Waiting for time sync...");
      while (time(nullptr) < 1510644967) {
        delay(100);
        Serial.print(".");
      }
      Serial.println("\nTime synchronized!");
      
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
  // dnsServer.processNextRequest();
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

void setupMode() {
  Serial.println("Entering setup mode");
  setupModeStartTime = millis();
  
  // Create unique AP name
  String apName = "SkyNet-AutoConnect";
  
  // Start AP
  WiFi.mode(WIFI_AP);
  WiFi.softAP(apName.c_str());
  
  // Configure DNS webServer to redirect all requests to the ESP
  IPAddress apIP = WiFi.softAPIP();
  Serial.print("AP IP address: ");
  Serial.println(apIP);
  //   
  // Setup web webServer
  webServer.on("/", handleRoot);
  webServer.on("/configure", handleConfigure);
  webServer.on("/cid", handleCID);
  webServer.on("/ota_setup", handleOTASetupPage);
  webServer.onNotFound(handleRoot);
  webServer.on("/reset", HTTP_GET, handleResetPage);
  webServer.on("/do_reset", HTTP_POST, handleDoReset);

  
  // Setup OTA update webServer in setup mode too
  httpUpdater.setup(&webServer, "/update", OTA_USERNAME, OTA_PASSWORD);
  
  webServer.begin();
  
  Serial.println("Setup mode active. Connect to WiFi: " + apName);
  
  // Start fast blinking LED to indicate setup mode
  // This will be handled in the loop function
}

void handleCID() {
  String wifiMAC = WiFi.macAddress();
  String cID = String(ESP.getChipId()).c_str();
  webServer.send(200, "text/html", cID);
}

void handleOTASetupPage() {
  String html = "<!DOCTYPE html><html><head><meta name='viewport' content='width=device-width, initial-scale=1'>";
  html += "<style>body{font-family:Arial;margin:0;padding:20px;text-align:center;}";
  html += "button{background-color:#4CAF50;color:white;padding:10px;border:none;cursor:pointer;width:100%;margin-top:20px;}";
  html += "</style></head><body>";
  html += "<h1>OTA Update - Setup Mode</h1>";
  html += "<p>Device ID: " + String(ESP.getChipId()) + "</p>";
  html += "<p>Firmware Version: " + String(FIRMWARE_VERSION) + "</p>";
  html += "<a href='/update'><button>Go to Update Page</button></a>";
  html += "<a href='/'><button style='background-color:#2196F3;'>Back to Setup</button></a>";
  html += "</body></html>";
  
  webServer.send(200, "text/html", html);
}

void handleRoot() {
  String html = "<!DOCTYPE html><html><head><meta name='viewport' content='width=device-width, initial-scale=1'>";
  html += "<style>body{font-family:Arial;margin:0;padding:20px;text-align:center;}";
  html += "input,select{width:100%;padding:10px;margin:10px 0;box-sizing:border-box;}";
  html += "button{background-color:#4CAF50;color:white;padding:10px;border:none;cursor:pointer;width:100%;}";
  html += "</style>";
  html += "<script>";
  html += "document.addEventListener('DOMContentLoaded', () => {";
  html += "  document.getElementById('wifiForm').addEventListener('submit', function(e) {";
  html += "    e.preventDefault();";
  html += "    const ssid = document.getElementById('ssid').value;";
  html += "    const pwd = document.getElementById('password').value;";
  html += "    fetch('/configure', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({ssid:ssid, password:pwd})})";
  html += "      .then(response => response.text())";
  html += "      .then(data => {";
  html += "        if (window.ResponseChannel) ResponseChannel.postMessage(data);";
  html += "        alert('Saved: Rebooting your Device');";
  html += "      });";
  html += "  });";
  html += "});";
  html += "</script></head><body>";
  html += "<h1>Switch Setup</h1>";
  html += "<form id='wifiForm'>";
  html += "<label for='ssid'>WiFi Network:</label><br>";
  html += "<select id='ssid' name='ssid' required>";

  int n = WiFi.scanNetworks();
  for (int i = 0; i < n; ++i) {
    html += "<option value='" + WiFi.SSID(i) + "'>" + WiFi.SSID(i) + " (" + WiFi.RSSI(i) + "dBm)</option>";
  }

  html += "</select><br>";
  html += "<label for='password'>WiFi Password:</label><br>";
  html += "<input type='password' id='password' name='password' required><br>";
  html += "<p>Device ID: " + String(ESP.getChipId()) + "</p>";
  html += "<button type='submit'>Connect</button>";
  html += "</form>";
  html += "<p>Firmware Version: " + String(FIRMWARE_VERSION) + "</p>";
  html += "<p><a href='/ota_setup'>Update Firmware</a></p>";
    html += "<p><a href='/reset'>Update WiFi</a></p>";
  html += "</body></html>";

  webServer.send(200, "text/html", html);
}


void handleConfigure() {
  if (webServer.method() != HTTP_POST) {
    webServer.send(405, "text/plain", "Method Not Allowed");
    return;
  }
  
  StaticJsonDocument<256> json;
  deserializeJson(json, webServer.arg("plain"));
  String ssid = json["ssid"];
  String password = json["password"];
  
  if (ssid.length() == 0 || password.length() == 0) {
    webServer.send(400, "text/plain", "Missing required fields");
    return;
  }
  
  // Store WiFi credentials
  ssid.toCharArray(wifiSSID, sizeof(wifiSSID));
  password.toCharArray(wifiPassword, sizeof(wifiPassword));
  
  // Generate device ID from chip ID (not stored in EEPROM)
  String chipIdStr = String(ESP.getChipId());
  chipIdStr.toCharArray(deviceId, sizeof(deviceId));
  
  // Send confirmation page
  StaticJsonDocument<128> resDoc;
  resDoc["status"] = "success";
  resDoc["message"] = "Rebooting to connect...";
  resDoc["chipID"] = chipIdStr ;
  String response;
  serializeJson(resDoc, response);
  webServer.send(200, "application/json", response);
  
  // Wait a moment for the response to be sent
  delay(1000);
  
  // Try to connect to the provided WiFi
  WiFi.mode(WIFI_STA);
  WiFi.begin(wifiSSID, wifiPassword);
  
  Serial.println("Connecting to WiFi...");
  
  // Wait up to 30 seconds for connection
  int timeout = 30;
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
    
    isConfigured = true;
    
    // Wait a moment before restarting
    delay(2000);
    ESP.restart();
  } else {
    Serial.println("Failed to connect to WiFi");
    // We'll continue in setup mode
  }
}

void saveConfigToEEPROM() {
  // Save WiFi credentials
  for (int i = 0; i < sizeof(wifiSSID); i++) {
    EEPROM.write(EEPROM_WIFI_SSID_ADDR + i, wifiSSID[i]);
  }
  
  for (int i = 0; i < sizeof(wifiPassword); i++) {
    EEPROM.write(EEPROM_WIFI_PASS_ADDR + i, wifiPassword[i]);
  }
  
  // Save device name to EEPROM
  for (int i = 0; i < sizeof(deviceName); i++) {
    EEPROM.write(EEPROM_DEVICE_NAME_ADDR + i, deviceName[i]);
  }
  
  // Device ID is not saved to EEPROM
  // It will be generated dynamically when needed
  
  EEPROM.commit();
  Serial.println("Configuration saved to EEPROM");
}

void readConfigFromEEPROM() {
  // Read WiFi credentials
  for (int i = 0; i < sizeof(wifiSSID); i++) {
    wifiSSID[i] = EEPROM.read(EEPROM_WIFI_SSID_ADDR + i);
  }
  
  for (int i = 0; i < sizeof(wifiPassword); i++) {
    wifiPassword[i] = EEPROM.read(EEPROM_WIFI_PASS_ADDR + i);
  }
  
  // Generate device ID from chip ID
  String chipIdStr = String(ESP.getChipId());
  chipIdStr.toCharArray(deviceId, sizeof(deviceId));
  
  // Read device name from EEPROM
  bool hasStoredName = false;
  for (int i = 0; i < sizeof(deviceName); i++) {
    deviceName[i] = EEPROM.read(EEPROM_DEVICE_NAME_ADDR + i);
    // Check if we have a valid stored name (first byte not 0 or 255)
    if (i == 0 && deviceName[0] != 0 && deviceName[0] != 255) {
      hasStoredName = true;
    }
  }
  
  // If no valid name in EEPROM, generate default name
  if (!hasStoredName) {
    String defaultName = "Switch_" + chipIdStr;
    defaultName.toCharArray(deviceName, sizeof(deviceName));
    Serial.println("No valid name in EEPROM, using default name");
  }
  
  Serial.println("Configuration loaded from EEPROM");
  Serial.print("SSID: ");
  Serial.println(wifiSSID);
  Serial.print("Device Name: ");
  Serial.println(deviceName);
  Serial.print("Device ID (from chip): ");
  Serial.println(deviceId);
}

bool connectToWiFi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(wifiSSID, wifiPassword);
  
  Serial.print("Connecting to WiFi...");
  
  // Wait up to 20 seconds for connection
  int timeout = 20;
  while (WiFi.status() != WL_CONNECTED && timeout > 0) {
    delay(1000);
    Serial.print(".");
    timeout--;
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("Connected!");
    Serial.print("IP address: ");
    Serial.println(WiFi.localIP());
    return true;
  } else {
    Serial.println("Failed to connect");
    return false;
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
      
      // Re-setup OTA if WiFi reconnected
      if (WiFi.status() == WL_CONNECTED) {
        setupOTA();
      }
    }
    
    // Handle OTA updates if enabled
    if (otaEnabled) {
      webServer.handleClient();
      MDNS.update();
    }
    
    // Get current time
    unsigned long currentMillis = millis();
    
    // Blink the onboard LED according to the specified pattern
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
    if (currentMillis - lastAutoUpdateCheck >= AUTO_UPDATE_CHECK_INTERVAL) {
      lastAutoUpdateCheck = currentMillis;
      checkForFirmwareUpdates();
    }
    
    // Check for device name changes in Firebase (every 5 minutes)
    static unsigned long lastNameCheckTime = 0;
    if (currentMillis - lastNameCheckTime >= 300000) { // 5 minutes
      lastNameCheckTime = currentMillis;
      checkDeviceNameInFirebase();
    }
    
    // Allow the ESP to handle other tasks
    yield();
  }
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
      
      // Parse the JSON response
      FirebaseJson payload;
      payload.setJsonData(fbdo.payload().c_str());
      
      // Extract the state field
      FirebaseJsonData result;
      payload.get(result, "fields/state/booleanValue");
      
      if (result.success) {
        // Convert the string "true" or "false" to a boolean
        bool newState = (result.stringValue == "true");
        Serial.print("Current state in Firestore: ");
        Serial.println(newState ? "ON" : "OFF");
        
        // Update the switch if state has changed
        if (newState != currentState) {
          currentState = newState;
          updateSwitchState();
        }
      } else {
        Serial.println("Document doesn't have a state field, creating it...");
        createInitialDocument();
      }
    } else {
      Serial.print("Failed to get document from Firestore: ");
      Serial.println(fbdo.errorReason());
      
      // If document doesn't exist, create it
      if (fbdo.errorReason().indexOf("NOT_FOUND") >= 0) {
        Serial.println("Document not found, creating it...");
        createInitialDocument();
      }
    }
  } else {
    Serial.println("Firebase is not ready, waiting for authentication...");
    delay(1000);
  }
}

void createInitialDocument() {
  Serial.println("Creating initial device document in Firestore...");
  
  // Document path in Firestore
  String documentPath = "devices/" + String(deviceId);
  
  // Create the document data
  content.clear();
  content.set("fields/state/booleanValue", false);
  content.set("fields/status/stringValue", "online");
  content.set("fields/ipAddress/stringValue", WiFi.localIP().toString());
  content.set("fields/lastActive/integerValue", String(time(nullptr)));
  content.set("fields/name/stringValue", String(deviceName));
  content.set("fields/firmware/mapValue/fields/currentVersion/stringValue", FIRMWARE_VERSION);
  content.set("fields/firmware/mapValue/fields/status/stringValue", "up_to_date");
  content.set("fields/firmware/mapValue/fields/autoUpdateEnabled/booleanValue", autoUpdateEnabled);
  
  if (Firebase.Firestore.createDocument(&fbdo, PROJECT_ID, "", documentPath, content.raw())) {
    Serial.println("Initial document created successfully");
    currentState = false;
    updateSwitchState();
  } else {
    Serial.print("Failed to create initial document: ");
    Serial.println(fbdo.errorReason());
  }
}

void updateSwitchState() {
  Serial.print("Updating switch to: ");
  Serial.println(currentState ? "ON" : "OFF");
  
  // Set the pin HIGH or LOW based on the state
  digitalWrite(SWITCH_PIN, currentState ? LOW : HIGH);
}

void setupOTA() {
  // Set up mDNS responder
  String hostname = "skynet-" + String(deviceId);
  if (MDNS.begin(hostname.c_str())) {
    Serial.println("mDNS responder started: " + hostname);
    // Add service to mDNS
    MDNS.addService("http", "tcp", 80);
  } else {
    Serial.println("Error setting up mDNS responder!");
  }
  
  // Set up HTTP OTA update webServer
  httpUpdater.setup(&webServer, "/update", OTA_USERNAME, OTA_PASSWORD);
  
  // Add route for OTA page
  webServer.on("/ota", HTTP_GET, handleOTAPage);
  webServer.on("/reset", HTTP_GET, handleResetPage);
  webServer.on("/do_reset", HTTP_POST, handleDoReset);
  
  // Start web webServer for OTA updates
  webServer.begin();
  Serial.println("HTTP OTA update webServer started");
  Serial.println("OTA URL: http://" + WiFi.localIP().toString() + "/update");
  
  otaEnabled = true;
}

void handleOTAPage() {
  String html = "<!DOCTYPE html><html><head><meta name='viewport' content='width=device-width, initial-scale=1'>";
  html += "<style>body{font-family:Arial;margin:0;padding:20px;text-align:center;}";
  html += "button{background-color:#4CAF50;color:white;padding:10px;border:none;cursor:pointer;width:100%;margin-top:20px;}";
  html += "</style></head><body>";
  html += "<h1>OTA Update Status</h1>";
  html += "<p>Device ID: " + String(deviceId) + "</p>";
  html += "<p>Device Name: " + String(deviceName) + "</p>";
  html += "<p>IP Address: " + WiFi.localIP().toString() + "</p>";
  html += "<p>Firmware Version: " + String(FIRMWARE_VERSION) + "</p>";
  
  // Show auto-update status (controlled from app)
  html += "<p>Automatic Updates: " + String(autoUpdateEnabled ? "Enabled" : "Disabled") + "</p>";
  html += "<p><small>Auto-update setting is controlled from the app</small></p>";
  
  html += "<a href='/update'><button>Go to Update Page</button></a>";
  html += "<p style='margin-top:20px;font-size:0.8em;'>Last update check: " + (lastAutoUpdateCheck > 0 ? String((millis() - lastAutoUpdateCheck) / 1000) + " seconds ago" : "Never") + "</p>";
  html += "</body></html>";
  
  webServer.send(200, "text/html", html);
}

void handleResetPage() {
  String html = "<!DOCTYPE html><html><head><meta name='viewport' content='width=device-width, initial-scale=1'>";
  html += "<style>body{font-family:Arial;padding:20px;text-align:center;}button{padding:10px 20px;background-color:#f44336;color:white;border:none;border-radius:5px;font-size:16px;cursor:pointer;}button:hover{background-color:#d32f2f;}</style>";
  html += "<script>function resetDevice() { fetch('/do_reset', { method: 'POST' }).then(() => { alert('Device will reboot'); }); }</script>";
  html += "</head><body><h2>Reset WiFi Settings</h2><button onclick='resetDevice()'>Reset WiFi Configuration</button></body></html>";

  webServer.send(200, "text/html", html);
}

void handleDoReset() {
  for (int i = 0; i < 96; i++) {
    EEPROM.write(i, 0); // Clear all saved config
  }
  EEPROM.commit();

  webServer.send(200, "text/plain", "Resetting...");

  delay(1000);
  ESP.restart();
}


// handleToggleAutoUpdate function removed - auto-update is now controlled from the app via Firestore

void checkForFirmwareUpdates() {
  Serial.println("Checking for firmware updates in Firestore...");
  
  // Check if Firebase is ready
  if (!Firebase.ready()) {
    Serial.println("Firebase is not ready, skipping firmware check");
    return;
  }
  
  // Don't check if an update is already in progress
  if (updateInProgress) {
    Serial.println("Update already in progress, skipping check");
    return;
  }
  
  // First, check if auto-updates are enabled for this device
  String deviceDocPath = "devices/" + String(deviceId);
  bool shouldAutoUpdate = false;
  
  if (Firebase.Firestore.getDocument(&fbdo, PROJECT_ID, "", deviceDocPath, "")) {
    // Parse the JSON response
    FirebaseJson deviceDoc;
    deviceDoc.setJsonData(fbdo.payload().c_str());
    
    // Extract the auto-update setting
    FirebaseJsonData autoUpdateResult;
    deviceDoc.get(autoUpdateResult, "fields/firmware/mapValue/fields/autoUpdateEnabled/booleanValue");
    
    if (autoUpdateResult.success) {
      shouldAutoUpdate = (autoUpdateResult.stringValue == "true");
      autoUpdateEnabled = shouldAutoUpdate; // Update the local variable for UI
      Serial.print("Auto-update setting from Firestore: ");
      Serial.println(shouldAutoUpdate ? "Enabled" : "Disabled");
    } else {
      Serial.println("Auto-update setting not found in device document, using default");
      shouldAutoUpdate = autoUpdateEnabled; // Use the current value
    }
  } else {
    Serial.print("Failed to get device document: ");
    Serial.println(fbdo.errorReason());
    shouldAutoUpdate = autoUpdateEnabled; // Use the current value
  }
  
  // Document path in Firestore for firmware
  String documentPath = "firmware/latest";
  
  // Get the document from Firestore
  if (Firebase.Firestore.getDocument(&fbdo, PROJECT_ID, "", documentPath, "")) {
    Serial.println("Got firmware document from Firestore");
    
    // Parse the JSON response
    FirebaseJson payload;
    payload.setJsonData(fbdo.payload().c_str());
    
    // Extract the version field
    FirebaseJsonData versionResult;
    payload.get(versionResult, "fields/version/stringValue");
    
    if (versionResult.success) {
      String latestVersion = versionResult.stringValue;
      Serial.print("Latest firmware version: ");
      Serial.println(latestVersion);
      
      // Compare with current version
      if (latestVersion != String(FIRMWARE_VERSION)) {
        Serial.println("New firmware version available!");
        
        // Extract the URL field
        FirebaseJsonData urlResult;
        payload.get(urlResult, "fields/url/stringValue");
        
        if (urlResult.success) {
          String firmwareUrl = urlResult.stringValue;
          Serial.print("Firmware URL: ");
          Serial.println(firmwareUrl);
          
          // Update firmware status in device document
          updateFirmwareStatus("update_available", latestVersion);
          
          // We already retrieved the auto-update setting from Firestore
          // shouldAutoUpdate contains the value from the database
          
          // Check if we should perform automatic update
          if (shouldAutoUpdate) {
            // Extract MD5 hash for verification if available
            FirebaseJsonData md5Result;
            payload.get(md5Result, "fields/md5/stringValue");
            String firmwareMD5 = "";
            if (md5Result.success) {
              firmwareMD5 = md5Result.stringValue;
            }
            
            // Perform the update
            performAutomaticUpdate(firmwareUrl, latestVersion, firmwareMD5);
          } else {
            Serial.println("Automatic updates disabled, skipping update");
          }
        }
      } else {
        Serial.println("Firmware is up to date");
      }
    }
  } else {
    Serial.print("Failed to get firmware document: ");
    Serial.println(fbdo.errorReason());
  }
}

void updateFirmwareStatus(String status, String availableVersion) {
  // Document path in Firestore
  String documentPath = "devices/" + String(deviceId);
  
  // Create the document data
  content.clear();
  content.set("fields/firmware/mapValue/fields/status/stringValue", status);
  content.set("fields/firmware/mapValue/fields/currentVersion/stringValue", String(FIRMWARE_VERSION));
  content.set("fields/firmware/mapValue/fields/availableVersion/stringValue", availableVersion);
  
  // Always include the autoUpdateEnabled field to prevent it from disappearing
  content.set("fields/firmware/mapValue/fields/autoUpdateEnabled/booleanValue", autoUpdateEnabled);
  
  // Define the update mask
  String updateMask = "firmware";
  
  if (Firebase.Firestore.patchDocument(&fbdo, PROJECT_ID, "", documentPath, content.raw(), updateMask)) {
    Serial.println("Firmware status updated successfully");
  } else {
    Serial.print("Failed to update firmware status: ");
    Serial.println(fbdo.errorReason());
  }
}

// Update firmware status with timestamp
void updateFirmwareStatusWithTimestamp(String status, String availableVersion) {
  // Document path in Firestore
  String documentPath = "devices/" + String(deviceId);
  
  // Get current time
  time_t now = time(nullptr);
  struct tm timeinfo;
  gmtime_r(&now, &timeinfo);
  char timeStr[30];
  strftime(timeStr, sizeof(timeStr), "%Y-%m-%dT%H:%M:%SZ", &timeinfo);
  
  // Create the document data
  content.clear();
  content.set("fields/firmware/mapValue/fields/status/stringValue", status);
  content.set("fields/firmware/mapValue/fields/currentVersion/stringValue", String(FIRMWARE_VERSION));
  content.set("fields/firmware/mapValue/fields/availableVersion/stringValue", availableVersion);
  content.set("fields/firmware/mapValue/fields/lastUpdated/stringValue", String(timeStr));
  
  // Always include the autoUpdateEnabled field to prevent it from disappearing
  content.set("fields/firmware/mapValue/fields/autoUpdateEnabled/booleanValue", autoUpdateEnabled);
  
  // Define the update mask
  String updateMask = "firmware";
  
  if (Firebase.Firestore.patchDocument(&fbdo, PROJECT_ID, "", documentPath, content.raw(), updateMask)) {
    Serial.println("Firmware status with timestamp updated successfully");
  } else {
    Serial.print("Failed to update firmware status: ");
    Serial.println(fbdo.errorReason());
  }
}

// Update firmware status with error and timestamp
void updateFirmwareStatusWithError(String errorMsg, String availableVersion) {
  // Document path in Firestore
  String documentPath = "devices/" + String(deviceId);
  
  // Get current time
  time_t now = time(nullptr);
  struct tm timeinfo;
  gmtime_r(&now, &timeinfo);
  char timeStr[30];
  strftime(timeStr, sizeof(timeStr), "%Y-%m-%dT%H:%M:%SZ", &timeinfo);
  
  // Create the document data
  content.clear();
  content.set("fields/firmware/mapValue/fields/status/stringValue", "update_failed");
  content.set("fields/firmware/mapValue/fields/currentVersion/stringValue", String(FIRMWARE_VERSION));
  content.set("fields/firmware/mapValue/fields/availableVersion/stringValue", availableVersion);
  content.set("fields/firmware/mapValue/fields/lastError/stringValue", errorMsg);
  content.set("fields/firmware/mapValue/fields/lastUpdated/stringValue", String(timeStr));
  
  // Always include the autoUpdateEnabled field to prevent it from disappearing
  content.set("fields/firmware/mapValue/fields/autoUpdateEnabled/booleanValue", autoUpdateEnabled);
  
  // Define the update mask
  String updateMask = "firmware";
  
  if (Firebase.Firestore.patchDocument(&fbdo, PROJECT_ID, "", documentPath, content.raw(), updateMask)) {
    Serial.println("Firmware error status updated successfully");
  } else {
    Serial.print("Failed to update firmware status: ");
    Serial.println(fbdo.errorReason());
  }
}

// Prepare for update by backing up settings and setting flags
void prepareForUpdate() {
  // Backup EEPROM settings before starting the update
  backupEEPROMSettings();
}

void performAutomaticUpdate(String firmwareUrl, String newVersion, String expectedMD5) {
  Serial.println("Starting automatic firmware update process...");
  
  // Print system information for debugging
  Serial.println("--- System Information ---");
  Serial.print("Free heap: ");
  Serial.println(ESP.getFreeHeap());
  Serial.print("Free sketch space: ");
  Serial.println(ESP.getFreeSketchSpace());
  Serial.print("Sketch size: ");
  Serial.println(ESP.getSketchSize());
  Serial.print("Flash chip size: ");
  Serial.println(ESP.getFlashChipSize());
  Serial.print("Flash chip real size: ");
  Serial.println(ESP.getFlashChipRealSize());
  Serial.println("------------------------");
  
  // Set update in progress flag
  updateInProgress = true;
  
  // Update status in Firestore
  updateFirmwareStatus("updating", newVersion);
  
  // Prepare for update by backing up EEPROM settings
  prepareForUpdate();
  
  // Configure secure connection if URL is HTTPS
  if (firmwareUrl.startsWith("https")) {
    Serial.println("Using secure connection for update");
    
    // For now, we'll use the default secure client
    WiFiClientSecure client;
    client.setInsecure(); // Skip certificate validation for simplicity
    
    // Set callback for update progress
    ESPhttpUpdate.onProgress([](int progress, int total) {
      Serial.printf("Update progress: %d%%\r", (progress / (total / 100)));
    });
    
    // Set callbacks for update events
    ESPhttpUpdate.onStart([]() {
      Serial.println("Update start");
    });
    
    ESPhttpUpdate.onEnd([]() {
      Serial.println("Update end");
    });
    
    // Store a copy of newVersion for the error handler
    String updateVersion = newVersion;
    
    ESPhttpUpdate.onError([updateVersion](int error) {
      Serial.printf("Update error: %d\n", error);
      
      // Provide more detailed error information
      if (error == 4) {
        Serial.println("ERROR[4]: Not Enough Space - The firmware binary is too large for the available space");
        Serial.println("Solutions:");
        Serial.println("1. Reduce firmware size by removing unused libraries or features");
        Serial.println("2. Check Arduino IDE flash size configuration (Tools > Flash Size)");
        Serial.println("3. Use a partition scheme with more space for OTA updates");
      }
      
      // Reset update in progress flag
      updateInProgress = false;
      
      // Update status in Firestore with error details
      updateFirmwareStatusWithError("ERROR[" + String(error) + "]: " + 
                                   (error == 4 ? "Not Enough Space" : "Unknown Error"), 
                                   updateVersion);
    });
    
    // Start the update process
    Serial.println("Downloading and installing update...");
    t_httpUpdate_return ret = ESPhttpUpdate.update(client, firmwareUrl);
    
    // Handle update result
    switch (ret) {
      case HTTP_UPDATE_FAILED:
        Serial.printf("HTTP update failed: (%d): %s\n", ESPhttpUpdate.getLastError(), ESPhttpUpdate.getLastErrorString().c_str());
        
        // Check for specific error codes
        if (ESPhttpUpdate.getLastError() == 4) {
          Serial.println("Not Enough Space error detected. The firmware binary is too large.");
          updateFirmwareStatusWithError("Not Enough Space", newVersion);
        } else {
          updateFirmwareStatusWithError("Update Failed: " + String(ESPhttpUpdate.getLastErrorString()), newVersion);
        }
        
        updateInProgress = false;
        break;
        
      case HTTP_UPDATE_NO_UPDATES:
        Serial.println("No updates available");
        updateInProgress = false;
        updateFirmwareStatus("up_to_date", "");
        break;
        
      case HTTP_UPDATE_OK:
        Serial.println("Update successful! Rebooting...");
        // The device will reboot automatically after a successful update
        break;
    }
  } else {
    // Non-secure connection
    WiFiClient client;
    
    // Set callback for update progress
    ESPhttpUpdate.onProgress([](int progress, int total) {
      Serial.printf("Update progress: %d%%\r", (progress / (total / 100)));
    });
    
    // Set callbacks for update events
    ESPhttpUpdate.onStart([]() {
      Serial.println("Update start");
    });
    
    ESPhttpUpdate.onEnd([]() {
      Serial.println("Update end");
    });
    
    // Store a copy of newVersion for the error handler
    String updateVersion = newVersion;
    
    ESPhttpUpdate.onError([updateVersion](int error) {
      Serial.printf("Update error: %d\n", error);
      
      // Provide more detailed error information
      if (error == 4) {
        Serial.println("ERROR[4]: Not Enough Space - The firmware binary is too large for the available space");
        Serial.println("Solutions:");
        Serial.println("1. Reduce firmware size by removing unused libraries or features");
        Serial.println("2. Check Arduino IDE flash size configuration (Tools > Flash Size)");
        Serial.println("3. Use a partition scheme with more space for OTA updates");
      }
      
      // Reset update in progress flag
      updateInProgress = false;
      
      // Update status in Firestore with error details
      updateFirmwareStatusWithError("ERROR[" + String(error) + "]: " + 
                                   (error == 4 ? "Not Enough Space" : "Unknown Error"), 
                                   updateVersion);
    });
    
    // Start the update process
    Serial.println("Downloading and installing update...");
    t_httpUpdate_return ret = ESPhttpUpdate.update(client, firmwareUrl);
    
    // Handle update result
    switch (ret) {
      case HTTP_UPDATE_FAILED:
        Serial.printf("HTTP update failed: (%d): %s\n", ESPhttpUpdate.getLastError(), ESPhttpUpdate.getLastErrorString().c_str());
        
        // Check for specific error codes
        if (ESPhttpUpdate.getLastError() == 4) {
          Serial.println("Not Enough Space error detected. The firmware binary is too large.");
          updateFirmwareStatusWithError("Not Enough Space", newVersion);
        } else {
          updateFirmwareStatusWithError("Update Failed: " + String(ESPhttpUpdate.getLastErrorString()), newVersion);
        }
        
        updateInProgress = false;
        break;
        
      case HTTP_UPDATE_NO_UPDATES:
        Serial.println("No updates available");
        updateInProgress = false;
        updateFirmwareStatus("up_to_date", "");
        break;
        
      case HTTP_UPDATE_OK:
        Serial.println("Update successful! Rebooting...");
        // The device will reboot automatically after a successful update
        break;
    }
  }
}

void checkDeviceNameInFirebase() {
  Serial.println("Checking for device name changes in Firestore...");
  
  // Check if Firebase is ready
  if (!Firebase.ready()) {
    Serial.println("Firebase is not ready, skipping name check");
    return;
  }
  
  // Document path in Firestore
  String documentPath = "devices/" + String(deviceId);
  
  // Get the document from Firestore
  if (Firebase.Firestore.getDocument(&fbdo, PROJECT_ID, "", documentPath, "name")) {
    Serial.println("Got document name field from Firestore");
    
    // Parse the JSON response
    FirebaseJson payload;
    payload.setJsonData(fbdo.payload().c_str());
    
    // Extract the name field
    FirebaseJsonData result;
    payload.get(result, "fields/name/stringValue");
    
    if (result.success) {
      String firebaseName = result.stringValue;
      String currentName = String(deviceName);
      
      Serial.print("Firebase name: ");
      Serial.println(firebaseName);
      Serial.print("Current local name: ");
      Serial.println(currentName);
      
      // If names are different, update local name
      if (firebaseName != currentName) {
        Serial.println("Device name changed in Firebase, updating local name");
        
        // Update local name
        firebaseName.toCharArray(deviceName, sizeof(deviceName));
        
        // Save to EEPROM
        for (int i = 0; i < sizeof(deviceName); i++) {
          EEPROM.write(EEPROM_DEVICE_NAME_ADDR + i, deviceName[i]);
        }
        EEPROM.commit();
        
        Serial.print("Local name updated to: ");
        Serial.println(deviceName);
      } else {
        Serial.println("Device name unchanged");
      }
    } else {
      Serial.println("Name field not found in document");
    }
  } else {
    Serial.print("Failed to get document from Firestore: ");
    Serial.println(fbdo.errorReason());
  }
}

void sendStatusUpdate() {
  Serial.println("Sending status update to Firestore...");
  
  // Check if Firebase is ready (token is valid)
  if (!Firebase.ready()) {
    Serial.println("Firebase is not ready, waiting for token refresh...");
    delay(1000);
    return;
  }
  
  // Document path in Firestore
  String documentPath = "devices/" + String(deviceId);
  
  // Get current time in seconds since epoch
  unsigned long currentTime = time(nullptr);
  
  // Create the document data
  content.clear();
  content.set("fields/state/booleanValue", currentState);
  content.set("fields/status/stringValue", "online");
  content.set("fields/ipAddress/stringValue", WiFi.localIP().toString());
  content.set("fields/lastActive/integerValue", String(currentTime));
  
  // Add firmware information to the update
  content.set("fields/firmware/mapValue/fields/currentVersion/stringValue", FIRMWARE_VERSION);
  content.set("fields/firmware/mapValue/fields/autoUpdateEnabled/booleanValue", autoUpdateEnabled);
  
  // Define the update mask for the fields we want to update
  String updateMask = "state,status,ipAddress,lastActive,firmware.currentVersion,firmware.autoUpdateEnabled";
  
  if (Firebase.Firestore.patchDocument(&fbdo, PROJECT_ID, "", documentPath, content.raw(), updateMask)) {
    Serial.println("Status update sent successfully to Firestore");
  } else {
    Serial.print("Failed to update status in Firestore: ");
    Serial.println(fbdo.errorReason());
    
    // If document doesn't exist, create it
    if (fbdo.errorReason().indexOf("NOT_FOUND") >= 0) {
      Serial.println("Document not found, creating it...");
      
      // Add name field for document creation
      content.set("fields/name/stringValue", String(deviceName));
      
      if (Firebase.Firestore.createDocument(&fbdo, PROJECT_ID, "", documentPath, content.raw())) {
        Serial.println("New document created successfully in Firestore");
      } else {
        Serial.print("Failed to create document: ");
        Serial.println(fbdo.errorReason());
      }
    }
  }
}

void backupEEPROMSettings() {
  Serial.println("Backing up EEPROM settings before update...");
  
  // First, mark that we're doing an update
  EEPROM.write(EEPROM_UPDATE_FLAG_ADDR, 1);
  
  // Backup WiFi credentials and device info
  for (int i = 0; i < EEPROM_BACKUP_SIZE; i++) {
    byte value = EEPROM.read(i);  // Read from original location
    EEPROM.write(EEPROM_BACKUP_ADDR + i, value);  // Write to backup location
  }
  
  EEPROM.commit();
  Serial.println("EEPROM backup complete");
}

// Function to restore EEPROM data after an update
void restoreEEPROMSettings() {
  Serial.println("Restoring EEPROM settings after update...");
  
  // Restore WiFi credentials and device info
  for (int i = 0; i < EEPROM_BACKUP_SIZE; i++) {
    byte value = EEPROM.read(EEPROM_BACKUP_ADDR + i);  // Read from backup location
    EEPROM.write(i, value);  // Write to original location
  }
  
  // Clear the update flag
  EEPROM.write(EEPROM_UPDATE_FLAG_ADDR, 0);
  EEPROM.commit();
  
  Serial.println("EEPROM restore complete");
}
