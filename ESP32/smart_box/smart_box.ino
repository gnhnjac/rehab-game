#include <Wire.h>
#include <Adafruit_PN532.h>
#include <WiFi.h>
#include <esp_now.h>
#include "soc/soc.h"
#include "soc/rtc_cntl_reg.h"
#include "../parameters.h"

// Define I2C pins for ESP32 (from working unit test)
#define SDA_PIN 21
#define SCL_PIN 22

Adafruit_PN532 nfc(SDA_PIN, SCL_PIN);

// State variables
bool isRegistered = false;
bool nfcFound = false; // Flag to track if the PN532 was successfully initialized
uint8_t gloveMac[6];
uint8_t myMac[6];

// Send callback (Empty, unused)
void OnDataSent(const uint8_t *mac_addr, esp_now_send_status_t status) {
  // Empty
}

// Receive callback
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
            
            // Register Glove as peer
            esp_now_peer_info_t peerInfo;
            memset(&peerInfo, 0, sizeof(peerInfo));
            memcpy(peerInfo.peer_addr, gloveMac, 6);
            peerInfo.channel = 0;
            peerInfo.encrypt = false;

            if (!esp_now_is_peer_exist(gloveMac)) {
                esp_now_add_peer(&peerInfo);
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

    esp_now_send(gloveMac, (uint8_t *)&msg, sizeof(msg));
}

void setup(void) {
  // Disable the brownout detector to prevent power dips from resetting the chip
  WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0);

  Serial.begin(115200);
  delay(1000);
  Serial.println("\n--- [Smart Box] Booting ---");

  // 1. Initialize WiFi first (while PN532 is idle and drawing minimal current)
  Serial.println("Starting WiFi...");
  WiFi.mode(WIFI_STA);
  WiFi.macAddress(myMac);
  Serial.print("MAC Address: ");
  for(int i=0; i<6; i++) {
    Serial.printf("%02X", myMac[i]);
    if (i < 5) Serial.print(":");
  }
  Serial.println();

  // 2. Initialize ESP-NOW
  Serial.println("Starting ESP-NOW...");
  if (esp_now_init() != ESP_OK) {
    Serial.println("Error: Failed to initialize ESP-NOW!");
    while (1) delay(100);
  }

  esp_now_register_recv_cb(OnDataRecv);

  // Add broadcast peer for registration
  esp_now_peer_info_t peerInfo;
  memset(&peerInfo, 0, sizeof(peerInfo));
  uint8_t broadcastMac[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
  memcpy(peerInfo.peer_addr, broadcastMac, 6);
  peerInfo.channel = 0;
  peerInfo.encrypt = false;
  
  if (esp_now_add_peer(&peerInfo) != ESP_OK) {
    Serial.println("Error: Failed to add broadcast peer!");
  }

  delay(500); // Let WiFi current draw stabilize

  // 3. Initialize PN532 (staggered to avoid overlapping startup power surges)
  Serial.println("Looking for PN532...");
  nfc.begin();

  uint32_t versiondata = nfc.getFirmwareVersion();
  if (!versiondata) {
    Serial.println("WARNING: Didn't find PN532 board. Check your wiring!");
    Serial.println("Running in Wi-Fi simulation mode (sending mock events)...");
    nfcFound = false;
  } else {
    nfcFound = true;
    Serial.print("Found chip PN532 "); 
    Serial.println((versiondata >> 24) & 0xFF, HEX); 
    Serial.print("Firmware ver. "); 
    Serial.print((versiondata >> 16) & 0xFF, DEC); 
    Serial.print('.'); Serial.println((versiondata >> 8) & 0xFF, DEC);
    nfc.SAMConfig();
  }

  // 4. Dynamic registration loop
  Serial.println("Searching for Glove...");
  while (!isRegistered) {
    AppMessage regMsg;
    regMsg.type = MSG_TYPE_REGISTER;
    memcpy(regMsg.box_mac, myMac, 6);
    regMsg.event = EVENT_NONE;
    regMsg.uid_len = 0;
    memset(regMsg.uid, 0, MAX_CUBE_UID_LEN);

    uint8_t broadcastMac[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
    esp_now_send(broadcastMac, (uint8_t *)&regMsg, sizeof(regMsg));
    
    Serial.println("Broadcasting registration request...");
    
    // Wait 2 seconds for background ACK processing
    unsigned long startWait = millis();
    while (millis() - startWait < 2000) {
      if (isRegistered) break;
      delay(50);
    }
  }

  Serial.println("Registered with Glove. Starting active loop...");
}

void loop(void) {
  if (nfcFound) {
    uint8_t success;
    uint8_t uid[] = { 0, 0, 0, 0, 0, 0, 0 };  // Buffer to store the returned UID
    uint8_t uidLength;                        // Length of the UID (4 or 7 bytes)

    // STATE 1: Wait for a card to be placed (Blocking call, identical to working unit test)
    success = nfc.readPassiveTargetID(PN532_MIFARE_ISO14443A, uid, &uidLength);

    if (success) {
      Serial.println("Card Entered!");
      sendNfcEvent(EVENT_CUBE_ENTERED, uid, uidLength);
      
      // STATE 2: Card is present. Poll it in a loop to detect when it leaves.
      int consecutiveFailures = 0;
      while (consecutiveFailures < 5) {
        delay(100);
        
        uint8_t pollUid[7];
        uint8_t pollUidLength = 0;
        bool pollSuccess = nfc.readPassiveTargetID(PN532_MIFARE_ISO14443A, pollUid, &pollUidLength, 100);
        
        if (pollSuccess) {
          consecutiveFailures = 0; // Reset counter on successful scan
        } else {
          consecutiveFailures++;   // Increment on failed scan
        }
      }
      
      // STATE 3: Card is removed
      Serial.println("Card Left!");
      sendNfcEvent(EVENT_CUBE_LEFT, uid, uidLength);
    }
  } else {
    // SIMULATED MODE: Send simulated events every 10 seconds to test WiFi/ESP-NOW communication
    uint8_t simulatedUid[] = { 0x04, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66 };
    uint8_t uidLen = 7;
    
    Serial.println("[Simulated] Cube Entered!");
    sendNfcEvent(EVENT_CUBE_ENTERED, simulatedUid, uidLen);
    delay(5000); // 5 seconds inside

    Serial.println("[Simulated] Cube Left!");
    sendNfcEvent(EVENT_CUBE_LEFT, simulatedUid, uidLen);
    delay(5000); // 5 seconds outside
  }
}