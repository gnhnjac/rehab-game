//user defined parameters

// OLED display width and height, in pixels
#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64

//  4x3 keypad GPIO pins
#define R4   19 
#define R3   13 
#define R2   12 
#define R1   4    
#define C1   21 
#define C2   27 
#define C3   33  

// INMP441 I2S microphone GPIO pins
#define I2S_WS 14
#define I2S_SD 15
#define I2S_SCK 32
#define I2S_PORT I2S_NUM_0

// external DAC MAX98357A GPIO pins
#define DAC_BCK_PIN 26
#define DAC_WS_PIN 25
#define DAC_DATA_PIN 22

// --- GLOVE SENSOR CONFIGURATION ---
// NOTE: We use only ADC1 pins (32, 33, 34, 35, 36, 39) because ADC2 pins (like 25)
// cannot be read using analogRead() when Wi-Fi/ESP-NOW is active.
#define NUM_FINGERS 5
#define FLEX_PIN_1 33
#define FLEX_PIN_2 32
#define FLEX_PIN_3 35
#define FLEX_PIN_4 34
#define FLEX_PIN_5 36
#define FORCE_PIN 39 // Analog pin for FSR sensor (using Sensor VN pin)
#define CALIBRATION_BUTTON_PIN 4

// --- ESP-NOW PROTOCOL DEFINITIONS ---
#define MAX_CUBE_UID_LEN 7
#define MAX_BOXES 8

typedef enum {
    MSG_TYPE_REGISTER,     // Box -> Glove: Request registration
    MSG_TYPE_EVENT,        // Box -> Glove: NFC event
    MSG_TYPE_ACK           // Glove -> Box: Registration acknowledgment
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


