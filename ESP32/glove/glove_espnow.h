#ifndef GLOVE_ESPNOW_H
#define GLOVE_ESPNOW_H

#include <esp_now.h>
#include <WiFi.h>
#include <unordered_map>
#include "../parameters.h"
#include "glove_haptic.h"

extern bool isAPMode;
extern uint8_t mainBoxMac[6];
extern bool mainBoxRegistered;
extern volatile bool pendingButtonPress;
extern volatile bool buttonPressIsLong;

// Forward declaration of local game event handlers
void handleLocalNfcEvent(String cubeId, int boxIndex, bool isPlaced, const uint8_t *boxMac);
void selectNextCubesBoxesTarget();

inline bool isMacZero(const uint8_t* mac) {
    return mac[0] == 0 && mac[1] == 0 && mac[2] == 0 && mac[3] == 0 && mac[4] == 0 && mac[5] == 0;
}






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

// Helper to get Box index in the registry order
inline int getBoxIndex(uint64_t boxKey) {
    int idx = 0;
    for (const auto& pair : boxRegistry) {
        if (pair.first == boxKey) {
            return idx;
        }
        idx++;
    }
    return 0;
}

// ESP-NOW Receive Callback
#if defined(ESP_ARDUINO_VERSION_MAJOR) && ESP_ARDUINO_VERSION_MAJOR >= 3
inline void OnDataRecv(const esp_now_recv_info_t * recvInfo, const uint8_t *incomingData, int len) {
    const uint8_t *incoming_mac = recvInfo->src_addr;
#else
inline void OnDataRecv(const uint8_t * incoming_mac, const uint8_t *incomingData, int len) {
#endif
    if (isAPMode) return; // Ignore ESP-NOW communications in AP / configuration mode
    if (len < sizeof(AppMessage)) {
        Serial.println("Warning: Received packet too small!");
        return;
    }

    AppMessage msg;
    memcpy(&msg, incomingData, sizeof(AppMessage));

    RegistryLock lock;

    uint64_t boxKey = macToKey(incoming_mac);

    if (msg.type == MSG_TYPE_REGISTER_MAIN) {
        Serial.print("[ESP-NOW] Main Box registration request from: ");
        printMac(incoming_mac);
        Serial.println();

        memcpy(mainBoxMac, incoming_mac, 6);
        mainBoxRegistered = true;

        esp_now_peer_info_t peerInfo;
        memset(&peerInfo, 0, sizeof(peerInfo));
        memcpy(peerInfo.peer_addr, incoming_mac, 6);
        peerInfo.channel = 0;
        peerInfo.encrypt = false;
        peerInfo.ifidx = isAPMode ? WIFI_IF_AP : WIFI_IF_STA;

        if (!esp_now_is_peer_exist(incoming_mac)) {
            if (esp_now_add_peer(&peerInfo) != ESP_OK) {
                Serial.println("[Glove] Error: Failed to add Main Box peer.");
            }
        }

        // Register in standard registry too
        auto it = boxRegistry.find(boxKey);
        if (it == boxRegistry.end()) {
            RegisteredBox newBox;
            memcpy(newBox.mac, incoming_mac, 6);
            newBox.active = true;
            newBox.current_cube_len = 0;
            memset(newBox.current_cube_uid, 0, MAX_CUBE_UID_LEN);
            newBox.last_seen = millis();
            strcpy(newBox.shape, "circle");
            boxRegistry[boxKey] = newBox;
        } else {
            it->second.last_seen = millis();
        }

        // Send ACK
        AppMessage ack_msg;
        ack_msg.type = MSG_TYPE_ACK;
        WiFi.macAddress(ack_msg.box_mac);
        esp_now_send(incoming_mac, (uint8_t *)&ack_msg, sizeof(ack_msg));
    }
    else if (msg.type == MSG_TYPE_REGISTER) {
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
                newBox.last_seen = millis();
                strcpy(newBox.shape, "circle");
                boxRegistry[boxKey] = newBox;

                Serial.print("[Glove] Registered new Smart Box. Total connected: ");
                Serial.println(boxRegistry.size());

                // Add box as peer
                esp_now_peer_info_t peerInfo;
                memset(&peerInfo, 0, sizeof(peerInfo));
                memcpy(peerInfo.peer_addr, incoming_mac, 6);
                peerInfo.channel = 0;
                peerInfo.encrypt = false;
                peerInfo.ifidx = isAPMode ? WIFI_IF_AP : WIFI_IF_STA;

                if (!esp_now_is_peer_exist(incoming_mac)) {
                    if (esp_now_add_peer(&peerInfo) != ESP_OK) {
                        Serial.println("[Glove] Error: Failed to add Box as peer.");
                    }
                }
                
                if (sessionState.active && currentPrescription.gameType == GAME_CUBES_BOXES && 
                    isMacZero(sessionState.targetBoxMac)) {
                    Serial.println("[ESP-NOW] First box registered while game active. Selecting target box.");
                    selectNextCubesBoxesTarget();
                }
            } else {
                Serial.println("[Glove] Error: Maximum box limit reached!");
                return;
            }
        } else {
            it->second.last_seen = millis(); // Refresh last seen
        }

        // Send ACK back to the box
        AppMessage ack_msg;
        ack_msg.type = MSG_TYPE_ACK;
        WiFi.macAddress(ack_msg.box_mac); // Pass Glove's MAC back
        esp_now_send(incoming_mac, (uint8_t *)&ack_msg, sizeof(ack_msg));
    }
    else if (msg.type == MSG_TYPE_HEARTBEAT) {
        auto it = boxRegistry.find(boxKey);
        bool isMain = (msg.uid_len > 0 && msg.uid[0] == 1);
        
        if (it != boxRegistry.end()) {
            it->second.last_seen = millis();
            Serial.print("[Glove] Heartbeat received from Box: ");
            printMac(incoming_mac);
            Serial.println();
            
            if (isMain) {
                memcpy(mainBoxMac, incoming_mac, 6);
                mainBoxRegistered = true;
            }
            
            // Reply with heartbeat response
            AppMessage reply_msg;
            reply_msg.type = MSG_TYPE_HEARTBEAT;
            WiFi.macAddress(reply_msg.box_mac);
            esp_now_send(incoming_mac, (uint8_t *)&reply_msg, sizeof(reply_msg));

            if (sessionState.active && currentPrescription.gameType == GAME_CUBES_BOXES && 
                isMacZero(sessionState.targetBoxMac)) {
                Serial.println("[ESP-NOW] Heartbeat from registered box while game active. Selecting target box.");
                selectNextCubesBoxesTarget();
            }
        } else {
            Serial.print("[Glove] Heartbeat from UNREGISTERED Box. Auto-registering: ");
            printMac(incoming_mac);
            Serial.println();

            if (isMain) {
                memcpy(mainBoxMac, incoming_mac, 6);
                mainBoxRegistered = true;
                Serial.println("[Glove] Unregistered heartbeat recognized as MAIN Box. Registered!");
            }

            if (boxRegistry.size() < MAX_BOXES) {
                RegisteredBox newBox;
                memcpy(newBox.mac, incoming_mac, 6);
                newBox.active = true;
                newBox.current_cube_len = 0;
                memset(newBox.current_cube_uid, 0, MAX_CUBE_UID_LEN);
                newBox.last_seen = millis();
                strcpy(newBox.shape, "circle");
                boxRegistry[boxKey] = newBox;

                // Add box as peer
                esp_now_peer_info_t peerInfo;
                memset(&peerInfo, 0, sizeof(peerInfo));
                memcpy(peerInfo.peer_addr, incoming_mac, 6);
                peerInfo.channel = 0;
                peerInfo.encrypt = false;
                peerInfo.ifidx = isAPMode ? WIFI_IF_AP : WIFI_IF_STA;

                if (!esp_now_is_peer_exist(incoming_mac)) {
                    if (esp_now_add_peer(&peerInfo) != ESP_OK) {
                        Serial.println("[Glove] Error: Failed to add Box as peer.");
                    }
                }

                // Send ACK back to the box so it transitions to registered state
                AppMessage ack_msg;
                ack_msg.type = MSG_TYPE_ACK;
                WiFi.macAddress(ack_msg.box_mac);
                esp_now_send(incoming_mac, (uint8_t *)&ack_msg, sizeof(ack_msg));

                if (sessionState.active && currentPrescription.gameType == GAME_CUBES_BOXES && 
                    isMacZero(sessionState.targetBoxMac)) {
                    Serial.println("[ESP-NOW] Target box auto-selected on auto-registration.");
                    selectNextCubesBoxesTarget();
                }
            }
        }
    }
    else if (msg.type == MSG_TYPE_EVENT) {
        if (msg.event == EVENT_BUTTON_PRESSED) {
            Serial.println("[ESP-NOW] Physical button event from Main Box received.");
            pendingButtonPress = true;
            buttonPressIsLong = (msg.uid_len > 0 && msg.uid[0] == 1);
            return;
        }

        auto it = boxRegistry.find(boxKey);
        if (it == boxRegistry.end()) {
            Serial.print("[Glove] Warning: Received event from unregistered Box: ");
            printMac(incoming_mac);
            Serial.println();
            return;
        }

        it->second.last_seen = millis(); // Refresh last seen on event

        if (msg.event == EVENT_CUBE_ENTERED) {
            // Filter duplicate enter events if same cube is already registered in this box
            if (it->second.current_cube_len == msg.uid_len &&
                memcmp(it->second.current_cube_uid, msg.uid, msg.uid_len) == 0) {
                return; // Ignore duplicate
            }

            it->second.current_cube_len = msg.uid_len;
            memcpy(it->second.current_cube_uid, msg.uid, msg.uid_len);

            Serial.print("[EVENT] Cube ENTERED Box [");
            printMac(incoming_mac);
            Serial.print("] - Cube UID: ");
            String cubeId = "";
            for (uint8_t i = 0; i < msg.uid_len; i++) {
                Serial.printf(" %02X", msg.uid[i]);
                char hex[3];
                sprintf(hex, "%02X", msg.uid[i]);
                cubeId += hex;
            }
            Serial.println();

            int boxIndex = getBoxIndex(boxKey);
            uint32_t timestamp = getEpochTime();
            if (!pushEvent(cubeId, timestamp, true, boxIndex)) {
                Serial.println("[ESP-NOW] Warning: Event queue full, cube entered event dropped!");
            }

            // Trigger local game state machine
            handleLocalNfcEvent(cubeId, boxIndex, true, incoming_mac);

            triggerHapticClick();
        } 
        else if (msg.event == EVENT_CUBE_LEFT) {
            // Filter duplicate leave events if no cube is currently registered in this box
            if (it->second.current_cube_len == 0 && msg.uid_len == 0) {
                return; // Ignore duplicate
            }

            String cubeId = "";
            uint8_t len = msg.uid_len > 0 ? msg.uid_len : it->second.current_cube_len;
            uint8_t* sourceUid = msg.uid_len > 0 ? msg.uid : it->second.current_cube_uid;
            
            for (uint8_t i = 0; i < len; i++) {
                char hex[3];
                sprintf(hex, "%02X", sourceUid[i]);
                cubeId += hex;
            }
            if (cubeId.length() == 0) cubeId = "UNKNOWN";

            it->second.current_cube_len = 0;
            memset(it->second.current_cube_uid, 0, MAX_CUBE_UID_LEN);

            Serial.print("[EVENT] Cube LEFT Box [");
            printMac(incoming_mac);
            Serial.println("]");

            int boxIndex = getBoxIndex(boxKey);
            uint32_t timestamp = getEpochTime();
            if (!pushEvent(cubeId, timestamp, false, boxIndex)) {
                Serial.println("[ESP-NOW] Warning: Event queue full, cube left event dropped!");
            }

            // Trigger local game state machine
            handleLocalNfcEvent(cubeId, boxIndex, false, incoming_mac);
        }
    }
}

