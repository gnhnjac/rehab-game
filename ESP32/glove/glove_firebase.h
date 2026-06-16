#ifndef GLOVE_FIREBASE_H
#define GLOVE_FIREBASE_H

#include <WiFi.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include <time.h>
#include "glove_secrets.h"

// Track time sync state
bool ntpInitialized = false;

// Queue structure to defer REST operations out of the ESP-NOW callback context
struct BoxActionEvent {
    String cubeId;
    uint32_t timestamp;
    bool isPlaced;
    int boxIndex;
};

#define MAX_PENDING_EVENTS 10
BoxActionEvent eventQueue[MAX_PENDING_EVENTS];
volatile int queueHead = 0;
volatile int queueTail = 0;

inline bool pushEvent(const String& cubeId, uint32_t timestamp, bool isPlaced, int boxIndex) {
    int nextTail = (queueTail + 1) % MAX_PENDING_EVENTS;
    if (nextTail == queueHead) {
        return false; // Queue full
    }
    eventQueue[queueTail].cubeId = cubeId;
    eventQueue[queueTail].timestamp = timestamp;
    eventQueue[queueTail].isPlaced = isPlaced;
    eventQueue[queueTail].boxIndex = boxIndex;
    queueTail = nextTail;
    return true;
}

inline bool popEvent(BoxActionEvent& event) {
    if (queueHead == queueTail) {
        return false; // Queue empty
    }
    event = eventQueue[queueHead];
    queueHead = (queueHead + 1) % MAX_PENDING_EVENTS;
    return true;
}

inline void setupWifi() {
    Serial.println();
    Serial.printf("[Wi-Fi] Connecting to network: %s\n", WIFI_SSID);
    
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    
    // We connect synchronously in setup to guarantee time sync and lock channel before ESP-NOW starts
    int retries = 0;
    while (WiFi.status() != WL_CONNECTED && retries < 20) {
        delay(500);
        Serial.print(".");
        retries++;
    }
    
    if (WiFi.status() == WL_CONNECTED) {
        Serial.println("\n[Wi-Fi] Connected successfully!");
        Serial.print("[Wi-Fi] IP Address: ");
        Serial.println(WiFi.localIP());
        Serial.printf("[Wi-Fi] Operating Channel: %d\n", WiFi.channel());
    } else {
        Serial.println("\n[Wi-Fi] Connection timed out! Operating in standalone ESP-NOW mode.");
    }
}

inline uint32_t getEpochTime() {
    if (WiFi.status() != WL_CONNECTED) return millis() / 1000; // fallback relative time
    
    if (!ntpInitialized) {
        // Configure NTP. GMT Offset is 0, daylight offset is 0.
        configTime(0, 0, "pool.ntp.org", "time.nist.gov");
        Serial.println("[NTP] Initializing time sync...");
        ntpInitialized = true;
        
        // Wait up to 3 seconds for initial sync
        int timeRetries = 0;
        time_t temp = time(nullptr);
        while (temp < 1600000000 && timeRetries < 30) {
            delay(100);
            temp = time(nullptr);
            timeRetries++;
        }
    }
    
    time_t now = time(nullptr);
    if (now < 1600000000) {
        return millis() / 1000; // fallback relative time if sync fails
    }
    return (uint32_t)now;
}

// Clean trailing slashes from database host to ensure well-formed URLs
inline String getCleanFirebaseUrl(const String& path) {
    String host = String(FIREBASE_HOST);
    host.trim();
    while (host.endsWith("/")) {
        host = host.substring(0, host.length() - 1);
    }
    return host + path;
}

