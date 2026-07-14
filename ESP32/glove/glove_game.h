#pragma once
#include <Arduino.h>
#include <vector>
#include "../parameters.h"
#include "glove_audio.h"
#include "glove_haptic.h"

// --- calibration data ---
extern int flexMin[NUM_FINGERS];
extern int flexMax[NUM_FINGERS];
extern int forceMin;
extern int forceMax;
extern bool isCalibrated;




// --- game prescription & state structure ---


inline void savePrescriptionToNVS(const GamePrescription& rx) {
    Preferences prefs;
    prefs.begin("prescription", false);
    prefs.putInt("type", (int)rx.gameType);
    prefs.putInt("timer", rx.timerSeconds);
    prefs.putInt("cycles", rx.totalCycles);
    prefs.putInt("difficulty", rx.difficulty);
    prefs.putInt("tgtWeight", rx.targetWeightGrams);
    prefs.putInt("holdTime", rx.requiredHoldTimeSeconds);
    
    // Save active fingers
    uint32_t activeFingersVal = 0;
    for (int i = 0; i < NUM_FINGERS; i++) {
        if (rx.activeFingers[i]) activeFingersVal |= (1 << i);
    }
    prefs.putUInt("actFingers", activeFingersVal);
    
    // Save required ROM
    for (int i = 0; i < NUM_FINGERS; i++) {
        char key[16];
        sprintf(key, "rom_%d", i);
        prefs.putInt(key, rx.requiredRom[i]);
    }
    
    // Save sequence
    prefs.putInt("seqCount", rx.sequenceCount);
    for (int i = 0; i < NUM_FINGERS; i++) {
        char key[16];
        sprintf(key, "seq_%d", i);
        prefs.putInt(key, rx.sequence[i]);
    }
    
    // Save cubes
    prefs.putInt("cubesCount", rx.cubesCount);
    for (int i = 0; i < rx.cubesCount; i++) {
        char keyUid[24], keyUidLen[24], keyCol[24], keyShp[24], keyWgt[24];
        sprintf(keyUid, "cube_uid_%d", i);
        sprintf(keyUidLen, "cube_len_%d", i);
        sprintf(keyCol, "cube_col_%d", i);
        sprintf(keyShp, "cube_shp_%d", i);
        sprintf(keyWgt, "cube_wgt_%d", i);
        
        if (rx.cubes[i].uid_len > 0) {
            prefs.putBytes(keyUid, rx.cubes[i].uid, rx.cubes[i].uid_len);
        }
        prefs.putInt(keyUidLen, rx.cubes[i].uid_len);
        prefs.putString(keyCol, rx.cubes[i].color);
        prefs.putString(keyShp, rx.cubes[i].shape);
        prefs.putInt(keyWgt, rx.cubes[i].weightGrams);
    }
    
    prefs.end();
    Serial.println("[NVS] Game prescription saved to NVS successfully.");
}

