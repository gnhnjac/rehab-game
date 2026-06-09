#include <esp_now.h>
#include <WiFi.h>
#include <Wire.h>
#include <Adafruit_PN532.h>
#include "../parameters.h"

// --- Hardware Pins ---
#define SDA_PIN 21
#define SCL_PIN 22

Adafruit_PN532 nfc(SDA_PIN, SCL_PIN);

// --- State Variables ---
bool isRegistered = false;
uint8_t gloveMac[6];
uint8_t myMac[6];

// NFC Cube tracking
uint8_t lastUid[7];
uint8_t lastUidLen = 0;
bool cubePresent = false;
int consecutiveFailures = 0;
const int maxFailures = 5; // Tag must fail to read 5 consecutive times (~500ms) to be considered LEFT

// Registration interval
unsigned long lastRegisterSend = 0;
const unsigned long registerInterval = 2000; // Try registering every 2 seconds

// --- Helper Functions ---
void printMac(const uint8_t *mac) {
    for (int i = 0; i < 6; i++) {
        Serial.printf("%02X", mac[i]);
        if (i < 5) Serial.print(":");
    }
}

// --- ESP-NOW Callbacks ---
void OnDataSent(const uint8_t *mac_addr, esp_now_send_status_t status) {
    if (status != ESP_NOW_SEND_SUCCESS) {
        Serial.println("[ESP-NOW] Warning: Message delivery failed!");
    }
}

