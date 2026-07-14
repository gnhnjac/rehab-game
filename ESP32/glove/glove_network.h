#ifndef GLOVE_NETWORK_H
#define GLOVE_NETWORK_H

#include <WiFi.h>
#include <time.h>
#include "glove_secrets.h"

// Track time sync state
extern bool ntpInitialized;

// Queue structure to defer NFC event processing out of the ESP-NOW callback context
struct BoxActionEvent {
    String cubeId;
    uint32_t timestamp;
    bool isPlaced;
    int boxIndex;
};

#define MAX_PENDING_EVENTS 10
extern BoxActionEvent eventQueue[MAX_PENDING_EVENTS];
extern volatile int queueHead;
extern volatile int queueTail;


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
        Serial.println("\n[Wi-Fi] Connection timed out! Starting local Access Point...");
        WiFi.mode(WIFI_AP_STA);
        WiFi.softAP("Rehab-Glove-AP", "rehab12345");
        Serial.print("[Wi-Fi] SoftAP IP Address: ");
        Serial.println(WiFi.softAPIP());
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

// Delegated to glove_sync.h
void saveSessionResultLocally(int gameType, int successes, int failures, unsigned long avgRespTimeMs, float avgForceOrRom);

#endif // GLOVE_NETWORK_H
