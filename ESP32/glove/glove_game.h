#pragma once
#include <Arduino.h>
#include <vector>
#include "../parameters.h"
#include "glove_audio.h"
#include "glove_haptic.h"

// --- calibration data ---
extern int flexMin[NUM_FINGERS];
extern int flexMax[NUM_FINGERS];
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
    
    // Save previous target MAC and Cube Color
    uint8_t prevBoxMac[6];
    memcpy(prevBoxMac, sessionState.targetBoxMac, 6);
    String prevCubeColor = String(sessionState.targetCube.color);
    
    auto it = boxRegistry.begin();
    int randCubeIdx = 0;
    bool foundNew = false;
    int totalCombos = boxRegistry.size() * (currentPrescription.cubesCount > 0 ? currentPrescription.cubesCount : 1);
    
    for (int attempt = 0; attempt < 10; attempt++) {
        // Pick random box
        it = boxRegistry.begin();
        int randBoxIdx = random(0, boxRegistry.size());
        for (int i = 0; i < randBoxIdx && it != boxRegistry.end(); i++) {
            it++;
        }
        if (it == boxRegistry.end()) it = boxRegistry.begin();
        
        // Pick random cube
        RxCube candidateCube;
        if (currentPrescription.cubesCount > 0) {
            randCubeIdx = random(0, currentPrescription.cubesCount);
            candidateCube = currentPrescription.cubes[randCubeIdx];
        } else {
            strcpy(candidateCube.color, "Red");
            strcpy(candidateCube.shape, "Circle");
            candidateCube.weightGrams = 100;
            candidateCube.uid_len = 0;
        }
        
        bool isSameBox = (memcmp(it->second.mac, prevBoxMac, 6) == 0);
        bool isSameColor = (String(candidateCube.color) == prevCubeColor);
        
        if (totalCombos <= 1 || !(isSameBox && isSameColor)) {
            memcpy(sessionState.targetBoxMac, it->second.mac, 6);
            sessionState.targetCube = candidateCube;
            foundNew = true;
            break;
        }
    }
    
    if (!foundNew) {
        it = boxRegistry.begin();
        memcpy(sessionState.targetBoxMac, it->second.mac, 6);
        if (currentPrescription.cubesCount > 0) {
            sessionState.targetCube = currentPrescription.cubes[0];
        } else {
            strcpy(sessionState.targetCube.color, "Red");
            strcpy(sessionState.targetCube.shape, "Circle");
            sessionState.targetCube.weightGrams = 100;
            sessionState.targetCube.uid_len = 0;
        }
    }
    
    // Translate key to index in registry
    int idx = 0;
    for (const auto& pair : boxRegistry) {
        if (pair.first == it->first) {
            sessionState.targetBoxIndex = idx;
            break;
        }
        idx++;
    }
    
    // Get RGB target
    uint8_t r, g, b;
    colorToRgb(sessionState.targetCube.color, r, g, b);
    
    // Turn off non-target box LEDs, and light up target box (reliable unicast)
    // This prevents double-sending packet clashes or queue congestion on the target box!
    for (const auto& pair : boxRegistry) {
        if (memcmp(pair.second.mac, sessionState.targetBoxMac, 6) == 0) {
            sendLedColorToBox(pair.second.mac, r, g, b);
        } else {
            sendLedColorToBox(pair.second.mac, 0, 0, 0);
        }
        delay(15);
    }
    
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
    lastSessionCompletedSuccess = false;
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
    
    // Initialize target box
    if (currentPrescription.gameType == GAME_CUBES_BOXES) {
        selectNextCubesBoxesTarget();
    } else if (currentPrescription.gameType == GAME_PINCH) {
        // Pinch game: Phase 0 — waiting for correct cube placement
        sessionState.currentStepInSequence = 0;
        
        // Select target cube
        if (currentPrescription.cubesCount > 0) {
            sessionState.targetCube = currentPrescription.cubes[0];
        } else {
            strcpy(sessionState.targetCube.color, "Red");
            strcpy(sessionState.targetCube.shape, "Circle");
            sessionState.targetCube.weightGrams = 100;
            sessionState.targetCube.uid_len = 0;
        }
        
        // Find which box to use
        bool foundBox = false;
        for (const auto& pair : boxRegistry) {
            memcpy(sessionState.targetBoxMac, pair.second.mac, 6);
            foundBox = true;
            break;
        }
        
        if (foundBox) {
            // Light up target box
            uint8_t r, g, b;
            colorToRgb(sessionState.targetCube.color, r, g, b);
            sendLedColorToBox(sessionState.targetBoxMac, r, g, b);
        }

        // Check if the target cube is already placed in any box
        bool alreadyPlaced = false;
        for (const auto& pair : boxRegistry) {
            const RegisteredBox& box = pair.second;
            if (box.current_cube_len > 0) {
                String boxCubeUid = "";
                for (int j = 0; j < box.current_cube_len; j++) {
                    char hex[3];
                    sprintf(hex, "%02X", box.current_cube_uid[j]);
                    boxCubeUid += hex;
                }
                
                String targetUid = "";
                for (int j = 0; j < sessionState.targetCube.uid_len; j++) {
                    char hex[3];
                    sprintf(hex, "%02X", sessionState.targetCube.uid[j]);
                    targetUid += hex;
                }
                
                if (targetUid.length() == 0 || targetUid == boxCubeUid) {
                    alreadyPlaced = true;
                    if (foundBox) {
                        memcpy(sessionState.targetBoxMac, box.mac, 6);
                    }
                    break;
                }
            }
        }
        
        if (alreadyPlaced) {
            Serial.println("[Game-Pinch] Target cube is already placed. Advancing to Phase 1 immediately.");
            sessionState.currentStepInSequence = 1;
            
            // Light box in target color
            if (foundBox) {
                uint8_t r, g, b;
                colorToRgb(sessionState.targetCube.color, r, g, b);
                sendLedColorToBox(sessionState.targetBoxMac, r, g, b);
            }
            
            // Voice: "Lift and hold for X seconds"
            int holdSec = currentPrescription.requiredHoldTimeSeconds;
            int trackNum = 5 + (holdSec / 5);
            if (trackNum < 6) trackNum = 6;
            if (trackNum > 11) trackNum = 11;
            delay(3000); // Let start prompt finish
            playTrack(2, trackNum);
        } else {
            // Voice: "Place the correct weight in the box"
            delay(3000); // Let start prompt finish
            playTrack(2, 5); // 02/005.mp3
            Serial.println("[Game-Pinch] Phase 0: Waiting for cube placement in box.");
        }
    }
}

