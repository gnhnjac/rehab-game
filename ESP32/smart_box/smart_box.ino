#include <Wire.h>
#include <Adafruit_PN532.h>
#include <WiFi.h>
#include <esp_now.h>
#include <esp_wifi.h>
#include "soc/soc.h"
#include "soc/rtc_cntl_reg.h"
#include "../parameters.h"

#include <Adafruit_NeoPixel.h>

Adafruit_PN532 nfc(SDA_PIN, SCL_PIN);

// --- NEOPIXEL STRIP CONFIGURATION ---
#define NEOPIXEL_PIN 13 // Change to your physical NeoPixel data GPIO pin
#define NUM_PIXELS 8    // Change to the number of LEDs in your strip

Adafruit_NeoPixel pixels(NUM_PIXELS, NEOPIXEL_PIN, NEO_GRB + NEO_KHZ800);

enum LedMode {
    LED_MODE_SOLID,
    LED_MODE_SUCCESS,
    LED_MODE_FAILURE,
    LED_MODE_IDENTIFY
};

LedMode currentLedMode = LED_MODE_SOLID;
uint8_t currentR = 0, currentG = 0, currentB = 0;
unsigned long lastLedUpdate = 0;
int ledStep = 0;

void writeLed(uint8_t r, uint8_t g, uint8_t b) {
    for (int i = 0; i < NUM_PIXELS; i++) {
        pixels.setPixelColor(i, pixels.Color(r, g, b));
    }
    pixels.show();
}


void setLedColor(uint8_t r, uint8_t g, uint8_t b) {
    currentLedMode = LED_MODE_SOLID;
    currentR = r;
    currentG = g;
    currentB = b;
    writeLed(r, g, b);
}

void triggerSuccessFlash() {
    currentLedMode = LED_MODE_SUCCESS;
    lastLedUpdate = millis();
    ledStep = 0;
}

void triggerFailureBlink() {
    currentLedMode = LED_MODE_FAILURE;
    lastLedUpdate = millis();
    ledStep = 0;
}

void triggerIdentifyFlash() {
    currentLedMode = LED_MODE_IDENTIFY;
    lastLedUpdate = millis();
    ledStep = 0;
}

void updateLeds() {
    if (currentLedMode == LED_MODE_SOLID) return;
    unsigned long now = millis();
    
    if (currentLedMode == LED_MODE_SUCCESS) {
        if (now - lastLedUpdate >= 100) {
            lastLedUpdate = now;
            ledStep++;
            if (ledStep > 20) {
                setLedColor(0, 0, 0); // Off after 2s
            } else {
                writeLed(random(0, 256), random(0, 256), random(0, 256));
            }
        }
    }
    else if (currentLedMode == LED_MODE_FAILURE) {
        if (now - lastLedUpdate >= 200) {
            lastLedUpdate = now;
            ledStep++;
            if (ledStep > 10) {
                setLedColor(0, 0, 0); // Off after 2s
            } else {
                if (ledStep % 2 == 0) {
                    writeLed(255, 0, 0); // Red
                } else {
                    writeLed(255, 255, 255); // White
                }
            }
        }
    }
    else if (currentLedMode == LED_MODE_IDENTIFY) {
        if (now - lastLedUpdate >= 150) {
            lastLedUpdate = now;
            ledStep++;
            if (ledStep > 20) {
                setLedColor(0, 0, 0); // Off after 3s
            } else {
                if (ledStep % 2 == 0) {
                    writeLed(0, 0, 255); // Blue
                } else {
                    writeLed(0, 0, 0);
                }
            }
        }
    }
}


// State variables
bool isRegistered = false;
bool nfcFound = false; // Flag to track if the PN532 was successfully initialized
uint8_t gloveMac[6];
uint8_t myMac[6];

unsigned long last_received_from_glove = 0;
unsigned long last_heartbeat_sent = 0;

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
        last_received_from_glove = millis();
    }
    else if (msg.type == MSG_TYPE_HEARTBEAT) {
        if (isRegistered && memcmp(incoming_mac, gloveMac, 6) == 0) {
            last_received_from_glove = millis();
        }
    }
    else if (msg.type == MSG_TYPE_COMMAND) {
        if (isRegistered && memcmp(incoming_mac, gloveMac, 6) == 0) {
            uint8_t cmdType = msg.event;
            if (cmdType == BOX_CMD_SET_LED) {
                setLedColor(msg.uid[0], msg.uid[1], msg.uid[2]);
            }
            else if (cmdType == BOX_CMD_FLASH_SUCCESS) {
                triggerSuccessFlash();
            }
            else if (cmdType == BOX_CMD_FLASH_FAILURE) {
                triggerFailureBlink();
            }
            else if (cmdType == BOX_CMD_IDENTIFY) {
                triggerIdentifyFlash();
            }
            last_received_from_glove = millis();
        }
    }
}

