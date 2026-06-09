#ifndef GLOVE_SENSORS_H
#define GLOVE_SENSORS_H

#include <Arduino.h>
#include "../parameters.h"

// Configuration
const int flexPins[NUM_FINGERS] = {FLEX_PIN_1, FLEX_PIN_2, FLEX_PIN_3, FLEX_PIN_4, FLEX_PIN_5};
const float filterWeight = 0.10;

// State
int flexMin[NUM_FINGERS];
int flexMax[NUM_FINGERS];
float flexSmoothed[NUM_FINGERS];

int forceMin = 4095;
int forceMax = 0;
float forceSmoothed = 0;

bool isCalibrated = false;

inline void setupSensors() {
    pinMode(CALIBRATION_BUTTON_PIN, INPUT_PULLUP);
    for (int i = 0; i < NUM_FINGERS; i++) {
        pinMode(flexPins[i], INPUT);
    }
    pinMode(FORCE_PIN, INPUT);
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
            
            if (flexSmoothed[i] < flexMin[i]) flexMin[i] = (int)flexSmoothed[i];
            if (flexSmoothed[i] > flexMax[i]) flexMax[i] = (int)flexSmoothed[i];
        }

        int rawForce = analogRead(FORCE_PIN);
        forceSmoothed = (rawForce * filterWeight) + (forceSmoothed * (1.0 - filterWeight));

        if (forceSmoothed < forceMin) forceMin = (int)forceSmoothed;
        if (forceSmoothed > forceMax) forceMax = (int)forceSmoothed;

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
    forcePercent = map((int)forceSmoothed, forceMin, forceMax, 0, 100);
    forcePercent = constrain(forcePercent, 0, 100);
}

#endif