inline bool loadPrescriptionFromNVS(GamePrescription& rx) {
    Preferences prefs;
    if (!prefs.begin("prescription", true)) return false;
    
    int typeVal = prefs.getInt("type", 0);
    if (typeVal == 0) {
        prefs.end();
        return false; // No valid prescription stored
    }
    
    rx.gameType = (GameType)typeVal;
    rx.timerSeconds = prefs.getInt("timer", 60);
    rx.totalCycles = prefs.getInt("cycles", 3);
    rx.difficulty = prefs.getInt("difficulty", 1);
    rx.targetWeightGrams = prefs.getInt("tgtWeight", 100);
    rx.requiredHoldTimeSeconds = prefs.getInt("holdTime", 5);
    
    // Load active fingers
    uint32_t activeFingersVal = prefs.getUInt("actFingers", 0);
    for (int i = 0; i < NUM_FINGERS; i++) {
        rx.activeFingers[i] = (activeFingersVal & (1 << i)) ? 1 : 0;
    }
    
    // Load required ROM
    for (int i = 0; i < NUM_FINGERS; i++) {
        char key[16];
        sprintf(key, "rom_%d", i);
        rx.requiredRom[i] = prefs.getInt(key, 0);
    }
    
    // Load sequence
    rx.sequenceCount = prefs.getInt("seqCount", 0);
    for (int i = 0; i < NUM_FINGERS; i++) {
        char key[16];
        sprintf(key, "seq_%d", i);
        rx.sequence[i] = prefs.getInt(key, 0);
    }
    
    // Load cubes
    rx.cubesCount = prefs.getInt("cubesCount", 0);
    for (int i = 0; i < rx.cubesCount; i++) {
        char keyUid[24], keyUidLen[24], keyCol[24], keyShp[24], keyWgt[24];
        sprintf(keyUid, "cube_uid_%d", i);
        sprintf(keyUidLen, "cube_len_%d", i);
        sprintf(keyCol, "cube_col_%d", i);
        sprintf(keyShp, "cube_shp_%d", i);
        sprintf(keyWgt, "cube_wgt_%d", i);
        
        rx.cubes[i].uid_len = prefs.getInt(keyUidLen, 0);
        if (rx.cubes[i].uid_len > 0) {
            prefs.getBytes(keyUid, rx.cubes[i].uid, rx.cubes[i].uid_len);
        }
        
        String col = prefs.getString(keyCol, "");
        String shp = prefs.getString(keyShp, "");
        strncpy(rx.cubes[i].color, col.c_str(), sizeof(rx.cubes[i].color) - 1);
        strncpy(rx.cubes[i].shape, shp.c_str(), sizeof(rx.cubes[i].shape) - 1);
        rx.cubes[i].weightGrams = prefs.getInt(keyWgt, 0);
    }
    
    prefs.end();
    Serial.println("[NVS] Game prescription loaded from NVS successfully.");
    return true;
}

extern SensorTelemetryData sharedTelemetry;
extern SemaphoreHandle_t telemetryMutex;

// ESP-NOW declarations
inline uint64_t macToKey_game(const uint8_t* mac) {
    uint64_t key = 0;
    for (int i = 0; i < 6; i++) {
        key = (key << 8) | mac[i];
    }
    return key;
}

inline void printMac_game(const uint8_t *mac) {
    for (int i = 0; i < 6; i++) {
        Serial.printf("%02X", mac[i]);
        if (i < 5) Serial.print(":");
    }
}

// Declarations of ESP-NOW sender helpers from glove_espnow.h
void sendLedColorToBox(const uint8_t *mac, uint8_t r, uint8_t g, uint8_t b);
void sendSuccessFlashToBoxes();
void sendFailureBlinkToBoxes();
void sendIdentifyToBox(const uint8_t *mac);

// Offline result buffer (defined in glove.ino/glove_network.h)
void saveSessionResultLocally(int gameType, int successes, int failures, unsigned long avgRespTimeMs, float avgForceOrRom);

// Helper: Convert color string to RGB
inline void colorToRgb(const char* color, uint8_t &r, uint8_t &g, uint8_t &b) {
    String c = String(color);
    c.toLowerCase();
    if (c == "red") { r = 255; g = 0; b = 0; }
    else if (c == "green") { r = 0; g = 255; b = 0; }
    else if (c == "blue") { r = 0; g = 0; b = 255; }
    else if (c == "yellow") { r = 255; g = 255; b = 0; }
    else if (c == "white") { r = 255; g = 255; b = 255; }
    else { r = 128; g = 0; b = 128; } // purple default
}

