#ifndef GLOVE_HAPTIC_H
#define GLOVE_HAPTIC_H

#include <Wire.h>
#include <Adafruit_DRV2605.h>
#include "../parameters.h"

extern Adafruit_DRV2605 hapticDrv;
extern bool hapticEnabled;

inline void setupHaptic() {
    Serial.println("[Haptic] Initializing DRV2605 on I2C...");
    Wire.begin(SDA_PIN, SCL_PIN);
    
    if (hapticDrv.begin()) {
        hapticDrv.selectLibrary(1);             
        hapticDrv.setMode(DRV2605_MODE_INTTRIG); 
        hapticEnabled = true;
        Serial.println("[Haptic] DRV2605 initialized successfully.");
    } else {
        hapticEnabled = false;
        Serial.println("[Haptic] Warning: DRV2605 not found. Haptic feedback disabled.");
    }
}

inline void triggerHapticClick() {
    if (hapticEnabled) {
        hapticDrv.setWaveform(0, 14); // Effect 14: Strong Click - 100%
        hapticDrv.setWaveform(1, 0);  // End sequence
        hapticDrv.go();
        Serial.println("[Haptic] Triggered vibration click feedback.");
    }
}

inline void triggerHapticContinuous() {
    if (hapticEnabled) {
        hapticDrv.setWaveform(0, 47); // Effect 47: Buzz 1 100%
        hapticDrv.setWaveform(1, 0);  // End sequence
        hapticDrv.go();
    }
}

inline void stopHapticContinuous() {
    if (hapticEnabled) {
        hapticDrv.setWaveform(0, 0); // Stop
        hapticDrv.go();
    }
}

#endif

