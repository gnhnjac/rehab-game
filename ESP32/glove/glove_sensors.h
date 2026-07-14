#ifndef GLOVE_SENSORS_H
#define GLOVE_SENSORS_H

#include <Arduino.h>
#include "../parameters.h"

// Configuration
const int flexPins[NUM_FINGERS] = {FLEX_PIN_1, FLEX_PIN_2, FLEX_PIN_3, FLEX_PIN_4, FLEX_PIN_5};
const float filterWeight = SENSOR_FILTER_WEIGHT;

// State
extern int flexMin[NUM_FINGERS];
extern int flexMax[NUM_FINGERS];
extern float flexSmoothed[NUM_FINGERS];

extern int forceMin;
extern int forceMax;
extern float forceSmoothed;

extern bool isCalibrated;
extern int fsrCalRaw[3];
extern int fsrCalGrams[3];


inline float getFsrForceGrams(int raw) {
    if (raw >= 4095) return 0.0f; // FSR idle state (unloaded)
    float x = (float)raw;
    float grams = (((-1.47891421e-07 * x + 1.13881999e-03) * x + -2.84335776e+00) * x + 2.66788197e+03) + 100.0f;
    return grams < 0.0f ? 0.0f : grams; // Clamp negative values
}
#include <Preferences.h>
extern Preferences preferences;
inline void setupSensors() {
    pinMode(CALIBRATION_BUTTON_PIN, INPUT_PULLUP);
    for (int i = 0; i < NUM_FINGERS; i++) {
        pinMode(flexPins[i], INPUT);
    }
    pinMode(FORCE_PIN, INPUT);

    // Load from NVS Preferences
    preferences.begin("calib", true); // Read-only mode
    isCalibrated = preferences.getBool("is_cal", false);
    if (isCalibrated) {
        for (int i = 0; i < NUM_FINGERS; i++) {
            char keyMin[16], keyMax[16];
            sprintf(keyMin, "fl_min_%d", i);
            sprintf(keyMax, "fl_max_%d", i);
            flexMin[i] = preferences.getInt(keyMin, 0);
            flexMax[i] = preferences.getInt(keyMax, 4095);
        }
        forceMin = preferences.getInt("fo_min", 4095);
        forceMax = preferences.getInt("fo_max", 0);
        Serial.println("[Sensors] Calibration parameters loaded from NVS successfully.");
    } else {
        Serial.println("[Sensors] No valid calibration found in NVS. Using default bounds.");
        for (int i = 0; i < NUM_FINGERS; i++) {
            flexMin[i] = 0;
            flexMax[i] = 4095;
        }
        forceMin = 4095;
        forceMax = 0;
    }
    preferences.end();

    // Initialize smoothed values
    for (int i = 0; i < NUM_FINGERS; i++) {
        flexSmoothed[i] = analogRead(flexPins[i]);
    }
    forceSmoothed = analogRead(FORCE_PIN);
}

extern SensorTelemetryData sharedTelemetry;
extern SemaphoreHandle_t telemetryMutex;

inline void readMappedSensors(int* flexPercent, int& forcePercent) {
    for (int i = 0; i < NUM_FINGERS; i++) {
        int raw = analogRead(flexPins[i]);
        flexSmoothed[i] = (raw * filterWeight) + (flexSmoothed[i] * (1.0 - filterWeight));
        
        flexPercent[i] = map((int)flexSmoothed[i], flexMin[i], flexMax[i], 0, 100);
        flexPercent[i] = constrain(flexPercent[i], 0, 100);
    }

    int rawForce = analogRead(FORCE_PIN);
    forceSmoothed = (rawForce * filterWeight) + (forceSmoothed * (1.0 - filterWeight));
    forcePercent = map((int)forceSmoothed, forceMin, forceMax, 0, 100);
    forcePercent = constrain(forcePercent, 0, 100);
}

inline void readAllSensors(int* flexRaw, int* flexPercent, int& forceRaw, int& forcePercent) {
    for (int i = 0; i < NUM_FINGERS; i++) {
        int raw = analogRead(flexPins[i]);
        flexSmoothed[i] = (raw * filterWeight) + (flexSmoothed[i] * (1.0 - filterWeight));
        
        flexRaw[i] = (int)flexSmoothed[i];
        flexPercent[i] = map(flexRaw[i], flexMin[i], flexMax[i], 0, 100);
        flexPercent[i] = constrain(flexPercent[i], 0, 100);
    }

    int rawForce = analogRead(FORCE_PIN);
    forceSmoothed = (rawForce * filterWeight) + (forceSmoothed * (1.0 - filterWeight));
    forceRaw = (int)forceSmoothed;
    forcePercent = map(forceRaw, forceMin, forceMax, 0, 100);
    forcePercent = constrain(forcePercent, 0, 100);
}

#endif
