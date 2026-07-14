#ifndef GLOVE_SYNC_H
#define GLOVE_SYNC_H

#include <Arduino.h>
#include <FS.h>
#include <SPIFFS.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include "glove_firebase.h"
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

// Buffer completed game session log locally to SPIFFS
inline void bufferGameSessionLog(const String& patientId, const String& gameType, int successCount, int totalCycles, const String& metricsFieldsJson) {
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
    String metricsJson = "";
    if (gameType == 1) { // CubesBoxes
        metricsJson = "{\"avgResponseTimeSeconds\":{\"doubleValue\":" + String(avgRespTimeMs / 1000.0) + "},\"levelCompleted\":{\"integerValue\":\"" + String(successes) + "\"}}";
    }
    else if (gameType == 2) { // Pinch
        metricsJson = "{\"avgSteadyStateForceGrams\":{\"doubleValue\":" + String(avgForceOrRom) + "},\"maxHoldTimeSeconds\":{\"doubleValue\":" + String(avgRespTimeMs / 1000.0) + "},\"succeeded\":{\"booleanValue\":true}}";
    }
    else if (gameType == 3) { // Bend
        metricsJson = "{\"avgRomReached\":{\"arrayValue\":{\"values\":[{\"integerValue\":\"" + String((int)avgForceOrRom) + "\"}]}},\"sequenceCompleted\":{\"booleanValue\":true}}";
    } else {
        metricsJson = "{}";
    }

    // 4. Buffer the log to SPIFFS
    bufferGameSessionLog(patientId, gameTypeStr, successes, successes + failures, metricsJson);
}

#endif // GLOVE_SYNC_H
