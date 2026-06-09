#include <Arduino.h>
#include "soc/soc.h"
#include "soc/rtc_cntl_reg.h"
#include "glove_sensors.h"
#include "glove_espnow.h"

unsigned long lastPrintTime = 0;
const unsigned long printInterval = 500; // Print sensor/registry states every 500ms

void setup() {
    // Disable the brownout detector to prevent power dips from resetting the chip
    WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0);

    Serial.begin(115200);
    delay(1000);
    Serial.println("[Glove] Starting central server...");

    setupSensors();
    setupEspNow();

    Serial.println("[Glove] ESP-NOW initialized. Waiting for Smart Boxes...");
    Serial.println("[Glove] Press the Calibration Button (GPIO 4) to start calibration.");
}

void loop() {
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

            // Print Sensor Output
            Serial.print("Flex: [");
            for (int i = 0; i < NUM_FINGERS; i++) {
                Serial.print(flexPercent[i]);
                if (i < NUM_FINGERS - 1) Serial.print("%, ");
            }
            Serial.printf("%%] | Force (FSR): %d%%\n", forcePercent);

            // Print Box Registry and Cube Placements
            printRegistry();
        }
    } 
    else if (millis() - lastPrintTime >= 3000) {
        lastPrintTime = millis();
        Serial.println("[Glove] Awaiting sensor calibration. Press the button to begin.");
    }
}