// Select next game target for Cubes & Boxes
inline void selectNextCubesBoxesTarget() {
    RegistryLock lock;
    if (boxRegistry.empty()) {
        Serial.println("[Game] Warning: No connected boxes for target selection!");
        return;
    }
    
    // Choose target box MAC
    auto it = boxRegistry.begin();
    int randBoxIdx = random(0, boxRegistry.size());
    for (int i = 0; i < randBoxIdx && it != boxRegistry.end(); i++) {
        it++;
    }
    if (it == boxRegistry.end()) it = boxRegistry.begin();
    
    memcpy(sessionState.targetBoxMac, it->second.mac, 6);
    
    // Translate key to index in registry
    int idx = 0;
    for (const auto& pair : boxRegistry) {
        if (pair.first == it->first) {
            sessionState.targetBoxIndex = idx;
            break;
        }
        idx++;
    }
    
    // Choose target cube
    if (currentPrescription.cubesCount > 0) {
        int randCubeIdx = random(0, currentPrescription.cubesCount);
        sessionState.targetCube = currentPrescription.cubes[randCubeIdx];
    } else {
        // Fallback default Red cube
        strcpy(sessionState.targetCube.color, "Red");
        strcpy(sessionState.targetCube.shape, "Circle");
        sessionState.targetCube.weightGrams = 100;
        sessionState.targetCube.uid_len = 0;
    }
    
    // Get RGB target
    uint8_t r, g, b;
    colorToRgb(sessionState.targetCube.color, r, g, b);
    
    // Turn off all box LEDs individually (reliable unicast)
    for (const auto& pair : boxRegistry) {
        sendLedColorToBox(pair.second.mac, 0, 0, 0);
        delay(10);
    }
    
    // Light up target box
    sendLedColorToBox(sessionState.targetBoxMac, r, g, b);
    
    sessionState.lastActionTime = millis();
    Serial.printf("[Game] Target set: Box [");
    printMac_game(sessionState.targetBoxMac);
    Serial.printf("] -> Color: %s, Weight: %dg, Shape: %s\n", 
                  sessionState.targetCube.color, sessionState.targetCube.weightGrams, sessionState.targetCube.shape);
}

