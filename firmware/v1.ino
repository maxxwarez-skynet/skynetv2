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
