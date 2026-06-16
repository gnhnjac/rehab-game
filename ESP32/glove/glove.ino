#include <Arduino.h>
#include <Adafruit_DRV2605.h>
#include "soc/soc.h"
#include "soc/rtc_cntl_reg.h"

Adafruit_DRV2605 hapticDrv;
bool hapticEnabled = false;

#include "glove_haptic.h"
#include "glove_sensors.h"
#include "glove_espnow.h"

unsigned long lastPrintTime = 0;
const unsigned long printInterval = 500; // Print sensor/registry states every 500ms

void setup() {
    // Disable the brownout detector to prevent power dips from resetting the chip
    //WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0);

    Serial.begin(115200);
    delay(1000);
    Serial.println("[Glove] Starting central server...");

    setupSensors();
    setupHaptic();
    setupEspNow();

    Serial.println("[Glove] ESP-NOW initialized. Waiting for Smart Boxes...");
    Serial.println("[Glove] Press the Calibration Button (GPIO 4) to start calibration.");
}

void loop() {
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

            int flexPercent[NUM_FINGERS];
            int forcePercent = 0;
            readMappedSensors(flexPercent, forcePercent);

            // 1. Print standard serial output for debugging
            Serial.print("Flex: [");
            for (int i = 0; i < NUM_FINGERS; i++) {
                Serial.print(flexPercent[i]);
                if (i < NUM_FINGERS - 1) Serial.print("%, ");
            }
            Serial.printf("%%] | Force (FSR): %d%%\n", forcePercent);
            printRegistry();

            // 2. Print JSON telemetry for local HTML dashboard
            Serial.print("JSON:{\"flex\":[");
            for (int i = 0; i < NUM_FINGERS; i++) {
                Serial.print(flexPercent[i]);
                if (i < NUM_FINGERS - 1) Serial.print(",");
            }
            Serial.printf("],\"force\":%d,\"calibrated\":true,\"boxes\":[", forcePercent);
            
            bool firstBox = true;
            for (const auto& pair : boxRegistry) {
                const RegisteredBox& box = pair.second;
                if (!firstBox) Serial.print(",");
                firstBox = false;
                
                Serial.print("{\"mac\":\"");
                for (int j = 0; j < 6; j++) {
                    Serial.printf("%02X", box.mac[j]);
                    if (j < 5) Serial.print(":");
                }
                Serial.print("\",\"cube\":\"");
                if (box.current_cube_len > 0) {
                    for (int j = 0; j < box.current_cube_len; j++) {
                        Serial.printf("%02X", box.current_cube_uid[j]);
                    }
                }
                Serial.print("\"}");
            }
            Serial.println("]}");
        }
    } 
    else if (millis() - lastPrintTime >= printInterval) {
        lastPrintTime = millis();
        Serial.println("JSON:{\"calibrated\":false}");
        Serial.println("[Glove] Awaiting sensor calibration. Press the button to begin.");
    }
}