#if defined(ESP_ARDUINO_VERSION_MAJOR) && ESP_ARDUINO_VERSION_MAJOR >= 3
void OnDataRecv(const esp_now_recv_info_t * recvInfo, const uint8_t *incomingData, int len) {
    const uint8_t *incoming_mac = recvInfo->src_addr;
#else
void OnDataRecv(const uint8_t * incoming_mac, const uint8_t *incomingData, int len) {
#endif
    if (len < sizeof(AppMessage)) return;

    AppMessage msg;
    memcpy(&msg, incomingData, sizeof(AppMessage));

    if (msg.type == MSG_TYPE_ACK) {
        if (!isRegistered) {
            isRegistered = true;
            memcpy(gloveMac, incoming_mac, 6);
            
            Serial.print("[Smart Box] Registration ACK received from Glove: ");
            printMac(gloveMac);
            Serial.println();

            // Register Glove as peer for direct communications
            esp_now_peer_info_t peerInfo;
            memset(&peerInfo, 0, sizeof(peerInfo));
            memcpy(peerInfo.peer_addr, gloveMac, 6);
            peerInfo.channel = 0;
            peerInfo.encrypt = false;

            if (!esp_now_is_peer_exist(gloveMac)) {
                if (esp_now_add_peer(&peerInfo) != ESP_OK) {
                    Serial.println("[Smart Box] Error: Failed to add Glove as peer.");
                }
            }
        }
    }
}

void sendNfcEvent(CubeEventType event, uint8_t *uid, uint8_t uidLen) {
    if (!isRegistered) return;

    AppMessage msg;
    msg.type = MSG_TYPE_EVENT;
    memcpy(msg.box_mac, myMac, 6);
    msg.event = event;
    msg.uid_len = uidLen;
    memset(msg.uid, 0, MAX_CUBE_UID_LEN);
    if (uid && uidLen > 0) {
        memcpy(msg.uid, uid, uidLen <= MAX_CUBE_UID_LEN ? uidLen : MAX_CUBE_UID_LEN);
    }

    Serial.print("[Smart Box] Sending NFC Event: ");
    if (event == EVENT_CUBE_ENTERED) Serial.print("ENTERED");
    else if (event == EVENT_CUBE_LEFT) Serial.print("LEFT");
    Serial.println();

    esp_now_send(gloveMac, (uint8_t *)&msg, sizeof(msg));
}

void setup() {
    Serial.begin(115200);
    delay(1000);
    Serial.println("[Smart Box] Starting client box...");

    // Initialize WiFi in Station mode
    WiFi.mode(WIFI_STA);
    WiFi.macAddress(myMac);
    Serial.print("[Smart Box] MAC Address: ");
    printMac(myMac);
    Serial.println();

    // Initialize PN532
    nfc.begin();
    uint32_t versiondata = nfc.getFirmwareVersion();
    if (!versiondata) {
        Serial.println("[Smart Box] Error: Didn't find PN532 board. Check wiring!");
        while (1) delay(100);
    }

    Serial.print("[Smart Box] Found chip PN532 ver. ");
    Serial.print((versiondata >> 16) & 0xFF, DEC);
    Serial.print('.'); Serial.println((versiondata >> 8) & 0xFF, DEC);

    nfc.SAMConfig();

    // Initialize ESP-NOW
    if (esp_now_init() != ESP_OK) {
        Serial.println("[Smart Box] Error: Failed to initialize ESP-NOW!");
        while (1) delay(100);
    }

    esp_now_register_send_cb(OnDataSent);
    esp_now_register_recv_cb(OnDataRecv);

    // Register broadcast address as peer for pairing
    esp_now_peer_info_t peerInfo;
    memset(&peerInfo, 0, sizeof(peerInfo));
    uint8_t broadcastMac[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
    memcpy(peerInfo.peer_addr, broadcastMac, 6);
    peerInfo.channel = 0;
    peerInfo.encrypt = false;

    if (esp_now_add_peer(&peerInfo) != ESP_OK) {
        Serial.println("[Smart Box] Error: Failed to add broadcast peer!");
    }

    Serial.println("[Smart Box] Setup complete. Searching for Glove...");
}

void loop() {
    // 1. Dynamic registration handler
    if (!isRegistered) {
        if (millis() - lastRegisterSend >= registerInterval) {
            lastRegisterSend = millis();
            
            AppMessage regMsg;
            regMsg.type = MSG_TYPE_REGISTER;
            memcpy(regMsg.box_mac, myMac, 6);
            regMsg.event = EVENT_NONE;
            regMsg.uid_len = 0;
            memset(regMsg.uid, 0, MAX_CUBE_UID_LEN);

            Serial.println("[Smart Box] Broadcasting registration request...");
            uint8_t broadcastMac[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
            esp_now_send(broadcastMac, (uint8_t *)&regMsg, sizeof(regMsg));
        }
        delay(100); // Slow down loop while searching
        return;
    }

    // 2. NFC scanner handler (Timeout = 100ms to keep loop responsive)
    uint8_t uid[7];
    uint8_t uidLength = 0;
    bool success = nfc.readPassiveTargetID(PN532_MIFARE_ISO14443A, uid, &uidLength, 100);

    if (success) {
        consecutiveFailures = 0;

        // Check if a new cube entered, or if the cube changed
        if (!cubePresent || uidLength != lastUidLen || memcmp(uid, lastUid, uidLength) != 0) {
            
            // If another cube was already registered in this box, send its left event first
            if (cubePresent) {
                sendNfcEvent(EVENT_CUBE_LEFT, lastUid, lastUidLen);
            }

            // Save new cube info
            cubePresent = true;
            lastUidLen = uidLength;
            memcpy(lastUid, uid, uidLength);

            // Send cube entered event
            sendNfcEvent(EVENT_CUBE_ENTERED, lastUid, lastUidLen);
        }
    } 
    else {
        // Tag not found in this scan iteration
        if (cubePresent) {
            consecutiveFailures++;
            if (consecutiveFailures >= maxFailures) {
                // Confirmed departure after 5 failed attempts
                sendNfcEvent(EVENT_CUBE_LEFT, lastUid, lastUidLen);
                cubePresent = false;
                lastUidLen = 0;
                memset(lastUid, 0, sizeof(lastUid));
            }
        }
    }

    delay(20); // Small loop pacing delay
}
