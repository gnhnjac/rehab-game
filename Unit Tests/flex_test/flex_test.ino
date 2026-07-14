// 1. Hardware Pins
const int numFingers = 5;
const int flexPins[numFingers] = {25, 33, 32, 35, 34};const int BUTTON_PIN = 4; 

// 2. Data Arrays
int minVals[numFingers];
int maxVals[numFingers];
float smoothedVals[numFingers];

// 3. System States & Configuration
bool isCalibrated = false;
const float filterWeight = 0.10; 

void setup() {
  Serial.begin(115200);
  
  // Configure the button pin with an internal pull-up
  pinMode(BUTTON_PIN, INPUT_PULLUP);
  
  // Configure flex pins
  for (int i = 0; i < numFingers; i++) {
    pinMode(flexPins[i], INPUT);
  }
  
  Serial.println("System initialized. Press the button to run calibration.");
}

void loop() {
  // Check if the button is pressed (pin goes LOW)
  if (digitalRead(BUTTON_PIN) == LOW) {
    // Hardware debounce delay
    delay(50);
    
    // Wait until the button is fully released to prevent infinite looping
    while (digitalRead(BUTTON_PIN) == LOW) { 
      delay(10); 
    }
    
    // Trigger the calibration routine
    runCalibration();
    isCalibrated = true; 
  }

  // Execution branching based on calibration state
  if (isCalibrated) {
    readSensors();
  } else {
    // Non-blocking prompt printed every 2 seconds while waiting for the initial calibration
    static unsigned long lastPrompt = 0;
    if (millis() - lastPrompt > 2000) {
      Serial.println("Awaiting initial calibration... Press the button to start.");
      lastPrompt = millis();
    }
    delay(10);
  }
}

// --- CALIBRATION LOGIC ---
void runCalibration() {
  Serial.println("\n--- CALIBRATION STARTING ---");
  Serial.println("Fully BEND and STRAIGHTEN all fingers repeatedly for 5 seconds!");
  
  // Reset limits to baseline values for a fresh run
  for (int i = 0; i < numFingers; i++) {
    minVals[i] = 4095; 
    maxVals[i] = 0;    
    smoothedVals[i] = analogRead(flexPins[i]); // Pre-seed filter to current position
  }
  
  unsigned long startTime = millis();
  
  // Execute loop for 5000 milliseconds
  while (millis() - startTime < 5000) { 
    for (int i = 0; i < numFingers; i++) {
      int rawRead = analogRead(flexPins[i]);
      
      // Filter raw input data before evaluation
      smoothedVals[i] = (rawRead * filterWeight) + (smoothedVals[i] * (1.0 - filterWeight));
      
      // Capture boundaries based on filtered data
      if (smoothedVals[i] < minVals[i]) minVals[i] = smoothedVals[i];
      if (smoothedVals[i] > maxVals[i]) maxVals[i] = smoothedVals[i];
    }
    delay(10); // Maintain fixed sampling interval
  }
  
  Serial.println("--- CALIBRATION COMPLETE ---\n");
  delay(500); // Brief operational pause
}

// --- MAIN SENSOR LOGIC ---
void readSensors() {
  Serial.print("Flex %: ");

  for (int i = 0; i < numFingers; i++) {
    int raw = analogRead(flexPins[i]);

    // Continuous filtering during normal operation
    smoothedVals[i] = (raw * filterWeight) + (smoothedVals[i] * (1.0 - filterWeight));

    // Map filtered range to target 0-100 percentage scale
    int flexPercent = map(smoothedVals[i], minVals[i], maxVals[i], 0, 100);
    flexPercent = constrain(flexPercent, 0, 100);

    Serial.print(flexPercent);
    Serial.print("%\t"); 
  }
  
  Serial.println(); 
  delay(20); // Execution rate limiting (~50 Hz output)
}