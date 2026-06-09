#include <esp_now.h>
#include <WiFi.h>
#include "../parameters.h"

// --- Global Variables ---
struct RegisteredBox {
    uint8_t mac[6];
    uint8_t current_cube_uid[MAX_CUBE_UID_LEN];
    uint8_t current_cube_len;
    bool active;
};

RegisteredBox boxes[MAX_BOXES];
int registeredBoxCount = 0;

// Sensor calibration data
const int flexPins[NUM_FINGERS] = {FLEX_PIN_1, FLEX_PIN_2, FLEX_PIN_3, FLEX_PIN_4, FLEX_PIN_5};
int flexMin[NUM_FINGERS];
int flexMax[NUM_FINGERS];
float flexSmoothed[NUM_FINGERS];

int forceMin = 4095;
int forceMax = 0;
float forceSmoothed = 0;

bool isCalibrated = false;
const float filterWeight = 0.10;

// Print rate limiter
unsigned long lastPrintTime = 0;
const unsigned long printInterval = 500; // Print sensor/registry states every 500ms

// --- Helper Functions ---
void printMac(const uint8_t *mac) {
    for (int i = 0; i < 6; i++) {
        Serial.printf("%02X", mac[i]);
        if (i < 5) Serial.print(":");
    }
}

int findBoxIndex(const uint8_t *mac) {
    for (int i = 0; i < registeredBoxCount; i++) {
        if (memcmp(boxes[i].mac, mac, 6) == 0) {
            return i;
        }
    }
    return -1;
}