void checkHeartbeats() {
  if (!isRegistered) return;

  unsigned long now = millis();

  // 1. Send heartbeat every 5 seconds
  if (now - last_heartbeat_sent >= 5000) {
    last_heartbeat_sent = now;
    AppMessage heartbeatMsg;
    heartbeatMsg.type = MSG_TYPE_HEARTBEAT;
    memcpy(heartbeatMsg.box_mac, myMac, 6);
    heartbeatMsg.event = EVENT_NONE;
    heartbeatMsg.uid_len = 0;
    memset(heartbeatMsg.uid, 0, MAX_CUBE_UID_LEN);

    esp_now_send(gloveMac, (uint8_t *)&heartbeatMsg, sizeof(heartbeatMsg));
  }

  // 2. Check for Glove timeout (15 seconds)
  if (now - last_received_from_glove > 15000) {
    Serial.println("[Smart Box] Lost connection to Glove (heartbeat timeout). Unregistering...");
    isRegistered = false;
    
    // Delete peer to free resources
    if (esp_now_is_peer_exist(gloveMac)) {
      esp_now_del_peer(gloveMac);
    }
  }
}

void connectToGlove() {
  Serial.println("Searching for Glove across channels...");
  int channel = 1;
  while (!isRegistered) {
    // Set current channel
    esp_wifi_set_channel(channel, WIFI_SECOND_CHAN_NONE);
    
    AppMessage regMsg;
    regMsg.type = MSG_TYPE_REGISTER;
    memcpy(regMsg.box_mac, myMac, 6);
    regMsg.event = EVENT_NONE;
    regMsg.uid_len = 0;
    memset(regMsg.uid, 0, MAX_CUBE_UID_LEN);

    uint8_t broadcastMac[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
    esp_now_send(broadcastMac, (uint8_t *)&regMsg, sizeof(regMsg));
    
    Serial.printf("Broadcasting registration request on channel %d...\n", channel);
    
    // Wait 250ms on this channel for ACK
    unsigned long startWait = millis();
    while (millis() - startWait < 250) {
      if (isRegistered) break;
      delay(10);
    }
    
    if (!isRegistered) {
      channel++;
      if (channel > 13) channel = 1;
    }
  }
  Serial.printf("Registered with Glove. Locked on channel %d. Starting active loop...\n", channel);
  last_received_from_glove = millis();
  last_heartbeat_sent = millis();
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

    // Send 3 times with a short 20ms delay to guarantee packet receipt (redundancy)
    for (int i = 0; i < 3; i++) {
        esp_now_send(gloveMac, (uint8_t *)&msg, sizeof(msg));
        delay(20);
    }
}

void setup(void) {
  // Disable the brownout detector to prevent power dips from resetting the chip
  //WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0);

  Serial.begin(115200);
  delay(1000);
  Serial.println("\n--- [Smart Box] Booting ---");

  // Initialize NeoPixel Strip
  pixels.begin();
  writeLed(0, 0, 0); // Turn off



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

  // 4. Dynamic registration
  connectToGlove();
}

void loop(void) {
  // Run non-blocking LED animations
  updateLeds();

  if (!isRegistered) {
    connectToGlove();
    return;
  }

  // Handle heartbeat sending and timeout checking
  checkHeartbeats();

  if (nfcFound) {
    uint8_t success;
    uint8_t uid[] = { 0, 0, 0, 0, 0, 0, 0 };  // Buffer to store the returned UID
    uint8_t uidLength;                        // Length of the UID (4 or 7 bytes)

    // Wait for card with a 100ms timeout (non-blocking)
    success = nfc.readPassiveTargetID(PN532_MIFARE_ISO14443A, uid, &uidLength, 100);

    if (success) {
      Serial.println("Card Entered!");
      sendNfcEvent(EVENT_CUBE_ENTERED, uid, uidLength);
      
      // Card is present. Poll it in a loop to detect when it leaves.
      int consecutiveFailures = 0;
      while (consecutiveFailures < 5) {
        if (!isRegistered) {
          break; // Lost Glove connection while card is present
        }

        // Wait 100ms non-blockingly while running animations
        unsigned long startPoll = millis();
        while (millis() - startPoll < 100) {
            updateLeds();
            checkHeartbeats();
            delay(10);
        }
        
        uint8_t pollUid[7];
        uint8_t pollUidLength = 0;
        bool pollSuccess = nfc.readPassiveTargetID(PN532_MIFARE_ISO14443A, pollUid, &pollUidLength, 100);
        
        if (pollSuccess) {
          consecutiveFailures = 0; // Reset counter on successful scan
        } else {
          consecutiveFailures++;   // Increment on failed scan
        }
      }
      
      if (isRegistered) {
        Serial.println("Card Left!");
        sendNfcEvent(EVENT_CUBE_LEFT, uid, uidLength);
      }
    }
  }
}