#include <Wire.h>
#include <Adafruit_PN532.h>
#include <WiFi.h>
#include <esp_now.h>
#include <esp_wifi.h>
#include "soc/soc.h"
#include "soc/rtc_cntl_reg.h"
#include "../parameters.h"

#include <Adafruit_NeoPixel.h>

// PN532 NFC reader
Adafruit_PN532 nfc(SDA_PIN, SCL_PIN);

// --- NEOPIXEL STRIP CONFIGURATION ---
#define NEOPIXEL_PIN 13 // Change to your physical NeoPixel data GPIO pin
#define NUM_PIXELS 8    // Change to the number of LEDs in your strip

Adafruit_NeoPixel pixels(NUM_PIXELS, NEOPIXEL_PIN, NEO_GRB + NEO_KHZ800);

// --- PHYSICAL BUTTON PIN CONFIGURATION ---
#define BUTTON_PIN 4


// State variables
bool isRegistered = false;
bool nfcFound = false;
uint8_t gloveMac[6];
uint8_t myMac[6];

unsigned long last_received_from_glove = 0;
unsigned long last_heartbeat_sent = 0;

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
                setLedColor(0, 0, 0);
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
                setLedColor(0, 0, 0);
            } else {
                if (ledStep % 2 == 0) {
                    writeLed(255, 0, 0);
                } else {
                    writeLed(255, 255, 255);
                }
            }
        }
    }
    else if (currentLedMode == LED_MODE_IDENTIFY) {
        if (now - lastLedUpdate >= 150) {
            lastLedUpdate = now;
            ledStep++;
            if (ledStep > 20) {
                setLedColor(0, 0, 0);
            } else {
                if (ledStep % 2 == 0) {
                    writeLed(0, 0, 255);
                } else {
                    writeLed(0, 0, 0);
                }
            }
        }
    }
}

// --- SERIAL MP3 PLAYER (CATALEX YX5300) HARDWARE SERIAL ---
static const byte start_byte = 0x7E;
static const byte end_byte = 0xEF;
static const byte set_volume_CMD = 0x31;
static const byte play_filename_CMD = 0x42;
static const uint8_t select_SD_CMD[] = { 0x7E, 0x03, 0x35, 0x01, 0xEF };
static const uint8_t reset_CMD[] = { 0x7E, 0x03, 0x35, 0x05, 0xEF };

bool resetMp3() {
    Serial.println("[Audio] MP3 RESET");
    Serial2.flush();
    for (int i = 0; i < 5; i++) {
        Serial2.write(reset_CMD[i]);
    }
    delay(50);
    return Serial2.available() > 0;
}

void selectSdCard() {
    Serial.println("[Audio] MP3 Select SD Card");
    for (int i = 0; i < 5; i++) {
        Serial2.write(select_SD_CMD[i]);
    }
}

void setVolume(byte volume) {
    delay(20);
    Serial.printf("[Audio] Set volume = %d of 30\n", volume);
    Serial2.write(start_byte);
    Serial2.write(0x03); // Length
    Serial2.write(set_volume_CMD);
    Serial2.write(volume);
    Serial2.write(end_byte);
    delay(20);
}

void playFilename(int8_t directory, int8_t file) {
    Serial.printf("[Audio] Playing directory %d, file %d\n", directory, file);
    Serial2.write(start_byte);
    Serial2.write(0x04); // Length
    Serial2.write(play_filename_CMD);
    Serial2.write((byte)directory);
    Serial2.write((byte)file);
    Serial2.write(end_byte);
    delay(20);
}

void setupAudio() {
    Serial2.begin(9600, SERIAL_8N1, DFPLAYER_RX_PIN, DFPLAYER_TX_PIN);
    delay(100);
    if (resetMp3()) {
        Serial.println("[Audio] reset MP3 success");
    } else {
        Serial.println("[Audio] reset MP3 fail");
    }
    selectSdCard();
    delay(1200);
    setVolume(30);
}

void playAudioTrack(uint8_t cmd, uint8_t high_arg, uint8_t low_arg) {
    if (cmd == 0x06) {
        // Set volume cmd (low_arg contains volume)
        setVolume(low_arg);
    }
    else if (cmd == 0x0F) {
        // Play folder/file cmd (high_arg contains folder, low_arg contains file)
        playFilename(high_arg, low_arg);
    }
}

// Send callback (Empty)
void OnDataSent(const uint8_t *mac_addr, esp_now_send_status_t status) {}

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
            
            esp_now_peer_info_t peerInfo;
            memset(&peerInfo, 0, sizeof(peerInfo));
            memcpy(peerInfo.peer_addr, gloveMac, 6);
            peerInfo.channel = 0;
            peerInfo.encrypt = false;

            if (!esp_now_is_peer_exist(gloveMac)) {
                esp_now_add_peer(&peerInfo);
            }
            
            // Success audio chime on connection
            playAudioTrack(0x0F, 4, 1); // Success chime
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
            else if (cmdType == BOX_CMD_PLAY_AUDIO) {
                // Execute play command on local DFPlayer
                uint8_t high = msg.uid[0];
                uint8_t low = msg.uid[1];
                uint8_t cmd = msg.uid[2];
                playAudioTrack(cmd, high, low);
            }
            last_received_from_glove = millis();
        }
    }
}

