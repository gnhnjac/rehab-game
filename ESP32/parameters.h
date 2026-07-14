#pragma once
#include <Arduino.h>
#include <unordered_map>

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
    MSG_TYPE_REGISTER,      // Box -> Glove: Request registration (Secondary Box)
    MSG_TYPE_REGISTER_MAIN, // Main Box -> Glove: Request registration (Main Box)
    MSG_TYPE_EVENT,         // Box -> Glove: NFC event or button press
    MSG_TYPE_ACK,           // Glove -> Box: Registration acknowledgment
    MSG_TYPE_HEARTBEAT,     // Bidirectional: Connection keep-alive
    MSG_TYPE_COMMAND        // Glove -> Box: Command packet (LED, audio, identify, etc.)
} MsgType;

// Glove -> Box commands (carried in event/uid fields of AppMessage)
typedef enum {
    BOX_CMD_SET_LED,       // Set LED to solid color (color in uid[0..2] as R, G, B)
    BOX_CMD_FLASH_SUCCESS, // Trigger rainbow/random flash
    BOX_CMD_FLASH_FAILURE, // Trigger red/white sync blink
    BOX_CMD_IDENTIFY,      // Trigger identify flash
    BOX_CMD_PLAY_AUDIO     // Play audio track (Folder in uid[0], Track in uid[1])
} BoxCmdType;

// --- DFPLAYER PIN CONFIGURATION (Main Box UART2) ---
#define DFPLAYER_RX_PIN 17
#define DFPLAYER_TX_PIN 16

typedef enum {
    EVENT_NONE,
    EVENT_CUBE_ENTERED,
    EVENT_CUBE_LEFT,
    EVENT_BUTTON_PRESSED   // Main Box -> Glove: Physical button pressed
} CubeEventType;


typedef struct {
    uint8_t type;            // MsgType (uint8_t to ensure size consistency)
    uint8_t box_mac[6];      // MAC address of the box
    uint8_t event;           // CubeEventType
    uint8_t uid[MAX_CUBE_UID_LEN]; // NFC tag UID
    uint8_t uid_len;         // Length of UID (4 or 7 bytes)
} __attribute__((packed)) AppMessage;

struct RegisteredBox {
    uint8_t mac[6];
    uint8_t current_cube_uid[MAX_CUBE_UID_LEN];
    uint8_t current_cube_len;
    bool active;
    unsigned long last_seen;
};

// Box registry extern declaration (defined in glove.ino)
extern std::unordered_map<uint64_t, RegisteredBox> boxRegistry;
extern SemaphoreHandle_t registryMutex;

struct RegistryLock {
    RegistryLock() {
        if (registryMutex) {
            xSemaphoreTakeRecursive(registryMutex, portMAX_DELAY);
        }
    }
    ~RegistryLock() {
        if (registryMutex) {
            xSemaphoreGiveRecursive(registryMutex);
        }
    }
};

// --- TELEMETRY SHARED DATA STRUCTURE ---
typedef struct {
    bool calibrated;
    bool calibrating;
    int time_remaining;
    int flexRaw[NUM_FINGERS];
    int flexPercent[NUM_FINGERS];
    int forceRaw;
    int forcePercent;
} SensorTelemetryData;

// --- GAME PRESCRIPTION & STATE STRUCTURES ---
enum GameType {
    GAME_NONE = 0,
    GAME_CUBES_BOXES = 1,
    GAME_PINCH = 2,
    GAME_BEND = 3
};

struct RxCube {
    uint8_t uid[MAX_CUBE_UID_LEN];
    uint8_t uid_len = 0;
    char color[16] = "";
    char shape[16] = "";
    int weightGrams = 0;
};

struct GamePrescription {
    GameType gameType = GAME_NONE;
    int timerSeconds = 60;
    int totalCycles = 3;
    int difficulty = 1;
    RxCube cubes[8];
    int cubesCount = 0;
    int targetWeightGrams = 100;
    int requiredHoldTimeSeconds = 5;
    int activeFingers[NUM_FINGERS] = {0}; // 1 = active, 0 = inactive
    int requiredRom[NUM_FINGERS] = {0}; // target percentages
    int sequence[NUM_FINGERS] = {0}; // sequence of finger indexes (1-indexed, e.g. 1=thumb, 2=index)
    int sequenceCount = 0;
};

struct GameSessionState {
    bool active = false;
    unsigned long startTime = 0;
    unsigned long timerEndMillis = 0;
    unsigned long lastCountdownTime = 0;
    int currentCycle = 0;
    int successCount = 0;
    int failureCount = 0;
    unsigned long totalResponseTimeMs = 0;
    unsigned long lastActionTime = 0;
    
    // Pinch / Bend specific variables
    bool isHolding = false;
    unsigned long holdStartTime = 0;
    unsigned long lastWarningTime = 0;
    int currentStepInSequence = 0; // For Bend sequence
    
    // Target indicators (CubesBoxes)
    int targetBoxIndex = -1;
    uint8_t targetBoxMac[6] = {0};
    RxCube targetCube;

    // Accumulators for metrics
    float sumSteadyForce = 0;
    int countSteadyForce = 0;
    float maxBendRom = 0;
    float sumHoldRom = 0;
    int countHoldRom = 0;
    
    // Countdown tracking flags
    bool played10sPrompt = false;
    bool played5sPrompt = false;
};

extern GameSessionState sessionState;
extern GamePrescription currentPrescription;
extern bool lastSessionCompletedSuccess;


