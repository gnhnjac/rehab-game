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

// Thread-safe telemetry data structure shared between Cores
struct SensorTelemetryData {
    bool calibrated;
    int flexRaw[NUM_FINGERS];
    int flexPercent[NUM_FINGERS];
    int forceRaw;
    int forcePercent;
};

SensorTelemetryData sharedTelemetry;
SemaphoreHandle_t telemetryMutex;

// Time tracking
unsigned long lastPrintTime = 0;
const unsigned long printInterval = 500; // Print sensor states every 500ms
unsigned long lastSampleTime = 0;
const unsigned long sampleInterval = 20; // Sample sensors at 50Hz (every 20ms)

// Background upload task pinned to Core 0 (handling all Wi-Fi / HTTPS uploads)
void telemetryUploadTask(void* parameter) {
    unsigned long lastUploadTime = 0;
    const unsigned long uploadInterval = 500; // Upload telemetry to Firebase every 500ms
    
    for (;;) {
        // Sleep for a short duration to yield CPU to other Core 0 system tasks (like Wi-Fi stack)
        vTaskDelay(pdMS_TO_TICKS(20));
        
        // 1. Process any deferred Firebase BoxAction uploads from the ESP-NOW queue
        BoxActionEvent pendingEvent;
        if (popEvent(pendingEvent)) {
            uploadBoxAction(pendingEvent.cubeId, pendingEvent.timestamp, pendingEvent.isPlaced, pendingEvent.boxIndex);
        }

        // 2. Periodically upload live telemetry
        if (millis() - lastUploadTime >= uploadInterval) {
            lastUploadTime = millis();
            
            SensorTelemetryData localData;
            // Safely fetch a local copy of the shared telemetry data
            if (xSemaphoreTake(telemetryMutex, portMAX_DELAY) == pdTRUE) {
                localData = sharedTelemetry;
                xSemaphoreGive(telemetryMutex);
            }
            
            if (localData.calibrated) {
                uploadLiveTelemetry(true, localData.flexRaw, localData.flexPercent, localData.forceRaw, localData.forcePercent);
            } else {
                uploadLiveTelemetry(false, nullptr, nullptr, 0, 0);
            }
        }
    }
}

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

    // Create a mutex to protect shared telemetry data across cores
    telemetryMutex = xSemaphoreCreateMutex();

    // Spawn the background uploading task on Core 0
    xTaskCreatePinnedToCore(
        telemetryUploadTask,     // Task function
        "TelemetryUploadTask",   // Task name
        8192,                    // Stack size (8KB is plenty for WiFiClientSecure/HTTPS)
        NULL,                    // Parameter passed to task
        1,                       // Task priority
        NULL,                    // Task handle
        0                        // Core ID (0 is the Wi-Fi/system core)
    );

    Serial.println("[Glove] Multitasking initialized.");
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
            
            // Set uncalibrated state before running blocking calibration so background task uploads it immediately
            isCalibrated = false;
            if (xSemaphoreTake(telemetryMutex, portMAX_DELAY) == pdTRUE) {
                sharedTelemetry.calibrated = false;
                xSemaphoreGive(telemetryMutex);
            }
            
            runSensorCalibration();
        }
    }

    // Read and sample sensors at a fixed frequency of 50Hz (Core 1)
    if (millis() - lastSampleTime >= sampleInterval) {
        lastSampleTime = millis();
        
        if (isCalibrated) {
            int flexRaw[NUM_FINGERS];
            int flexPercent[NUM_FINGERS];
            int forceRaw = 0;
            int forcePercent = 0;
            readAllSensors(flexRaw, flexPercent, forceRaw, forcePercent);

            // Safely write the fresh readings to the shared structure
            if (xSemaphoreTake(telemetryMutex, 0) == pdTRUE) {
                sharedTelemetry.calibrated = true;
                memcpy(sharedTelemetry.flexRaw, flexRaw, sizeof(flexRaw));
                memcpy(sharedTelemetry.flexPercent, flexPercent, sizeof(flexPercent));
                sharedTelemetry.forceRaw = forceRaw;
                sharedTelemetry.forcePercent = forcePercent;
                xSemaphoreGive(telemetryMutex);
            }

            // Print standard serial output for debugging at the print interval
            if (millis() - lastPrintTime >= printInterval) {
                lastPrintTime = millis();
                Serial.print("Flex: [");
                for (int i = 0; i < NUM_FINGERS; i++) {
                    Serial.print(flexPercent[i]);
                    if (i < NUM_FINGERS - 1) Serial.print("%, ");
                }
                Serial.printf("%%] | Force (FSR): %d%%\n", forcePercent);
                printRegistry();
            }
        } 
        else {
            // Uncalibrated state
            if (xSemaphoreTake(telemetryMutex, 0) == pdTRUE) {
                sharedTelemetry.calibrated = false;
                xSemaphoreGive(telemetryMutex);
            }
            
            if (millis() - lastPrintTime >= printInterval) {
                lastPrintTime = millis();
                Serial.println("[Glove] Awaiting sensor calibration. Press the button to begin.");
            }
        }
    }
}
