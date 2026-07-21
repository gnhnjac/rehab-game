#ifndef GLOVE_SYNC_H
#define GLOVE_SYNC_H

#include <Arduino.h>
#include <FS.h>
#include <SPIFFS.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include "glove_network.h"
#include "glove_secrets.h"

// Convert epoch time to RFC 3339 string (e.g., 2026-07-14T14:02:00Z)
inline String formatRfc3339(uint32_t epochTime) {
    time_t rawtime = epochTime;
    struct tm * ti;
    ti = gmtime(&rawtime);
    char buffer[25];
    sprintf(buffer, "%04d-%02d-%02dT%02d:%02d:%02dZ", 
            ti->tm_year + 1900, ti->tm_mon + 1, ti->tm_mday, 
            ti->tm_hour, ti->tm_min, ti->tm_sec);
    return String(buffer);
}

// Wrap parameters into Firestore Document REST JSON structure
inline String buildFirestoreDocument(const String& patientId, const String& gameType, int successCount, int totalCycles, const String& timestampRfc, const String& metricsFieldsJson) {
    String json = "{\"fields\":{";
    json += "\"patientId\":{\"stringValue\":\"" + patientId + "\"},";
    json += "\"gameType\":{\"stringValue\":\"" + gameType + "\"},";
    json += "\"successCount\":{\"integerValue\":\"" + String(successCount) + "\"},";
    json += "\"totalCycles\":{\"integerValue\":\"" + String(totalCycles) + "\"},";
    json += "\"timestamp\":{\"timestampValue\":\"" + timestampRfc + "\"},";
    json += "\"metrics\":{\"mapValue\":{\"fields\":" + metricsFieldsJson + "}}";
    json += "}}";
    return json;
}

// Initialize SPIFFS
inline void setupSPIFFS() {
    if (!SPIFFS.begin(true)) {
        Serial.println("[SPIFFS] Error: Mount failed! Formatting SPIFFS...");
    } else {
        Serial.println("[SPIFFS] SPIFFS mounted successfully.");
    }
}

// Get count of buffered logs
inline int getBufferedLogCount() {
    File root = SPIFFS.open("/");
    if (!root) return 0;
    
    int count = 0;
    File file = root.openNextFile();
    while (file) {
        String filename = String(file.name());
        if (filename.startsWith("/")) {
            filename = filename.substring(1);
        }
        if (filename.startsWith("log_") && filename.endsWith(".json")) {
            count++;
        }
        file.close();
        file = root.openNextFile();
    }
    return count;
}

// Find and remove oldest log file to maintain circular buffer
inline void removeOldestLog() {
    File root = SPIFFS.open("/");
    if (!root) return;
    
    String oldestFilename = "";
    uint32_t oldestEpoch = 0xFFFFFFFF;
    
    File file = root.openNextFile();
    while (file) {
        String filename = String(file.name());
        if (filename.startsWith("/")) {
            filename = filename.substring(1);
        }
        if (filename.startsWith("log_") && filename.endsWith(".json")) {
            int underscoreIdx = filename.indexOf('_');
            int nextUnderscoreIdx = filename.indexOf('_', underscoreIdx + 1);
            if (underscoreIdx != -1 && nextUnderscoreIdx != -1) {
                String epochStr = filename.substring(underscoreIdx + 1, nextUnderscoreIdx);
                uint32_t epoch = strtoul(epochStr.c_str(), NULL, 10);
                if (epoch < oldestEpoch) {
                    oldestEpoch = epoch;
                    oldestFilename = "/" + filename;
                }
            }
        }
        file.close();
        file = root.openNextFile();
    }
    
    if (oldestFilename.length() > 0) {
        SPIFFS.remove(oldestFilename);
        Serial.printf("[SPIFFS] Circular buffer: Deleted oldest log: %s\n", oldestFilename.c_str());
    }
}

// Buffer completed game session log locally to SPIFFS
inline void bufferGameSessionLog(const String& patientId, const String& gameType, int successCount, int totalCycles, const String& metricsFieldsJson) {
    // If the local log buffer is full, remove the oldest log to maintain circular buffer space
    if (getBufferedLogCount() >= 50) {
        Serial.println("[Buffer] Warning: Log buffer limit reached (50). Overwriting oldest log...");
        removeOldestLog();
    }

    uint32_t epoch = getEpochTime();
    String timestampRfc = formatRfc3339(epoch);
    String payload = buildFirestoreDocument(patientId, gameType, successCount, totalCycles, timestampRfc, metricsFieldsJson);

    // Create unique file name
    String filepath = "/log_" + String(epoch) + "_" + String(random(1000, 9999)) + ".json";
    
    File file = SPIFFS.open(filepath, "w");
    if (file) {
        file.print(payload);
        file.close();
        Serial.printf("[Buffer] Session log saved locally: %s\n", filepath.c_str());
    } else {
        Serial.printf("[Buffer] Error: Failed to open %s for writing!\n", filepath.c_str());
    }
}

// Upload a single log file to Firestore REST API
inline bool uploadLogToFirestore(const String& jsonPayload) {
    if (WiFi.status() != WL_CONNECTED) {
        return false;
    }

    WiFiClientSecure client;
    client.setInsecure(); // Bypass SSL validation for Google API

    HTTPClient http;
    String url = "https://firestore.googleapis.com/v1/projects/" + String(FIREBASE_PROJECT_ID) + "/databases/(default)/documents/game_history";
    
    http.begin(client, url);
    http.addHeader("Content-Type", "application/json");
    http.setTimeout(3000); // 3-second timeout

    int httpResponseCode = http.POST(jsonPayload);
    bool success = false;
    
    if (httpResponseCode == 200 || httpResponseCode == 201) {
        Serial.println("[Sync] Log uploaded successfully to Firestore.");
        success = true;
    } else {
        Serial.printf("[Sync] Upload failed. HTTP Code: %d\n", httpResponseCode);
        if (httpResponseCode <= 0) {
            Serial.printf("[Sync] Connection error: %s\n", http.errorToString(httpResponseCode).c_str());
        } else {
            String response = http.getString();
            Serial.printf("[Sync] Server Response: %s\n", response.c_str());
        }
    }
    http.end();
    return success;
}