void checkHeartbeats() {
  if (!isRegistered) return;
  unsigned long now = millis();
  
  if (now - last_heartbeat_sent > 1000) {
    AppMessage hbMsg;
    hbMsg.type = MSG_TYPE_HEARTBEAT;
    memcpy(hbMsg.box_mac, myMac, 6);
    esp_now_send(gloveMac, (uint8_t *)&hbMsg, sizeof(hbMsg));
    last_heartbeat_sent = now;
  }
  
  if (now - last_received_from_glove > 5000) {
    Serial.println("Glove timeout. Lost registration. Re-searching...");
    isRegistered = false;
    esp_now_del_peer(gloveMac);
  }
}

void connectToGlove() {
  int channel = 1;
  while (!isRegistered) {
    Serial.printf("Scanning for Glove on channel %d...\n", channel);
    esp_wifi_set_channel(channel, WIFI_SECOND_CHAN_NONE);
    
    AppMessage regMsg;
    regMsg.type = MSG_TYPE_REGISTER_MAIN; // Identify as Main Box
    memcpy(regMsg.box_mac, myMac, 6);
    regMsg.event = EVENT_NONE;
    regMsg.uid_len = 0;
    memset(regMsg.uid, 0, MAX_CUBE_UID_LEN);

    uint8_t broadcastMac[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
    esp_now_send(broadcastMac, (uint8_t *)&regMsg, sizeof(regMsg));
    
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
  Serial.printf("Registered Main Box with Glove. Channel: %d\n", channel);
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
    esp_now_send(gloveMac, (uint8_t *)&msg, sizeof(msg));
}

void sendButtonPressEvent(bool isLongPress) {
    if (!isRegistered) return;
    AppMessage msg;
    msg.type = MSG_TYPE_EVENT;
    memcpy(msg.box_mac, myMac, 6);
    msg.event = EVENT_BUTTON_PRESSED;
    msg.uid_len = 1;
    msg.uid[0] = isLongPress ? 1 : 0; // 1 = long press, 0 = short press
    memset(msg.uid + 1, 0, MAX_CUBE_UID_LEN - 1);
    esp_now_send(gloveMac, (uint8_t *)&msg, sizeof(msg));
    Serial.printf("[Button] Transmitted button press event (Long=%d) to Glove.\n", isLongPress);
}

void checkButton() {
    static bool lastButtonState = HIGH;
    bool currentButtonState = digitalRead(BUTTON_PIN);
    if (currentButtonState == LOW && lastButtonState == HIGH) {
        delay(50); // debounce
        if (digitalRead(BUTTON_PIN) == LOW) {
            unsigned long pressStart = millis();
            while (digitalRead(BUTTON_PIN) == LOW) {
                delay(10);
            }
            unsigned long duration = millis() - pressStart;
            if (duration > 1500) {
                sendButtonPressEvent(true); // Long press -> Calibrate
            } else {
                sendButtonPressEvent(false); // Short press -> Start/Stop
            }
        }
    }
    lastButtonState = currentButtonState;
}

void setup(void) {
  Serial.begin(115200);
  delay(1000);
  Serial.println("\n--- [Smart Box - Main] Booting ---");

  // Initialize NeoPixel Strip
  pixels.begin();
  writeLed(0, 0, 0); // Turn off


  pinMode(BUTTON_PIN, INPUT_PULLUP);

  // Initialize DFPlayer Mini
  setupAudio();

  // Initialize WiFi & ESP-NOW
  WiFi.mode(WIFI_STA);
  WiFi.macAddress(myMac);
  
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
  esp_now_add_peer(&peerInfo);

  // Initialize PN532
  nfc.begin();
  uint32_t versiondata = nfc.getFirmwareVersion();
  if (!versiondata) {
    Serial.println("WARNING: PN532 not found. Simulated NFC active.");
    nfcFound = false;
  } else {
    nfcFound = true;
    nfc.SAMConfig();
  }

  // Register with Glove
  connectToGlove();
}

void loop(void) {
  updateLeds();

  if (!isRegistered) {
    connectToGlove();
    return;
  }

  checkHeartbeats();

  // Monitor physical button press
  checkButton();

  // NFC scanning
  if (nfcFound) {
    uint8_t success;
    uint8_t uid[] = { 0, 0, 0, 0, 0, 0, 0 };
    uint8_t uidLength;

    success = nfc.readPassiveTargetID(PN532_MIFARE_ISO14443A, uid, &uidLength, 100);
    if (success) {
      Serial.println("Cube Entered!");
      sendNfcEvent(EVENT_CUBE_ENTERED, uid, uidLength);
      
      int consecutiveFailures = 0;
      while (consecutiveFailures < 5) {
        updateLeds();
        checkHeartbeats();
        if (!isRegistered) break;

        // Monitor button even while cube is present
        checkButton();

        delay(100);
        uint8_t pollUid[7];
        uint8_t pollUidLength = 0;
        bool pollSuccess = nfc.readPassiveTargetID(PN532_MIFARE_ISO14443A, pollUid, &pollUidLength, 100);
        
        if (pollSuccess) consecutiveFailures = 0;
        else consecutiveFailures++;
      }
      
      if (isRegistered) {
        Serial.println("Cube Left!");
        sendNfcEvent(EVENT_CUBE_LEFT, uid, uidLength);
      }
    }
  }
}