// Stop game session helper
inline void stopGameSession(bool completedSuccessfully) {
    if (!sessionState.active) return;
    sessionState.active = false;
    lastSessionCompletedSuccess = completedSuccessfully;
    
    Serial.println("[Game] Session finished.");
    
    // Turn off all box LEDs individually (reliable unicast)
    for (const auto& pair : boxRegistry) {
        sendLedColorToBox(pair.second.mac, 0, 0, 0);
        delay(10);
    }
    
    // Play end prompt
    if (completedSuccessfully) {
        if (currentPrescription.gameType == GAME_CUBES_BOXES) {
            playCubesBoxesSuccess();
            delay(1500);
            playCubesBoxesCompletion();
        } else if (currentPrescription.gameType == GAME_PINCH) {
            playPinchSuccess();
            delay(1500);
            playPinchCompletion();
        } else if (currentPrescription.gameType == GAME_BEND) {
            playBendSuccess();
            delay(1500);
            playBendCompletion();
        } else {
            playSuccessSound();
            delay(1200);
            playCompletionSound();
        }
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
    
    float avgForceOrRom = 0; // For Pinch or Bend or CubesBoxes
    if (currentPrescription.gameType == GAME_PINCH) {
        if (sessionState.countSteadyForce > 0) {
            avgForceOrRom = sessionState.sumSteadyForce / sessionState.countSteadyForce;
        } else {
            avgForceOrRom = currentPrescription.targetWeightGrams; // Fallback
        }
    } else if (currentPrescription.gameType == GAME_CUBES_BOXES) {
        if (sessionState.countSteadyForce > 0) {
            avgForceOrRom = sessionState.sumSteadyForce / sessionState.countSteadyForce;
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
            sessionState.isHolding = false;
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
                    
                    playCubesBoxesSuccess();
                    // Visual success: Turn correct box white for 1 second
                    sendLedColorToBox(boxMac, 255, 255, 255);
                    delay(1000);
                    sendLedColorToBox(boxMac, 0, 0, 0);
                    delay(500);
                    
                    if (sessionState.currentCycle >= currentPrescription.totalCycles) {
                        stopGameSession(true);
                    } else {
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
                    
                    playCubesBoxesSuccess();
                    // Visual success: Turn correct box white for 1 second
                    sendLedColorToBox(boxMac, 255, 255, 255);
                    delay(1000);
                    sendLedColorToBox(boxMac, 0, 0, 0);
                    delay(500);
                    
                    if (sessionState.currentCycle >= currentPrescription.totalCycles) {
                        stopGameSession(true);
                    } else {
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
                    
                    playCubesBoxesSuccess();
                    // Visual success: Turn correct box white for 1 second
                    sendLedColorToBox(boxMac, 255, 255, 255);
                    delay(1000);
                    sendLedColorToBox(boxMac, 0, 0, 0);
                    delay(500);
                    
                    if (sessionState.currentCycle >= currentPrescription.totalCycles) {
                        stopGameSession(true);
                    } else {
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
        } else {
            // Cube lifted — start carry force monitoring
            sessionState.isHolding = true;
            sessionState.holdStartTime = millis();
            Serial.println("[Game-CubesBoxes] Cube lifted. Carrying started.");
        }
    }
    else if (currentPrescription.gameType == GAME_PINCH) {
        if (memcmp(boxMac, sessionState.targetBoxMac, 6) != 0) return;
        
        // Phase 0: Waiting for cube placement
        if (sessionState.currentStepInSequence == 0) {
            if (isPlaced) {
                // Cube placed in box — verify it's the correct one
                String rxTargetUid = "";
                for (int j = 0; j < sessionState.targetCube.uid_len; j++) {
                    char hex[3];
                    sprintf(hex, "%02X", sessionState.targetCube.uid[j]);
                    rxTargetUid += hex;
                }
                
                bool cubeMatch = (rxTargetUid.length() == 0 || rxTargetUid == cubeId);
                if (cubeMatch) {
                    Serial.println("[Game-Pinch] Correct cube placed. Phase 1: Waiting for lift.");
                    sessionState.currentStepInSequence = 1;
                    
                    // Flash box white briefly to confirm placement
                    sendLedColorToBox(boxMac, 255, 255, 255);
                    delay(500);
                    
                    // Light box in target color 
                    uint8_t r, g, b;
                    colorToRgb(sessionState.targetCube.color, r, g, b);
                    sendLedColorToBox(sessionState.targetBoxMac, r, g, b);
                    
                    // Voice: "Lift and hold for X seconds"
                    int holdSec = currentPrescription.requiredHoldTimeSeconds;
                    int trackNum = 5 + (holdSec / 5); // 5s→6, 10s→7, 15s→8, 20s→9, 25s→10, 30s→11
                    if (trackNum < 6) trackNum = 6;
                    if (trackNum > 11) trackNum = 11;
                    playTrack(2, trackNum);
                    Serial.printf("[Game-Pinch] Prompted: lift and hold for %d seconds (track 02/%03d).\n", holdSec, trackNum);
                    
                    triggerHapticClick();
                } else {
                    Serial.println("[Game-Pinch] Wrong cube placed.");
                    playFailureSound();
                }
            }
        }
        // Phase 1: Cube is in box, waiting for lift
        else if (sessionState.currentStepInSequence == 1) {
            if (!isPlaced) {
                // Cube lifted — start hold timer (Phase 2)
                Serial.println("[Game-Pinch] Cube lifted! Phase 2: Hold timer started.");
                sessionState.currentStepInSequence = 2;
                sessionState.isHolding = true;
                sessionState.holdStartTime = millis();
                
                // Turn off box LED while holding
                sendLedColorToBox(sessionState.targetBoxMac, 0, 0, 0);
                triggerHapticClick();
            }
        }
        // Phase 2: Cube is lifted, hold timer running
        else if (sessionState.currentStepInSequence == 2) {
            if (isPlaced) {
                // Cube returned too early — failure
                Serial.println("[Game-Pinch] Cube returned before hold time. Failure!");
                sessionState.isHolding = false;
                sessionState.failureCount++;
                stopHapticContinuous();
                playFailureSound();
                
                // Go back to Phase 1 (cube is in box, wait for re-lift)
                sessionState.currentStepInSequence = 1;
                uint8_t r, g, b;
                colorToRgb(sessionState.targetCube.color, r, g, b);
                sendLedColorToBox(sessionState.targetBoxMac, r, g, b);
                
                // Re-prompt the lift instruction
                int holdSec = currentPrescription.requiredHoldTimeSeconds;
                int trackNum = 5 + (holdSec / 5);
                if (trackNum < 6) trackNum = 6;
                if (trackNum > 11) trackNum = 11;
                delay(1500);
                playTrack(2, trackNum);
            }
        }
    }
}

// Periodically run game loops (timers, FSR pressure thresholds, flex ROM sequences)
inline void updateGame() {
    if (!sessionState.active) return;
    
    unsigned long now = millis();

    // Accumulate force metrics when holding/carrying a cube/block
    if (currentPrescription.gameType == GAME_CUBES_BOXES || currentPrescription.gameType == GAME_PINCH) {
        bool isPinchHold = (currentPrescription.gameType == GAME_PINCH && sessionState.currentStepInSequence == 2 && sessionState.isHolding);
        bool isCubesCarry = (currentPrescription.gameType == GAME_CUBES_BOXES && sessionState.isHolding);
        
        if (isPinchHold || isCubesCarry) {
            int currentForceRaw = 0;
            if (xSemaphoreTake(telemetryMutex, 0) == pdTRUE) {
                currentForceRaw = sharedTelemetry.forceRaw;
                xSemaphoreGive(telemetryMutex);
            }
            float forceGrams = getFsrForceGrams(currentForceRaw);
            sessionState.sumSteadyForce += forceGrams;
            sessionState.countSteadyForce++;
        }
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
    
    // 3. Monitor hold timer during Pinch Grip (Phase 2 only — cube is lifted)
    if (currentPrescription.gameType == GAME_PINCH) {
        if (sessionState.currentStepInSequence == 2 && sessionState.isHolding) {
            // Check if held long enough
            if (now - sessionState.holdStartTime >= (unsigned long)currentPrescription.requiredHoldTimeSeconds * 1000) {
                Serial.println("[Game-Pinch] Successfully held cube for required duration!");
                
                sessionState.successCount++;
                sessionState.currentCycle++;
                sessionState.isHolding = false;
                
                playPinchSuccess();
                sendSuccessFlashToBoxes();
                
                if (sessionState.currentCycle >= currentPrescription.totalCycles) {
                    stopGameSession(true);
                } else {
                    // Next cycle: go back to Phase 0 (waiting for placement)
                    sessionState.currentStepInSequence = 0;
                    delay(1500);
                    
                    // Light box back up and prompt placement
                    uint8_t r, g, b;
                    colorToRgb(sessionState.targetCube.color, r, g, b);
                    sendLedColorToBox(sessionState.targetBoxMac, r, g, b);
                    playTrack(2, 5); // "Place the weight in the box"
                    Serial.println("[Game-Pinch] Phase 0: Waiting for next cube placement.");
                }
            }
        }
    }
    else if (currentPrescription.gameType == GAME_BEND) {
        int maxFlexPct = 0;
        if (xSemaphoreTake(telemetryMutex, 0) == pdTRUE) {
            for (int i = 0; i < NUM_FINGERS; i++) {
                if (sharedTelemetry.flexPercent[i] > maxFlexPct) {
                    maxFlexPct = sharedTelemetry.flexPercent[i];
                }
            }
            xSemaphoreGive(telemetryMutex);
        }
        
        int targetRom = currentPrescription.requiredRom[0];
        
        // Phase 0: Waiting for release (straight hand, flex < 20%)
        if (sessionState.currentStepInSequence == 0) {
            if (maxFlexPct < 20) {
                Serial.println("[Game-Bend] Hand straight. Phase 1: Prompting bend.");
                sessionState.currentStepInSequence = 1;
                playTrack(3, 2); // "כופף את האצבע והחזק אותה מכופפת"
            }
        }
        // Phase 1: Waiting for bend (flex >= targetRom)
        else if (sessionState.currentStepInSequence == 1) {
            if (maxFlexPct >= targetRom) {
                Serial.println("[Game-Bend] ROM target reached! Phase 2: Start hold.");
                sessionState.currentStepInSequence = 2;
                sessionState.isHolding = true;
                sessionState.holdStartTime = now;
                playHoldPrompt(); // "החזק"
            }
        }
        // Phase 2: Holding
        else if (sessionState.currentStepInSequence == 2) {
            if (maxFlexPct >= targetRom) {
                triggerHapticContinuous();
                
                if (maxFlexPct > sessionState.maxBendRom) {
                    sessionState.maxBendRom = maxFlexPct;
                }
                
                // Check hold duration
                if (now - sessionState.holdStartTime >= (unsigned long)currentPrescription.requiredHoldTimeSeconds * 1000) {
                    Serial.println("[Game-Bend] Cycle completed successfully!");
                    stopHapticContinuous();
                    playBendSuccess(); // "כיפוף מעולה, שחרר את האצבע."
                    
                    sessionState.isHolding = false;
                    sessionState.successCount++;
                    sessionState.currentCycle++;
                    
                    if (sessionState.currentCycle >= currentPrescription.totalCycles) {
                        stopGameSession(true);
                    } else {
                        // Go back to Phase 0 (waiting for release)
                        sessionState.currentStepInSequence = 0;
                        delay(2000); // Give time for success prompt to speak
                        playReleasePrompt(); // "שחרר את האצבע" (04/008)
                    }
                }
            } else {
                // Released too early - failure
                Serial.println("[Game-Bend] Released too early. Failure!");
                stopHapticContinuous();
                sessionState.isHolding = false;
                sessionState.failureCount++;
                playFailureSound();
                
                // Go back to Phase 1 (waiting for bend)
                sessionState.currentStepInSequence = 1;
                delay(1500);
                playTrack(3, 2); // Re-prompt bend
            }
        }
    }
}
