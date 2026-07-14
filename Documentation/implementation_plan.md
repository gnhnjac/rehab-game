# Implementation Plan: Glove Rehabilitation - Basic Communication & Sensor Integration

This plan implements the initial phase of the glove rehabilitation project: verifying P2P communication (using ESP-NOW), dynamic box registration, cube tracking, and calibrated sensor readings (flex and force) with output via the Serial monitor.

---

## Proposed System Architecture

### 1. Smart Box (Client)
- **PN532 NFC Reader**: Detects NFC cubes. Implements debounced scanning (cube entered and cube left).
- **ESP-NOW client**: 
  - On startup, sends registration request to the Glove.
  - Sends cube enter and leave events to the Glove.
- **Visuals/Audio**: None for now (saved for later).

### 2. Glove (Server)
- **ESP-NOW server**:
  - Dynamically registers boxes on pairing messages.
  - Tracks which box has which cube (registry of boxes and cubes).
  - Receives cube enter/leave events and prints status to Serial.
- **Sensors**: 
  - Reads 5 flex sensors and 1 force (FSR) sensor.
  - Calibrates sensors (min/max range mapped to 0-100%) when a button is pressed.
- **UI/Display**: None (all output goes to Serial Monitor).
- **Game Engine**: None (deferred to verification of basic connectivity first).

---

## Technical Details

### 1. Data Registry (Glove)
The glove will maintain:
- A box registry using `std::unordered_map<uint64_t, RegisteredBox>` where the MAC address is packed into a 64-bit key for fast, O(1) lookup.
- A state map of where cubes are located (each registered box maps to the cube's UID currently inside).

### 2. Communication Packet

```cpp
typedef enum {
    MSG_TYPE_REGISTER,     // Box -> Glove: Register me
    MSG_TYPE_EVENT,        // Box -> Glove: NFC event
    MSG_TYPE_ACK           // Glove -> Box: Acknowledgement
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
```

---

## Proposed Changes

### [MODIFY] [parameters.h](file:///c:/Users/gnhnj/Programming/rehab-game/ESP32/parameters.h)
- Define pins for flex sensors, force sensor, button, and I2C lines.
- Define ESP-NOW message structure.

### [NEW] [glove.ino](file:///c:/Users/gnhnj/Programming/rehab-game/ESP32/glove/glove.ino)
- Main sketch file that handles the setup and main loop, calling functions from the modular helper headers.

### [NEW] [glove_sensors.h](file:///c:/Users/gnhnj/Programming/rehab-game/ESP32/glove/glove_sensors.h)
- Implements calibration and filtered reading of the 5 flex sensors and 1 FSR force sensor.

### [NEW] [glove_espnow.h](file:///c:/Users/gnhnj/Programming/rehab-game/ESP32/glove/glove_espnow.h)
- Implements the ESP-NOW server, dynamic box registration, and packet parsing using a `std::unordered_map` lookup by MAC address.

### [NEW] [smart_box.ino](file:///c:/Users/gnhnj/Programming/rehab-game/ESP32/smart_box/smart_box.ino)
- Scan for NFC tags using PN532.
- Debounce tags (ensure stable enter/leave state transitions).
- Connect via ESP-NOW and register with the Glove.
- Send event updates to the Glove.

---

## Verification Plan

### Automated / Compiler Verification
- Compile both the Glove and Smart Box sketches to ensure no syntax/compilation issues.

### Manual Verification
- Confirm dynamic registration: Box boots up, registers with Glove, Glove prints connection message.
- Confirm NFC event reporting: Placing cube on Box triggers enter event on Glove; removing it triggers leave event.
- Confirm sensor calibration: Pressing the calibration button starts a 5-second calibration for all 5 flex sensors + FSR, then outputs 0-100% values correctly.