// --- ESP-NOW Receive Callback ---
#if defined(ESP_ARDUINO_VERSION_MAJOR) && ESP_ARDUINO_VERSION_MAJOR >= 3
void OnDataRecv(const esp_now_recv_info_t * recvInfo, const uint8_t *incomingData, int len) {
    const uint8_t *incoming_mac = recvInfo->src_addr;
#else
void OnDataRecv(const uint8_t * incoming_mac, const uint8_t *incomingData, int len) {
#endif
    if (len < sizeof(AppMessage)) {
        Serial.println("Warning: Received packet too small!");
        return;
    }

    AppMessage msg;
    memcpy(&msg, incomingData, sizeof(AppMessage));

    // Handle Box dynamic registration
    if (msg.type == MSG_TYPE_REGISTER) {
        Serial.print("[ESP-NOW] Registration request from Box: ");
        printMac(incoming_mac);
        Serial.println();

        int index = findBoxIndex(incoming_mac);
        if (index == -1) {
            if (registeredBoxCount < MAX_BOXES) {
                index = registeredBoxCount;
                memcpy(boxes[index].mac, incoming_mac, 6);
                boxes[index].active = true;
                boxes[index].current_cube_len = 0;
                memset(boxes[index].current_cube_uid, 0, MAX_CUBE_UID_LEN);
                registeredBoxCount++;

                Serial.print("[Glove] Registered new Smart Box. Total connected: ");
                Serial.println(registeredBoxCount);

                // Add box as peer to send ACK back
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
    
    // Handle NFC Cube events
    else if (msg.type == MSG_TYPE_EVENT) {
        int index = findBoxIndex(incoming_mac);
        if (index == -1) {
            Serial.print("[Glove] Warning: Received event from unregistered Box: ");
            printMac(incoming_mac);
            Serial.println();
            return;
        }

        if (msg.event == EVENT_CUBE_ENTERED) {
            boxes[index].current_cube_len = msg.uid_len;
            memcpy(boxes[index].current_cube_uid, msg.uid, msg.uid_len);

            Serial.print("[EVENT] Cube ENTERED Box [");
            printMac(incoming_mac);
            Serial.print("] - Cube UID: ");
            for (uint8_t i = 0; i < msg.uid_len; i++) {
                Serial.printf(" %02X", msg.uid[i]);
            }
            Serial.println();
        } 
        else if (msg.event == EVENT_CUBE_LEFT) {
            boxes[index].current_cube_len = 0;
            memset(boxes[index].current_cube_uid, 0, MAX_CUBE_UID_LEN);

            Serial.print("[EVENT] Cube LEFT Box [");
            printMac(incoming_mac);
            Serial.println("]");
        }
    }
}

// --- Sensor Calibration Routine ---
void runCalibration() {
    Serial.println("\n=================================");
    Serial.println("--- GLOVE SENSOR CALIBRATION ---");
    Serial.println("Fully FLEX and EXTEND all fingers, and SQUEEZE the force sensor.");
    Serial.println("Calibration will run for 5 seconds...");
    Serial.println("=================================");

    // Initialize/reset limits
    for (int i = 0; i < NUM_FINGERS; i++) {
        flexMin[i] = 4095;
        flexMax[i] = 0;
        flexSmoothed[i] = analogRead(flexPins[i]);
    }
    forceMin = 4095;
    forceMax = 0;
    forceSmoothed = analogRead(FORCE_PIN);

    unsigned long startTime = millis();
    unsigned long lastStatusPrint = 0;

    while (millis() - startTime < 5000) {
        // Calibrate Flex Sensors
        for (int i = 0; i < NUM_FINGERS; i++) {
            int raw = analogRead(flexPins[i]);
            flexSmoothed[i] = (raw * filterWeight) + (flexSmoothed[i] * (1.0 - filterWeight));
            
            if (flexSmoothed[i] < flexMin[i]) flexMin[i] = (int)flexSmoothed[i];
            if (flexSmoothed[i] > flexMax[i]) flexMax[i] = (int)flexSmoothed[i];
        }

        // Calibrate Force Sensor (FSR)
        int rawForce = analogRead(FORCE_PIN);
        forceSmoothed = (rawForce * filterWeight) + (forceSmoothed * (1.0 - filterWeight));

        if (forceSmoothed < forceMin) forceMin = (int)forceSmoothed;
        if (forceSmoothed > forceMax) forceMax = (int)forceSmoothed;

        // Print countdown every second
        if (millis() - lastStatusPrint >= 1000) {
            int elapsedSec = (millis() - startTime) / 1000;
            Serial.printf("Calibrating... %d/5s remaining\n", 5 - elapsedSec);
            lastStatusPrint = millis();
        }
        delay(10);
    }

    // Safeguard to prevent division by zero in map() if range is zero
    for (int i = 0; i < NUM_FINGERS; i++) {
        if (flexMax[i] == flexMin[i]) flexMax[i]++;
    }
    if (forceMax == forceMin) forceMax++;

    isCalibrated = true;
    Serial.println("--- CALIBRATION COMPLETE ---");
    Serial.println("Calibration calibration values (Min -> Max):");
    for (int i = 0; i < NUM_FINGERS; i++) {
        Serial.printf("  Finger %d: %d -> %d\n", i + 1, flexMin[i], flexMax[i]);
    }
    Serial.printf("  Force FSR: %d -> %d\n", forceMin, forceMax);
    Serial.println("=================================\n");
}

void setup() {
    Serial.begin(115200);
    delay(1000);
    Serial.println("[Glove] Starting central server...");

    // Setup input pins
    pinMode(CALIBRATION_BUTTON_PIN, INPUT_PULLUP);
    for (int i = 0; i < NUM_FINGERS; i++) {
        pinMode(flexPins[i], INPUT);
    }
    pinMode(FORCE_PIN, INPUT);

    // Initialize WiFi in Station mode
    WiFi.mode(WIFI_STA);
    Serial.print("[Glove] MAC Address: ");
    Serial.println(WiFi.macAddress());

    // Initialize ESP-NOW
    if (esp_now_init() != ESP_OK) {
        Serial.println("[Glove] Error: Failed to initialize ESP-NOW!");
        while (1) delay(100);
    }

    // Register callback for receiving data
    esp_now_register_recv_cb(OnDataRecv);

    Serial.println("[Glove] ESP-NOW initialized. Waiting for Smart Boxes...");
    Serial.println("[Glove] Press the Calibration Button (GPIO 4) to start calibration.");
}

void loop() {
    // Check calibration button
    if (digitalRead(CALIBRATION_BUTTON_PIN) == LOW) {
        delay(50); // Debounce
        if (digitalRead(CALIBRATION_BUTTON_PIN) == LOW) {
            // Wait for release
            while (digitalRead(CALIBRATION_BUTTON_PIN) == LOW) {
                delay(10);
            }
            runCalibration();
        }
    }

    // Read and print sensor readings + registry state
    if (isCalibrated && (millis() - lastPrintTime >= printInterval)) {
        lastPrintTime = millis();

        // 1. Read Sensors and Map to 0-100%
        int flexPercent[NUM_FINGERS];
        for (int i = 0; i < NUM_FINGERS; i++) {
            int raw = analogRead(flexPins[i]);
            flexSmoothed[i] = (raw * filterWeight) + (flexSmoothed[i] * (1.0 - filterWeight));
            
            // Map min/max to 0-100%
            flexPercent[i] = map((int)flexSmoothed[i], flexMin[i], flexMax[i], 0, 100);
            flexPercent[i] = constrain(flexPercent[i], 0, 100);
        }

        int rawForce = analogRead(FORCE_PIN);
        forceSmoothed = (rawForce * filterWeight) + (forceSmoothed * (1.0 - filterWeight));
        int forcePercent = map((int)forceSmoothed, forceMin, forceMax, 0, 100);
        forcePercent = constrain(forcePercent, 0, 100);

        // 2. Print Sensor Output
        Serial.print("Flex: [");
        for (int i = 0; i < NUM_FINGERS; i++) {
            Serial.print(flexPercent[i]);
            if (i < NUM_FINGERS - 1) Serial.print("%, ");
        }
        Serial.printf("%%] | Force (FSR): %d%%\n", forcePercent);

        // 3. Print Box Registry and Cube Placements
        if (registeredBoxCount > 0) {
            Serial.println("--- Cube Placements Registry ---");
            for (int i = 0; i < registeredBoxCount; i++) {
                Serial.print("  Box [");
                printMac(boxes[i].mac);
                Serial.print("]: ");
                if (boxes[i].current_cube_len > 0) {
                    Serial.print("Cube UID =");
                    for (int j = 0; j < boxes[i].current_cube_len; j++) {
                        Serial.printf(" %02X", boxes[i].current_cube_uid[j]);
                    }
                } else {
                    Serial.print("[EMPTY]");
                }
                Serial.println();
            }
            Serial.println("--------------------------------");
        }
    } 
    else if (!isCalibrated && (millis() - lastPrintTime >= 3000)) {
        // Prompt user to calibrate every 3 seconds if not calibrated
        lastPrintTime = millis();
        Serial.println("[Glove] Awaiting sensor calibration. Press the button to begin.");
    }
}