// Timeout check function
inline void checkBoxTimeouts() {
    RegistryLock lock;
    unsigned long now = millis();
    for (auto it = boxRegistry.begin(); it != boxRegistry.end(); ) {
        if (now - it->second.last_seen > 15000) {
            Serial.print("[Glove] Heartbeat timeout. Unregistering Box [");
            printMac(it->second.mac);
            Serial.println("]");

            // Delete box as peer to free up peer list slots
            if (esp_now_is_peer_exist(it->second.mac)) {
                esp_now_del_peer(it->second.mac);
            }
            
            // Erase from registry
            it = boxRegistry.erase(it);
        } else {
            ++it;
        }
    }
}

inline void setupEspNow() {
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

// --- ESP-NOW GLOVE -> BOX COMMAND SENDER HELPERS ---
inline void sendLedColorToBox(const uint8_t *mac, uint8_t r, uint8_t g, uint8_t b) {
    AppMessage msg;
    msg.type = MSG_TYPE_COMMAND;
    msg.event = BOX_CMD_SET_LED;
    msg.uid_len = 3;
    msg.uid[0] = r;
    msg.uid[1] = g;
    msg.uid[2] = b;
    
    if (mac[0] != 0xFF) {
        esp_now_peer_info_t peerInfo;
        memset(&peerInfo, 0, sizeof(peerInfo));
        memcpy(peerInfo.peer_addr, mac, 6);
        peerInfo.channel = 0;
        peerInfo.encrypt = false;
        peerInfo.ifidx = isAPMode ? WIFI_IF_AP : WIFI_IF_STA;
        if (!esp_now_is_peer_exist(mac)) {
            esp_now_add_peer(&peerInfo);
        }
    }
    esp_now_send(mac, (uint8_t *)&msg, sizeof(msg));
}

inline void sendSuccessFlashToBoxes() {
    AppMessage msg;
    msg.type = MSG_TYPE_COMMAND;
    msg.event = BOX_CMD_FLASH_SUCCESS;
    msg.uid_len = 0;
    
    for (const auto& pair : boxRegistry) {
        esp_now_send(pair.second.mac, (uint8_t *)&msg, sizeof(msg));
        delay(10);
    }
}

inline void sendFailureBlinkToBoxes() {
    AppMessage msg;
    msg.type = MSG_TYPE_COMMAND;
    msg.event = BOX_CMD_FLASH_FAILURE;
    msg.uid_len = 0;
    
    for (const auto& pair : boxRegistry) {
        esp_now_send(pair.second.mac, (uint8_t *)&msg, sizeof(msg));
        delay(10);
    }
}

inline void sendIdentifyToBox(const uint8_t *mac) {
    AppMessage msg;
    msg.type = MSG_TYPE_COMMAND;
    msg.event = BOX_CMD_IDENTIFY;
    msg.uid_len = 0;
    
    if (mac[0] != 0xFF) {
        esp_now_peer_info_t peerInfo;
        memset(&peerInfo, 0, sizeof(peerInfo));
        memcpy(peerInfo.peer_addr, mac, 6);
        peerInfo.channel = 0;
        peerInfo.encrypt = false;
        peerInfo.ifidx = isAPMode ? WIFI_IF_AP : WIFI_IF_STA;
        if (!esp_now_is_peer_exist(mac)) {
            esp_now_add_peer(&peerInfo);
        }
    }
    esp_now_send(mac, (uint8_t *)&msg, sizeof(msg));
}

#endif
