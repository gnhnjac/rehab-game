#ifndef GLOVE_ESPNOW_H
#define GLOVE_ESPNOW_H

#include <esp_now.h>
#include <WiFi.h>
#include <unordered_map>
#include "../parameters.h"

struct RegisteredBox {
    uint8_t mac[6];
    uint8_t current_cube_uid[MAX_CUBE_UID_LEN];
    uint8_t current_cube_len;
    bool active;
};

// Box registry using std::unordered_map (key is MAC packed as uint64_t for O(1) lookup)
std::unordered_map<uint64_t, RegisteredBox> boxRegistry;

// Helper to print MAC address
inline void printMac(const uint8_t *mac) {
    for (int i = 0; i < 6; i++) {
        Serial.printf("%02X", mac[i]);
        if (i < 5) Serial.print(":");
    }
}

// Helper to convert MAC to 64-bit key
inline uint64_t macToKey(const uint8_t* mac) {
    uint64_t key = 0;
    for (int i = 0; i < 6; i++) {
        key = (key << 8) | mac[i];
    }
    return key;
}

// ESP-NOW Receive Callback
#if defined(ESP_ARDUINO_VERSION_MAJOR) && ESP_ARDUINO_VERSION_MAJOR >= 3
inline void OnDataRecv(const esp_now_recv_info_t * recvInfo, const uint8_t *incomingData, int len) {
    const uint8_t *incoming_mac = recvInfo->src_addr;
#else
inline void OnDataRecv(const uint8_t * incoming_mac, const uint8_t *incomingData, int len) {
#endif
    if (len < sizeof(AppMessage)) {
        Serial.println("Warning: Received packet too small!");
        return;
    }

    AppMessage msg;
    memcpy(&msg, incomingData, sizeof(AppMessage));

    uint64_t boxKey = macToKey(incoming_mac);

    if (msg.type == MSG_TYPE_REGISTER) {
        Serial.print("[ESP-NOW] Registration request from Box: ");
        printMac(incoming_mac);
        Serial.println();

        auto it = boxRegistry.find(boxKey);
        if (it == boxRegistry.end()) {
            if (boxRegistry.size() < MAX_BOXES) {
                RegisteredBox newBox;
                memcpy(newBox.mac, incoming_mac, 6);
                newBox.active = true;
                newBox.current_cube_len = 0;
                memset(newBox.current_cube_uid, 0, MAX_CUBE_UID_LEN);
                
                boxRegistry[boxKey] = newBox;

                Serial.print("[Glove] Registered new Smart Box. Total connected: ");
                Serial.println(boxRegistry.size());

                // Add box as peer
                esp_now_peer_info_t peerInfo;
                memset(&peerInfo, 0, sizeof(peerInfo));
                memcpy(peerInfo.peer_addr, incoming_mac, 6);
                peerInfo.channel = 0;
                peerInfo.encrypt = false;

                if (!esp_now_is_peer_exist(incoming_mac)) {
                    if (esp_now_add_peer(&peerInfo) != ESP_OK) {
                        Serial.println("[Glove] Error: Failed to add Box as peer.");
                    }
                }
            } else {
                Serial.println("[Glove] Error: Maximum box limit reached!");
                return;
            }
        }

        // Send ACK back to the box
        AppMessage ack_msg;
        ack_msg.type = MSG_TYPE_ACK;
        WiFi.macAddress(ack_msg.box_mac); // Pass Glove's MAC back
        esp_now_send(incoming_mac, (uint8_t *)&ack_msg, sizeof(ack_msg));
    }
    else if (msg.type == MSG_TYPE_EVENT) {
        auto it = boxRegistry.find(boxKey);
        if (it == boxRegistry.end()) {
            Serial.print("[Glove] Warning: Received event from unregistered Box: ");
            printMac(incoming_mac);
            Serial.println();
            return;
        }

        if (msg.event == EVENT_CUBE_ENTERED) {
            it->second.current_cube_len = msg.uid_len;
            memcpy(it->second.current_cube_uid, msg.uid, msg.uid_len);

            Serial.print("[EVENT] Cube ENTERED Box [");
            printMac(incoming_mac);
            Serial.print("] - Cube UID: ");
            for (uint8_t i = 0; i < msg.uid_len; i++) {
                Serial.printf(" %02X", msg.uid[i]);
            }
            Serial.println();
        } 
        else if (msg.event == EVENT_CUBE_LEFT) {
            it->second.current_cube_len = 0;
            memset(it->second.current_cube_uid, 0, MAX_CUBE_UID_LEN);

            Serial.print("[EVENT] Cube LEFT Box [");
            printMac(incoming_mac);
            Serial.println("]");
        }
    }
}

inline void setupEspNow() {
    WiFi.mode(WIFI_STA);
    Serial.print("[Glove] MAC Address: ");
    Serial.println(WiFi.macAddress());

    if (esp_now_init() != ESP_OK) {
        Serial.println("[Glove] Error: Failed to initialize ESP-NOW!");
        while (1) delay(100);
    }

    esp_now_register_recv_cb(OnDataRecv);
}

inline void printRegistry() {
    if (boxRegistry.empty()) return;
    
    Serial.println("--- Cube Placements Registry ---");
    for (const auto& pair : boxRegistry) {
        const RegisteredBox& box = pair.second;
        Serial.print("  Box [");
        printMac(box.mac);
        Serial.print("]: ");
        if (box.current_cube_len > 0) {
            Serial.print("Cube UID =");
            for (int j = 0; j < box.current_cube_len; j++) {
                Serial.printf(" %02X", box.current_cube_uid[j]);
            }
        } else {
            Serial.print("[EMPTY]");
        }
        Serial.println();
    }
    Serial.println("--------------------------------");
}

#endif
