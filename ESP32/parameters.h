#pragma once
//user defined parameters

// --- I2C CONFIGURATION FOR SENSORS/HAPTICS ---
#define SDA_PIN 21
#define SCL_PIN 22

// --- GLOVE SENSOR CONFIGURATION ---
// NOTE: We use only ADC1 pins (32, 33, 34, 35, 36, 39) because ADC2 pins (like 2)
// cannot be read using analogRead() when Wi-Fi/ESP-NOW is active.
// Labeled pins on the DOIT ESP32 board:
// - GPIO 36 is labeled VP
// - GPIO 39 is labeled VN
// - GPIO 34 is labeled D34
// - GPIO 35 is labeled D35
// - GPIO 32 is labeled D32
// - GPIO 33 is labeled D33

#define NUM_FINGERS 5

#define FLEX_PIN_1 33  // Labeled D33
#define FLEX_PIN_2 32  // Labeled D32
#define FLEX_PIN_3 35  // Labeled D35
#define FLEX_PIN_4 34  // Labeled D34
#define FLEX_PIN_5 39  // Labeled VN
#define FORCE_PIN 36   // Labeled VP

#define CALIBRATION_BUTTON_PIN 4
#define SENSOR_FILTER_WEIGHT 0.1f // Larger weight responds faster with less smoothing

// --- ESP-NOW PROTOCOL DEFINITIONS ---
#define MAX_CUBE_UID_LEN 7
#define MAX_BOXES 8

typedef enum {
    MSG_TYPE_REGISTER,     // Box -> Glove: Request registration
    MSG_TYPE_EVENT,        // Box -> Glove: NFC event
    MSG_TYPE_ACK,          // Glove -> Box: Registration acknowledgment
    MSG_TYPE_HEARTBEAT     // Bidirectional: Connection keep-alive
} MsgType;

typedef enum {
    EVENT_NONE,
    EVENT_CUBE_ENTERED,
    EVENT_CUBE_LEFT
} CubeEventType;

typedef struct {
    uint8_t type;            // MsgType (uint8_t to ensure size consistency)
    uint8_t box_mac[6];      // MAC address of the box
    uint8_t event;           // CubeEventType
    uint8_t uid[MAX_CUBE_UID_LEN]; // NFC tag UID
    uint8_t uid_len;         // Length of UID (4 or 7 bytes)
} __attribute__((packed)) AppMessage;


