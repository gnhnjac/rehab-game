# Firebase Realtime Database Specification

This document details the exact JSON data structures used by the Rehab Glove system in Firebase Realtime Database (RTDB). Both the ESP32 Glove (writer/backend) and the Flutter Web App (reader/frontend) adhere to this format.

---

## Database Root Path
All telemetry data is stored under the `/telemetry` node of the Realtime Database.

```
/ (Database Root)
└── telemetry
    ├── calibrated: bool
    ├── flex
    │   ├── raw: [int, int, int, int, int]
    │   └── percent: [int, int, int, int, int]
    ├── force
    │   ├── raw: [int]
    │   └── percent: [int]
    └── weights
        ├── <NFC_ID_1>: [timestamp_seconds, isPlaced, boxIndex]
        └── <NFC_ID_2>: [timestamp_seconds, isPlaced, boxIndex]
```

---

## 1. Live Telemetry Stream Document
The live stream document is updated constantly (e.g., every 500ms) by the Glove during active sessions. It provides real-time progress to the therapist/patient.

### Format (Calibrated State)
```json
{
  "calibrated": true,
  "flex": {
    "raw": [1240, 1310, 1150, 940, 1080],
    "percent": [65, 80, 50, 20, 40]
  },
  "force": {
    "raw": [450],
    "percent": [45]
  }
}
```

### Format (Uncalibrated State)
If the glove has not completed its startup calibration routine:
```json
{
  "calibrated": false
}
```

---

## 2. Weight Actions Map
This map tracks the physical movement of NFC weighted cubes between the active Smart Boxes. The key is the NFC Cube tag's UID (hex string), and the value is a tuple (represented as a JSON list/array).

### Path
`/telemetry/weights.json`

### Format
```json
{
  "04112233": [1718556488, true, 2],
  "04AA88CC": [1718556599, false, 1]
}
```

### Tuple Array Structure
For each entry `[timestamp, isPlaced, boxIndex]`:
1. **Timestamp** (`int`): The Unix epoch time (in seconds) of the action.
2. **isPlaced** (`bool`):
   - `true`: Weight was placed (הונח) in the box.
   - `false`: Weight was picked up / removed (הורם) from the box.
3. **boxIndex** (`int`): The `0-indexed` box identifier of the box where the action occurred.

---

## Protocol Implementation

### Glove Upload Actions (ESP32 REST API)
1. **Live Stream**: The glove sends an HTTP `PATCH` request to `/telemetry.json` with the current sensor data payload.
2. **Weight Event**: When the Glove receives an ESP-NOW event from a box, it constructs the hex `NFC_ID`, fetches the current Unix time via NTP, and sends an HTTP `PUT` request to `/telemetry/weights/<NFC_ID>.json` with the action array payload (e.g. `[1718556488, true, 2]`).

### Frontend Reading (Flutter Web App)
- The app establishes a single real-time database listener on the `/telemetry` node.
- Incoming snapshots are parsed into the `GloveTelemetry` Dart model. The `weights` map is dynamically deserialized from either JSON arrays or map objects for maximum robustness.