// Start game session helper
inline void startNewGameSession() {
    if (currentPrescription.gameType == GAME_NONE) return;

    // Check if buffer is full (50 sessions) and offline (WiFi not connected)
    if (getBufferedLogCount() >= 50 && WiFi.status() != WL_CONNECTED) {
        Serial.println("[Game] Warning: Local log buffer is FULL (50 sessions) and offline. Circular buffer will overwrite oldest logs.");
    }
    
    Serial.printf("[Game] Starting Game Session. Type: %d, Timer: %ds, Cycles: %d\n", 
                  currentPrescription.gameType, currentPrescription.timerSeconds, currentPrescription.totalCycles);
    
    sessionState.active = true;
    sessionState.startTime = millis();
    sessionState.timerEndMillis = millis() + currentPrescription.timerSeconds * 1000;
    sessionState.lastCountdownTime = millis();
    sessionState.currentCycle = 0;
    sessionState.successCount = 0;
    sessionState.failureCount = 0;
    sessionState.totalResponseTimeMs = 0;
    sessionState.lastActionTime = millis();
    sessionState.isHolding = false;
    sessionState.holdStartTime = 0;
    sessionState.lastWarningTime = 0;
    sessionState.currentStepInSequence = 0;
    sessionState.sumSteadyForce = 0;
    sessionState.countSteadyForce = 0;
    sessionState.maxBendRom = 0;
    sessionState.sumHoldRom = 0;
    sessionState.played10sPrompt = false;
    sessionState.played5sPrompt = false;
    sessionState.countHoldRom = 0;
    
    // Speak Hebrew verbal instruction
    playStartPrompt(currentPrescription.gameType, currentPrescription.difficulty);
    sessionState.jingleResumeTime = millis() + 5500; // Let start instruction play, then start jingle
    
    // Initialize target box
    if (currentPrescription.gameType == GAME_CUBES_BOXES) {
        selectNextCubesBoxesTarget();
    } else if (currentPrescription.gameType == GAME_PINCH) {
        // Light up the target box in target color to prompt lift
        if (currentPrescription.cubesCount > 0) {
            sessionState.targetCube = currentPrescription.cubes[0];
        } else {
            strcpy(sessionState.targetCube.color, "Red");
            sessionState.targetCube.weightGrams = 100;
        }
        uint8_t r, g, b;
        colorToRgb(sessionState.targetCube.color, r, g, b);
        
        // Find if that cube is currently placed in a box
        uint8_t broadcastMac[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
        sendLedColorToBox(broadcastMac, 0, 0, 0);
        delay(20);
        
        // Find which box has the cube
        bool foundBox = false;
        for (const auto& pair : boxRegistry) {
            const RegisteredBox& box = pair.second;
            // Match UID or assume Box 0
            if (box.current_cube_len > 0) {
                sendLedColorToBox(box.mac, r, g, b);
                memcpy(sessionState.targetBoxMac, box.mac, 6);
                foundBox = true;
                break;
            }
        }
        if (!foundBox && !boxRegistry.empty()) {
            memcpy(sessionState.targetBoxMac, boxRegistry.begin()->second.mac, 6);
            sendLedColorToBox(sessionState.targetBoxMac, r, g, b);
        }
    }
}

// Stop game session helper
inline void stopGameSession(bool completedSuccessfully) {
    if (!sessionState.active) return;
    sessionState.active = false;
    
    Serial.println("[Game] Session finished.");
    
    // Turn off all box LEDs individually (reliable unicast)
    for (const auto& pair : boxRegistry) {
        sendLedColorToBox(pair.second.mac, 0, 0, 0);
        delay(10);
    }
    
    // Play end prompt
    if (completedSuccessfully) {
        playCompletionSound();
        sendSuccessFlashToBoxes();
    } else {
        playTimeoutSound();
        sendFailureBlinkToBoxes();
    }
    
    // Calculate average metrics
    unsigned long avgRespTime = 0;
    if (sessionState.successCount > 0) {
        avgRespTime = sessionState.totalResponseTimeMs / sessionState.successCount;
    }
    
    float avgForceOrRom = 0; // For Pinch or Bend
    if (currentPrescription.gameType == GAME_PINCH) {
        if (sessionState.countSteadyForce > 0) {
            avgForceOrRom = sessionState.sumSteadyForce / sessionState.countSteadyForce;
        } else {
            avgForceOrRom = currentPrescription.targetWeightGrams; // Fallback
        }
    } else if (currentPrescription.gameType == GAME_BEND) {
        avgForceOrRom = sessionState.maxBendRom;
    }
    
    // Save locally for offline synchronization
    saveSessionResultLocally(
        currentPrescription.gameType,
        sessionState.successCount,
        sessionState.failureCount,
        avgRespTime,
        avgForceOrRom
    );
}

// Handle local entered/left NFC events from the boxes in real-time
inline void handleLocalNfcEvent(String cubeId, int boxIndex, bool isPlaced, const uint8_t *boxMac) {
    if (!sessionState.active) return;
    
    Serial.printf("[Game-NFC] Event: Cube=%s, Box=%d, Placed=%s\n", 
                  cubeId.c_str(), boxIndex, isPlaced ? "TRUE" : "FALSE");
                  
    if (currentPrescription.gameType == GAME_CUBES_BOXES) {
        if (isPlaced) {
            // Match the cube details
            RxCube insertedCube;
            bool foundCube = false;
            for (int i = 0; i < currentPrescription.cubesCount; i++) {
                String rxUid = "";
                for (int j = 0; j < currentPrescription.cubes[i].uid_len; j++) {
                    char hex[3];
                    sprintf(hex, "%02X", currentPrescription.cubes[i].uid[j]);
                    rxUid += hex;
                }
                if (rxUid == cubeId) {
                    insertedCube = currentPrescription.cubes[i];
                    foundCube = true;
                    break;
                }
            }
            
            // Level 1: Fixed Color
            if (currentPrescription.difficulty == 1) {
                // Check if color matches target box LED color (or targetCube color)
                if (memcmp(boxMac, sessionState.targetBoxMac, 6) == 0 && 
                    (!foundCube || String(insertedCube.color) == String(sessionState.targetCube.color))) {
                    
                    sessionState.successCount++;
                    sessionState.totalResponseTimeMs += (millis() - sessionState.lastActionTime);
                    sessionState.currentCycle++;
                    
                    playSuccessSound();
                    sendSuccessFlashToBoxes();
                    
                    if (sessionState.currentCycle >= currentPrescription.totalCycles) {
                        stopGameSession(true);
                    } else {
                        delay(1500); // 1.5s feedback delay
                        selectNextCubesBoxesTarget();
                    }
                } else {
                    sessionState.failureCount++;
                    playFailureSound();
                    sendLedColorToBox(boxMac, 255, 0, 0); // Red on wrong box
                    delay(1000);
                    sendLedColorToBox(boxMac, 0, 0, 0); // Turn off wrong box
                    delay(20);
                    uint8_t r, g, b;
                    colorToRgb(sessionState.targetCube.color, r, g, b);
                    sendLedColorToBox(sessionState.targetBoxMac, r, g, b);
                }
            }
            // Level 2: Varying color and weights
            else if (currentPrescription.difficulty == 2) {
                // Must match targetBox AND targetCube (UID or properties)
                if (memcmp(boxMac, sessionState.targetBoxMac, 6) == 0 && foundCube &&
                    String(insertedCube.color) == String(sessionState.targetCube.color) &&
                    insertedCube.weightGrams == sessionState.targetCube.weightGrams) {
                    
                    sessionState.successCount++;
                    sessionState.totalResponseTimeMs += (millis() - sessionState.lastActionTime);
                    sessionState.currentCycle++;
                    
                    playSuccessSound();
                    sendSuccessFlashToBoxes();
                    
                    if (sessionState.currentCycle >= currentPrescription.totalCycles) {
                        stopGameSession(true);
                    } else {
                        delay(1500); // 1.5s feedback delay
                        selectNextCubesBoxesTarget();
                    }
                } else {
                    sessionState.failureCount++;
                    playFailureSound();
                    sendLedColorToBox(boxMac, 255, 0, 0); // Red on wrong box
                    delay(1000);
                    sendLedColorToBox(boxMac, 0, 0, 0); // Turn off wrong box
                    delay(20);
                    uint8_t r, g, b;
                    colorToRgb(sessionState.targetCube.color, r, g, b);
                    sendLedColorToBox(sessionState.targetBoxMac, r, g, b);
                }
            }
            // Level 3: Shape and Color matching
            else if (currentPrescription.difficulty == 3) {
                // Box has a shape cutout. Cube shape must match Box shape AND cube color must match LED.
                // In this simplified logic, the targetBoxMac represents the correct shape slot.
                if (memcmp(boxMac, sessionState.targetBoxMac, 6) == 0 && foundCube &&
                    String(insertedCube.shape) == String(sessionState.targetCube.shape) &&
                    String(insertedCube.color) == String(sessionState.targetCube.color)) {
                    
                    sessionState.successCount++;
                    sessionState.totalResponseTimeMs += (millis() - sessionState.lastActionTime);
                    sessionState.currentCycle++;
                    
                    playSuccessSound();
                    sendSuccessFlashToBoxes();
                    
                    if (sessionState.currentCycle >= currentPrescription.totalCycles) {
                        stopGameSession(true);
                    } else {
                        delay(1500); // 1.5s feedback delay
                        selectNextCubesBoxesTarget();
                    }
                } else {
                    sessionState.failureCount++;
                    playFailureSound();
                    sendLedColorToBox(boxMac, 255, 0, 0); // Red on wrong box
                    delay(1000);
                    sendLedColorToBox(boxMac, 0, 0, 0); // Turn off wrong box
                    delay(20);
                    uint8_t r, g, b;
                    colorToRgb(sessionState.targetCube.color, r, g, b);
                    sendLedColorToBox(sessionState.targetBoxMac, r, g, b);
                }
            }
        }
    }
    else if (currentPrescription.gameType == GAME_PINCH) {
        if (!isPlaced) {
            // Cube was lifted
            // Match the target cube
            String rxTargetUid = "";
            for (int j = 0; j < sessionState.targetCube.uid_len; j++) {
                char hex[3];
                sprintf(hex, "%02X", sessionState.targetCube.uid[j]);
                rxTargetUid += hex;
            }
            
            if (rxTargetUid.length() == 0 || rxTargetUid == cubeId) {
                Serial.println("[Game-Pinch] Correct cube lifted. Starting hold timer.");
                sessionState.isHolding = true;
                sessionState.holdStartTime = millis();
                
                // Turn off target box LED
                sendLedColorToBox(sessionState.targetBoxMac, 0, 0, 0);
                triggerHapticClick();
            } else {
                Serial.println("[Game-Pinch] Incorrect cube lifted.");
                playFailureSound();
            }
        } else {
            // Cube returned to box
            if (sessionState.isHolding) {
                Serial.println("[Game-Pinch] Cube returned before hold time finished.");
                sessionState.isHolding = false;
                playFailureSound();
                
                // Light up box LED again
                uint8_t r, g, b;
                colorToRgb(sessionState.targetCube.color, r, g, b);
                sendLedColorToBox(sessionState.targetBoxMac, r, g, b);
            }
        }
    }
}

// Periodically run game loops (timers, FSR pressure thresholds, flex ROM sequences)
inline void updateGame() {
    if (!sessionState.active) return;
    
    unsigned long now = millis();
    
    // Resume background jingle if resume timer expired
    if (sessionState.jingleResumeTime > 0 && now >= sessionState.jingleResumeTime) {
        sessionState.jingleResumeTime = 0;
        playTrack(4, 11); // Play "04/011.mp3" background jingle
        Serial.println("[Game] Resuming background jingle.");
    }
    
    // 1. Check timer expiration (only if timerSeconds is defined > 0)
    if (currentPrescription.timerSeconds > 0 && now >= sessionState.timerEndMillis) {
        Serial.println("[Game] Session timeout!");
        stopGameSession(false); // Fail due to timeout
        return;
    }
    
    // 2. Play countdown prompts at 10s and 5s remaining (only if there is an active timer)
    if (currentPrescription.timerSeconds > 0) {
        int secRemaining = (sessionState.timerEndMillis - now) / 1000;
        if (secRemaining <= 10 && secRemaining > 5 && !sessionState.played10sPrompt) {
            sessionState.played10sPrompt = true;
            playTrack(4, 9); // Play "עשר שניות" (04/009.mp3)
            Serial.println("[Game] Spoken countdown: 10 seconds remaining.");
        }
        else if (secRemaining <= 5 && secRemaining > 0 && !sessionState.played5sPrompt) {
            sessionState.played5sPrompt = true;
            playTrack(4, 10); // Play "חמש שניות" (04/010.mp3)
            Serial.println("[Game] Spoken countdown: 5 seconds remaining.");
        }
    }
    
    // 3. Monitor FSR force during Pinch Grip
    if (currentPrescription.gameType == GAME_PINCH) {
        if (sessionState.isHolding) {
            int currentForceRaw = 0;
            if (xSemaphoreTake(telemetryMutex, 0) == pdTRUE) {
                currentForceRaw = sharedTelemetry.forceRaw;
                xSemaphoreGive(telemetryMutex);
            }
            
            float forceGrams = getFsrForceGrams(currentForceRaw);
            
            if (forceGrams >= currentPrescription.targetWeightGrams) {
                // Vibrate glove haptics to confirm grip target force
                triggerHapticContinuous();
                
                // Filter out 2 seconds from the edges of the hold to clean movement noise
                float elapsedHoldSec = (now - sessionState.holdStartTime) / 1000.0f;
                float reqHoldSec = currentPrescription.requiredHoldTimeSeconds;
                float filterSec = 2.0f;
                if (reqHoldSec <= 4.0f) {
                    filterSec = reqHoldSec * 0.25f; // 25% filter if hold time is short
                }
                if (elapsedHoldSec >= filterSec && elapsedHoldSec <= (reqHoldSec - filterSec)) {
                    sessionState.sumSteadyForce += forceGrams;
                    sessionState.countSteadyForce++;
                }
                
                // Check if held long enough
                if (now - sessionState.holdStartTime >= currentPrescription.requiredHoldTimeSeconds * 1000) {
                    Serial.println("[Game-Pinch] Successfully completed pinch hold!");
                    
                    sessionState.successCount++;
                    sessionState.currentCycle++;
                    sessionState.isHolding = false;
                    
                    stopHapticContinuous();
                    playSuccessSound();
                    sendSuccessFlashToBoxes();
                    
                    if (sessionState.currentCycle >= currentPrescription.totalCycles) {
                        stopGameSession(true);
                    } else {
                        // Light box LED back on, wait for next lift
                        uint8_t r, g, b;
                        colorToRgb(sessionState.targetCube.color, r, g, b);
                        sendLedColorToBox(sessionState.targetBoxMac, r, g, b);
                        sessionState.holdStartTime = millis();
                    }
                }
            } else {
                // Force too low
                stopHapticContinuous();
                
                // Every 2 seconds warning
                if (now - sessionState.lastWarningTime >= 2000) {
                    sessionState.lastWarningTime = now;
                    playForceWarning(); // "Press harder"
                }
                
                // Reset continuous hold start timer
                sessionState.holdStartTime = now;
            }
        } else {
            stopHapticContinuous();
        }
    }
    // 4. Monitor flex sensors during Bend Grip
    else if (currentPrescription.gameType == GAME_BEND) {
        int activeFingerIndex = currentPrescription.sequence[sessionState.currentStepInSequence] - 1;
        if (activeFingerIndex >= 0 && activeFingerIndex < NUM_FINGERS) {
            int flexPct = 0;
            if (xSemaphoreTake(telemetryMutex, 0) == pdTRUE) {
                flexPct = sharedTelemetry.flexPercent[activeFingerIndex];
                xSemaphoreGive(telemetryMutex);
            }
            
            int targetRom = currentPrescription.requiredRom[activeFingerIndex];
            
            if (flexPct >= targetRom) {
                if (!sessionState.isHolding) {
                    sessionState.isHolding = true;
                    sessionState.holdStartTime = now;
                    playHoldPrompt();
                }
                
                triggerHapticContinuous();
                
                // Track max ROM reached during the hold state
                if (flexPct > sessionState.maxBendRom) {
                    sessionState.maxBendRom = flexPct;
                }
                
                // Check hold duration
                if (now - sessionState.holdStartTime >= currentPrescription.requiredHoldTimeSeconds * 1000) {
                    Serial.printf("[Game-Bend] Step %d (Finger %d) completed!\n", 
                                  sessionState.currentStepInSequence, activeFingerIndex + 1);
                    
                    stopHapticContinuous();
                    playSuccessSound();
                    sessionState.isHolding = false;
                    
                    sessionState.currentStepInSequence++;
                    if (sessionState.currentStepInSequence >= currentPrescription.sequenceCount) {
                        // All fingers in sequence bent!
                        sessionState.successCount++;
                        sessionState.currentCycle++;
                        sessionState.currentStepInSequence = 0; // reset sequence
                        
                        if (sessionState.currentCycle >= currentPrescription.totalCycles) {
                            stopGameSession(true);
                        } else {
                            playStartPrompt(GAME_BEND, 1);
                        }
                    } else {
                        // Prompt next finger in sequence
                        playHoldPrompt();
                    }
                }
            } else {
                stopHapticContinuous();
                if (sessionState.isHolding) {
                    sessionState.isHolding = false;
                    playFailureSound();
                }
            }
        }
    }
}
