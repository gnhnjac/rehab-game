#ifndef GLOVE_SENSORS_H
#define GLOVE_SENSORS_H

#include <Arduino.h>
#include "../parameters.h"

// Configuration
const int flexPins[NUM_FINGERS] = {FLEX_PIN_1, FLEX_PIN_2, FLEX_PIN_3, FLEX_PIN_4, FLEX_PIN_5};
const float filterWeight = SENSOR_FILTER_WEIGHT;

// State
int flexMin[NUM_FINGERS];
int flexMax[NUM_FINGERS];
float flexSmoothed[NUM_FINGERS];

int forceMin = 4095;
int forceMax = 0;
float forceSmoothed = 0;

#include <Preferences.h>

Preferences preferences;
bool isCalibrated = false;

inline void setupSensors() {
    pinMode(CALIBRATION_BUTTON_PIN, INPUT_PULLUP);
    for (int i = 0; i < NUM_FINGERS; i++) {
        pinMode(flexPins[i], INPUT);
    }
    pinMode(FORCE_PIN, INPUT);

    // Load from NVS Preferences
    preferences.begin("calib", true); // Read-only mode
    isCalibrated = preferences.getBool("isCalibrated", false);
    if (isCalibrated) {
        preferences.getBytes("flexMin", flexMin, sizeof(flexMin));
        preferences.getBytes("flexMax", flexMax, sizeof(flexMax));
        forceMin = preferences.getInt("forceMin", 4095);
        forceMax = preferences.getInt("forceMax", 0);
        Serial.println("[Sensors] Calibration parameters loaded from NVS successfully.");
    } else {
        Serial.println("[Sensors] No valid calibration found in NVS. Awaiting manual/API calibration.");
    }
    preferences.end();

    // Initialize smoothed values
    for (int i = 0; i < NUM_FINGERS; i++) {
        flexSmoothed[i] = analogRead(flexPins[i]);
    }
    forceSmoothed = analogRead(FORCE_PIN);
}

inline void runSensorCalibration() {
    Serial.println("\n=================================");
    Serial.println("--- GLOVE SENSOR CALIBRATION ---");
    Serial.println("Fully FLEX and EXTEND all fingers, and SQUEEZE the force sensor.");
    Serial.println("Calibration will run for 5 seconds...");
    Serial.println("=================================");

    // Reset/initialize limits
    for (int i = 0; i < NUM_FINGERS; i++) {
        flexMin[i] = 4095;
        flexMax[i] = 0;
        flexSmoothed[i] = analogRead(flexPins[i]);
    }
    forceMin = 4095;
    forceMax = 0;
    forceSmoothed = analogRead(FORCE_PIN);

    unsigned long startTime = millis();
    unsigned long lastStatusPrint = 0;

    while (millis() - startTime < 5000) {
        for (int i = 0; i < NUM_FINGERS; i++) {
            int raw = analogRead(flexPins[i]);
            flexSmoothed[i] = (raw * filterWeight) + (flexSmoothed[i] * (1.0 - filterWeight));
            
            if (raw < flexMin[i]) flexMin[i] = raw;
            if (raw > flexMax[i]) flexMax[i] = raw;
        }

        int rawForce = analogRead(FORCE_PIN);
        forceSmoothed = (rawForce * filterWeight) + (forceSmoothed * (1.0 - filterWeight));

        if (rawForce < forceMin) forceMin = rawForce;
        if (rawForce > forceMax) forceMax = rawForce;

        if (millis() - lastStatusPrint >= 1000) {
            int elapsedSec = (millis() - startTime) / 1000;
            Serial.printf("Calibrating... %d/5s remaining\n", 5 - elapsedSec);
            lastStatusPrint = millis();
        }
        delay(10);
    }

    // Prevent division by zero
    for (int i = 0; i < NUM_FINGERS; i++) {
        if (flexMax[i] == flexMin[i]) flexMax[i]++;
    }
    if (forceMax == forceMin) forceMax++;

    isCalibrated = true;

    // Save permanently to Preferences
    preferences.begin("calib", false); // Read-write mode
    preferences.putBytes("flexMin", flexMin, sizeof(flexMin));
    preferences.putBytes("flexMax", flexMax, sizeof(flexMax));
    preferences.putInt("forceMin", forceMin);
    preferences.putInt("forceMax", forceMax);
    preferences.putBool("isCalibrated", isCalibrated);
    preferences.end();

    Serial.println("--- CALIBRATION COMPLETE ---");
    for (int i = 0; i < NUM_FINGERS; i++) {
        Serial.printf("  Finger %d: %d -> %d\n", i + 1, flexMin[i], flexMax[i]);
    }
    Serial.printf("  Force FSR: %d -> %d\n", forceMin, forceMax);
    Serial.println("=================================\n");
}

inline void readMappedSensors(int* flexPercent, int& forcePercent) {
    for (int i = 0; i < NUM_FINGERS; i++) {
        int raw = analogRead(flexPins[i]);
        flexSmoothed[i] = (raw * filterWeight) + (flexSmoothed[i] * (1.0 - filterWeight));
        
        flexPercent[i] = map((int)flexSmoothed[i], flexMin[i], flexMax[i], 0, 100);
        flexPercent[i] = constrain(flexPercent[i], 0, 100);
    }

    int rawForce = analogRead(FORCE_PIN);
    forceSmoothed = (rawForce * filterWeight) + (forceSmoothed * (1.0 - filterWeight));
    forcePercent = map((int)forceSmoothed, forceMax, forceMin, 0, 100);
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
    forcePercent = map(forceRaw, forceMax, forceMin, 0, 100);
    forcePercent = constrain(forcePercent, 0, 100);
}

#endif