// Synchronize all buffered SPIFFS logs to Firestore
inline void syncBufferedLogs() {
    if (WiFi.status() != WL_CONNECTED) {
        return; // Offline, can't sync
    }

    File root = SPIFFS.open("/");
    if (!root) {
        Serial.println("[Sync] Error: Failed to open SPIFFS root!");
        return;
    }

    File file = root.openNextFile();
    int syncCount = 0;

    while (file) {
        String filename = String(file.name());
        if (filename.startsWith("/")) {
            filename = filename.substring(1);
        }
        
        // Match only log files
        if (filename.startsWith("log_") && filename.endsWith(".json")) {
            // Absolute path
            String filepath = "/" + filename;
            Serial.printf("[Sync] Found buffered log: %s. Synchronizing...\n", filepath.c_str());


            // Read log file content
            String jsonPayload = "";
            while (file.available()) {
                jsonPayload += (char)file.read();
            }
            file.close(); // Close before upload/delete

            // Attempt upload
            if (uploadLogToFirestore(jsonPayload)) {
                // If successful, delete the local file
                if (SPIFFS.remove(filepath)) {
                    Serial.printf("[Sync] Local file %s deleted.\n", filepath.c_str());
                    syncCount++;
                } else {
                    Serial.printf("[Sync] Error: Failed to delete local file %s\n", filepath.c_str());
                }
            } else {
                Serial.printf("[Sync] Skipping %s for now (upload failed).\n", filepath.c_str());
                // Re-open root and break to try again later, avoiding locks
                break;
            }
        } else {
            file.close();
        }
        
        file = root.openNextFile();
    }
    
    if (syncCount > 0) {
        Serial.printf("[Sync] Complete. Total files synchronized: %d\n", syncCount);
    }
}



// Global Preferences from glove.ino
extern Preferences preferences;

inline void saveSessionResultLocally(int gameType, int successes, int failures, unsigned long avgRespTimeMs, float avgForceOrRom) {
    Serial.println("\n===== GAME OVER LOGS =====");
    Serial.printf("Game Type: %d\n", gameType);
    Serial.printf("Success Count: %d\n", successes);
    Serial.printf("Failure Count: %d\n", failures);
    Serial.printf("Average Response Time: %lu ms\n", avgRespTimeMs);
    Serial.printf("Average Force/ROM: %.2f\n", avgForceOrRom);
    Serial.println("==========================\n");

    // 1. Convert gameType to string
    String gameTypeStr = "Unknown";
    if (gameType == 1) gameTypeStr = "CubesBoxes";
    else if (gameType == 2) gameTypeStr = "Pinch";
    else if (gameType == 3) gameTypeStr = "Bend";

    // 2. Read active patient ID from preferences (default to "OFFLINE_PATIENT")
    preferences.begin("calibration", true); 
    String patientId = preferences.getString("activePatientId", "OFFLINE_PATIENT");
    preferences.end();

    // 3. Construct the metrics JSON string in Firestore REST format
    String romThumbVal = String((double)sessionState.maxRomPerFinger[0]);
    String romIndexVal = String((double)sessionState.maxRomPerFinger[1]);
    String romMiddleVal = String((double)sessionState.maxRomPerFinger[2]);
    String romRingVal = String((double)sessionState.maxRomPerFinger[3]);
    String romPinkyVal = String((double)sessionState.maxRomPerFinger[4]);

    String fingerRomJson = ",\"romThumb\":{\"doubleValue\":" + romThumbVal + "}" +
                           ",\"romIndex\":{\"doubleValue\":" + romIndexVal + "}" +
                           ",\"romMiddle\":{\"doubleValue\":" + romMiddleVal + "}" +
                           ",\"romRing\":{\"doubleValue\":" + romRingVal + "}" +
                           ",\"romPinky\":{\"doubleValue\":" + romPinkyVal + "}";

    String metricsJson = "";
    if (gameType == 1) { // CubesBoxes
        metricsJson = "{\"avgResponseTimeMs\":{\"doubleValue\":" + String((double)avgRespTimeMs) + "},\"avgGripForceGrams\":{\"doubleValue\":" + String(avgForceOrRom) + "},\"levelCompleted\":{\"integerValue\":\"" + String(successes) + "\"}" + fingerRomJson + "}";
    }
    else if (gameType == 2) { // Pinch
        metricsJson = "{\"avgGripForceGrams\":{\"doubleValue\":" + String(avgForceOrRom) + "},\"avgResponseTimeMs\":{\"doubleValue\":" + String((double)avgRespTimeMs) + "},\"succeeded\":{\"booleanValue\":true}" + fingerRomJson + "}";
    }
    else if (gameType == 3) { // Bend
        metricsJson = "{\"avgRomPercent\":{\"doubleValue\":" + String(avgForceOrRom) + "},\"avgResponseTimeMs\":{\"doubleValue\":" + String((double)avgRespTimeMs) + "},\"sequenceCompleted\":{\"booleanValue\":true}" + fingerRomJson + "}";
    } else {
        metricsJson = "{}";
    }

    // 4. Buffer the log to SPIFFS
    bufferGameSessionLog(patientId, gameTypeStr, successes, successes + failures, metricsJson);
}

#endif // GLOVE_SYNC_H