// Diagnostic helper to print network status, DNS resolution, and heap on HTTP failure
inline void printFirebaseErrorDiagnostics(int responseCode) {
    Serial.printf("[Firebase] HTTP Fail Code: %d (%s)\n", 
        responseCode, HTTPClient::errorToString(responseCode).c_str());

    String host = String(FIREBASE_HOST);
    host.trim();
    if (host.startsWith("https://")) host = host.substring(8);
    if (host.startsWith("http://")) host = host.substring(7);
    int slashIdx = host.indexOf('/');
    if (slashIdx != -1) host = host.substring(0, slashIdx);

    IPAddress resolvedIP;
    if (WiFi.hostByName(host.c_str(), resolvedIP)) {
        Serial.printf("[Firebase] Diagnostics: DNS lookup OK (%s -> %s)\n", 
            host.c_str(), resolvedIP.toString().c_str());
    } else {
        Serial.printf("[Firebase] Diagnostics: DNS lookup FAILED for %s\n", host.c_str());
    }

    Serial.printf("[Firebase] Diagnostics: Free Heap = %d bytes\n", ESP.getFreeHeap());
    Serial.printf("[Firebase] Diagnostics: Wi-Fi Status = %d (3 = Connected)\n", WiFi.status());
}

inline void uploadLiveTelemetry(bool calibrated, int* flexRaw, int* flexPercent, int forceRaw, int forcePercent) {
    if (WiFi.status() != WL_CONNECTED) return;

    WiFiClientSecure client;
    client.setInsecure(); // Bypass SSL verification for HTTPS

    HTTPClient http;
    String url = getCleanFirebaseUrl("/telemetry.json");
    http.begin(client, url);
    http.setTimeout(1500); // 1.5 second timeout to prevent blocking ESP-NOW heartbeats
    http.addHeader("Content-Type", "application/json");

    String jsonPayload;
    if (calibrated) {
        jsonPayload = "{\"calibrated\":true,";
        
        // flex group (raw and percent lists)
        jsonPayload += "\"flex\":{\"raw\":[";
        for (int i = 0; i < NUM_FINGERS; i++) {
            jsonPayload += String(flexRaw[i]);
            if (i < NUM_FINGERS - 1) jsonPayload += ",";
        }
        jsonPayload += "],\"percent\":[";
        for (int i = 0; i < NUM_FINGERS; i++) {
            jsonPayload += String(flexPercent[i]);
            if (i < NUM_FINGERS - 1) jsonPayload += ",";
        }
        jsonPayload += "]},";
 
        // force group
        jsonPayload += "\"force\":{\"raw\":[" + String(forceRaw) + "],\"percent\":[" + String(forcePercent) + "]}";
        jsonPayload += "}";
    } else {
        jsonPayload = "{\"calibrated\":false}";
    }

    int httpResponseCode = http.PATCH(jsonPayload);
    if (httpResponseCode <= 0) {
        Serial.print("[Firebase] Telemetry upload failed.\n");
        printFirebaseErrorDiagnostics(httpResponseCode);
    }
    http.end();
}

inline void uploadBoxAction(const String& cubeId, uint32_t timestamp, bool isPlaced, int boxIndex) {
    if (WiFi.status() != WL_CONNECTED) {
        Serial.println("[Firebase] Cannot upload BoxAction (Wi-Fi disconnected)");
        return;
    }

    WiFiClientSecure client;
    client.setInsecure(); // Bypass SSL verification for HTTPS

    HTTPClient http;
    String url = getCleanFirebaseUrl("/telemetry/weights/" + cubeId + ".json");
    
    Serial.printf("[Firebase] Uploading BoxAction to URL: %s\n", url.c_str());

    http.begin(client, url);
    http.setTimeout(1500); // 1.5 second timeout to prevent blocking ESP-NOW heartbeats
    http.addHeader("Content-Type", "application/json");

    // Tuple structure: [timestamp, isPlaced, boxIndex]
    String jsonPayload = "[" + String(timestamp) + "," + (isPlaced ? "true" : "false") + "," + String(boxIndex) + "]";

    int httpResponseCode = http.PUT(jsonPayload);
    if (httpResponseCode > 0) {
        Serial.printf("[Firebase] BoxAction uploaded successfully: Weight %s -> %s Box %d\n", 
            cubeId.c_str(), isPlaced ? "Placed" : "Picked Up", boxIndex + 1);
    } else {
        Serial.print("[Firebase] BoxAction upload failed.\n");
        printFirebaseErrorDiagnostics(httpResponseCode);
    }
    http.end();
}

#endif // GLOVE_FIREBASE_H
