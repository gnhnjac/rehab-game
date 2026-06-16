#include <Arduino.h>
#include <Adafruit_DRV2605.h>
#include "soc/soc.h"
#include "soc/rtc_cntl_reg.h"

Adafruit_DRV2605 hapticDrv;
bool hapticEnabled = false;

#include "glove_haptic.h"
#include "glove_sensors.h"
#include "glove_firebase.h"
#include "glove_espnow.h"

unsigned long lastPrintTime = 0;
const unsigned long printInterval = 500; // Print sensor/registry states every 500ms

void setup() {
    // Disable the brownout detector to prevent power dips from resetting the chip
    //WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0);

    Serial.begin(115200);
    delay(1000);
    Serial.println("[Glove] Starting central server...");

    setupWifi();
    setupSensors();
    setupHaptic();
    setupEspNow();

    Serial.println("[Glove] ESP-NOW initialized. Waiting for Smart Boxes...");
    Serial.println("[Glove] Press the Calibration Button (GPIO 4) to start calibration.");
}

void loop() {
    // Process any deferred Firebase BoxAction uploads from the ESP-NOW queue
    BoxActionEvent pendingEvent;
    if (popEvent(pendingEvent)) {
        uploadBoxAction(pendingEvent.cubeId, pendingEvent.timestamp, pendingEvent.isPlaced, pendingEvent.boxIndex);
    }

    // Periodically clean up timed-out boxes
    checkBoxTimeouts();

    // Check calibration button
    if (digitalRead(CALIBRATION_BUTTON_PIN) == LOW) {
        delay(50); // Debounce
        if (digitalRead(CALIBRATION_BUTTON_PIN) == LOW) {
            while (digitalRead(CALIBRATION_BUTTON_PIN) == LOW) {
                delay(10);
            }
            runSensorCalibration();
        }
    }

    // Read and print sensor readings + registry state
    if (isCalibrated) {
        if (millis() - lastPrintTime >= printInterval) {
            lastPrintTime = millis();

            int flexRaw[NUM_FINGERS];
            int flexPercent[NUM_FINGERS];
            int forceRaw = 0;
            int forcePercent = 0;
            readAllSensors(flexRaw, flexPercent, forceRaw, forcePercent);

            // 1. Print standard serial output for debugging
            Serial.print("Flex: [");
            for (int i = 0; i < NUM_FINGERS; i++) {
                Serial.print(flexPercent[i]);
                if (i < NUM_FINGERS - 1) Serial.print("%, ");
            }
            Serial.printf("%%] | Force (FSR): %d%%\n", forcePercent);
            printRegistry();

            // 2. Upload live data to Firebase
            uploadLiveTelemetry(true, flexRaw, flexPercent, forceRaw, forcePercent);
        }
    } 
    else if (millis() - lastPrintTime >= printInterval) {
        lastPrintTime = millis();
        
        // Upload uncalibrated state to Firebase
        uploadLiveTelemetry(false, nullptr, nullptr, 0, 0);
        
        Serial.println("[Glove] Awaiting sensor calibration. Press the button to begin.");
    }
}
