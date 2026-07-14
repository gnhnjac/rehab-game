#ifndef GLOVE_WEBSERVER_H
#define GLOVE_WEBSERVER_H

#include <WebServer.h>
#include <Preferences.h>
#include "../parameters.h"
#include "glove_sensors.h"

extern WebServer server;
extern Preferences preferences;

// JSON parsing helper functions (standalone, zero dependencies)
inline void parseJsonArray(const String& json, const String& key, int* output, int size) {
    int keyIdx = json.indexOf("\"" + key + "\"");
    if (keyIdx == -1) return;
    int startBracket = json.indexOf("[", keyIdx);
    int endBracket = json.indexOf("]", startBracket);
    if (startBracket == -1 || endBracket == -1) return;
    String arrayContent = json.substring(startBracket + 1, endBracket);
    
    int currentIdx = 0;
    for (int i = 0; i < size; i++) {
        int nextComma = arrayContent.indexOf(",", currentIdx);
        if (nextComma == -1) {
            output[i] = arrayContent.substring(currentIdx).toInt();
            break;
        } else {
            output[i] = arrayContent.substring(currentIdx, nextComma).toInt();
            currentIdx = nextComma + 1;
        }
    }
}

inline int parseJsonInt(const String& json, const String& key) {
    int keyIdx = json.indexOf("\"" + key + "\"");
    if (keyIdx == -1) return 0;
    int colonIdx = json.indexOf(":", keyIdx);
    if (colonIdx == -1) return 0;
    
    int startIdx = colonIdx + 1;
    while (startIdx < json.length() && (json[startIdx] == ' ' || json[startIdx] == '\t' || json[startIdx] == '\n' || json[startIdx] == '\r')) {
        startIdx++;
    }
    
    int endIdx = startIdx;
    while (endIdx < json.length() && ((json[endIdx] >= '0' && json[endIdx] <= '9') || json[endIdx] == '-')) {
        endIdx++;
    }
    return json.substring(startIdx, endIdx).toInt();
}

// Route handlers
inline void handleRawSensors() {
    int flexRaw[NUM_FINGERS];
    int flexPercent[NUM_FINGERS];
    int forceRaw = 0;
    int forcePercent = 0;
    readAllSensors(flexRaw, flexPercent, forceRaw, forcePercent);

    String json = "{\"flex\":[";
    for (int i = 0; i < NUM_FINGERS; i++) {
        json += String(flexRaw[i]);
        if (i < NUM_FINGERS - 1) json += ",";
    }
    json += "],\"force\":" + String(forceRaw) + "}";
    
    server.send(200, "application/json", json);
}

inline void handleCalibrateSensor() {
    if (!server.hasArg("plain")) {
        server.send(400, "application/json", "{\"status\":\"error\",\"message\":\"Missing body\"}");
        return;
    }
    
    String body = server.arg("plain");
    Serial.println("[WebServer] Received calibration coefficients:");
    Serial.println(body);

    int newFlexMin[NUM_FINGERS];
    int newFlexMax[NUM_FINGERS];
    
    // Set default fallbacks in case parsing fails
    memcpy(newFlexMin, flexMin, sizeof(flexMin));
    memcpy(newFlexMax, flexMax, sizeof(flexMax));
    
    parseJsonArray(body, "flex_min", newFlexMin, NUM_FINGERS);
    parseJsonArray(body, "flex_max", newFlexMax, NUM_FINGERS);
    
    int newForceMin = parseJsonInt(body, "force_min");
    int newForceMax = parseJsonInt(body, "force_max");

    // Copy to active variables in glove_sensors.h
    memcpy(flexMin, newFlexMin, sizeof(flexMin));
    memcpy(flexMax, newFlexMax, sizeof(flexMax));
    forceMin = newForceMin;
    forceMax = newForceMax;
    isCalibrated = true;

    // Prevent division by zero
    for (int i = 0; i < NUM_FINGERS; i++) {
        if (flexMax[i] == flexMin[i]) flexMax[i]++;
        flexSmoothed[i] = analogRead(flexPins[i]); // Re-seed filter
    }
    if (forceMax == forceMin) forceMax++;
    forceSmoothed = analogRead(FORCE_PIN); // Re-seed filter

    // Save permanently to Preferences
    preferences.begin("calib", false);
    preferences.putBytes("flexMin", flexMin, sizeof(flexMin));
    preferences.putBytes("flexMax", flexMax, sizeof(flexMax));
    preferences.putInt("forceMin", forceMin);
    preferences.putInt("forceMax", forceMax);
    preferences.putBool("isCalibrated", isCalibrated);
    preferences.end();

    Serial.println("[WebServer] Calibration updated and saved to NVS.");
    server.send(200, "application/json", "{\"status\":\"success\"}");
}

inline void handleActivePrescription() {
    if (!server.hasArg("plain")) {
        server.send(400, "application/json", "{\"status\":\"error\",\"message\":\"Missing body\"}");
        return;
    }
    
    String body = server.arg("plain");
    Serial.println("[WebServer] Received active prescription payload:");
    Serial.println(body);

    // Save to Preferences
    preferences.begin("glove", false);
    preferences.putString("prescription", body);
    preferences.end();

    Serial.println("[WebServer] Active prescription saved to NVS.");
    server.send(200, "application/json", "{\"status\":\"success\"}");
}

inline void setupWebServer() {
    server.on("/api/raw-sensors", HTTP_GET, handleRawSensors);
    server.on("/api/calibrate-sensor", HTTP_POST, handleCalibrateSensor);
    server.on("/api/active-prescription", HTTP_POST, handleActivePrescription);
    
    // Add CORS headers support for web app direct connection
    server.enableCORS(true);
    
    server.begin();
    Serial.println("[WebServer] HTTP WebServer started on port 80.");
}

#endif // GLOVE_WEBSERVER_H
