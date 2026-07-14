#include <Arduino.h>
#include <Adafruit_DRV2605.h>
#include "soc/soc.h"
#include "soc/rtc_cntl_reg.h"

Adafruit_DRV2605 hapticDrv;
bool hapticEnabled = false;

#include "glove_haptic.h"
#include "glove_sensors.h"
#include "glove_audio.h"
#include "glove_network.h"
#include "glove_sync.h"
#include "glove_game.h"
#include "glove_espnow.h"
#include "glove_web_server.h"

// Shared telemetry state variables
SensorTelemetryData sharedTelemetry;
SemaphoreHandle_t telemetryMutex;

// Global definitions (declared extern in headers)
std::unordered_map<uint64_t, RegisteredBox> boxRegistry;

WebServer server(80);
DNSServer dnsServer;
Preferences preferences;
bool isAPMode = false;
String connectedSSID = "";
IPAddress localIP;
String scanResultsHtml = "";
CommandEvent pendingCommand = {"", 5, false};

bool ntpInitialized = false;
BoxActionEvent eventQueue[MAX_PENDING_EVENTS];
volatile int queueHead = 0;
volatile int queueTail = 0;

int flexMin[NUM_FINGERS];
int flexMax[NUM_FINGERS];
float flexSmoothed[NUM_FINGERS];
int forceMin = 4095;
int forceMax = 0;
float forceSmoothed = 0;
bool isCalibrated = false;

// Global Game Variables
GamePrescription currentPrescription;
GameSessionState sessionState;

// Piecewise linear force calibration coefficients (raw ADC -> grams)
int fsrCalRaw[3] = {4095, 2000, 500};
int fsrCalGrams[3] = {0, 100, 500};

// Main Box wireless communication state
uint8_t mainBoxMac[6] = {0};
bool mainBoxRegistered = false;
volatile bool pendingButtonPress = false;
volatile bool buttonPressIsLong = false;


// Time tracking
unsigned long lastPrintTime = 0;
const unsigned long printInterval = 500; // Print sensor states every 500ms
unsigned long lastSampleTime = 0;
const unsigned long sampleInterval = 20; // Sample sensors at 50Hz (every 20ms)

// Background network task pinned to Core 0 (handling local HTTP server and offline sync)
void networkTask(void* parameter) {
    for (;;) {
        // Sleep for a short duration to yield CPU to other Core 0 system tasks (like Wi-Fi stack)
        vTaskDelay(pdMS_TO_TICKS(20));

        // Handle local HTTP / captive portal requests
        handleNetworkRequests();
        
        // Process any deferred NFC events from the ESP-NOW queue
        BoxActionEvent pendingEvent;
        if (popEvent(pendingEvent)) {
            // Events are now processed locally by the game engine
            Serial.printf("[Event] Box %d cube %s %s\n", 
                pendingEvent.boxIndex, pendingEvent.cubeId.c_str(),
                pendingEvent.isPlaced ? "placed" : "removed");
        }

        // Run sync bridge to upload any buffered offline logs
        static unsigned long lastSyncTime = 0;
        if (millis() - lastSyncTime >= 5000) { // Check sync queue every 5 seconds
            lastSyncTime = millis();
            syncBufferedLogs();
        }
    }
}

void setup() {
    // Disable the brownout detector to prevent power dips from resetting the chip
    //WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0);

    Serial.begin(115200);
    delay(1000);
    Serial.println("[Glove] Central server starting...");

    setupNetwork();
    setupSPIFFS();
    setupSensors();
    setupHaptic();
    setupAudio(); // Initialize UART audio module
    setupEspNow();


    // Load calibration coefficients from Preferences
    preferences.begin("calibration", true);
    fsrCalRaw[0] = preferences.getInt("fsr_r0", 4095);
    fsrCalRaw[1] = preferences.getInt("fsr_r1", 2000);
    fsrCalRaw[2] = preferences.getInt("fsr_r2", 500);
    fsrCalGrams[0] = preferences.getInt("fsr_g0", 0);
    fsrCalGrams[1] = preferences.getInt("fsr_g1", 100);
    fsrCalGrams[2] = preferences.getInt("fsr_g2", 500);
    
    for (int i = 0; i < NUM_FINGERS; i++) {
        char keyMin[16], keyMax[16];
        sprintf(keyMin, "fl_min_%d", i);
        sprintf(keyMax, "fl_max_%d", i);
        flexMin[i] = preferences.getInt(keyMin, 0);
        flexMax[i] = preferences.getInt(keyMax, 4095);
    }
    isCalibrated = preferences.getBool("is_calibrated", false);
    preferences.end();

    // Load last persisted prescription from NVS if available
    GamePrescription savedRx;
    if (loadPrescriptionFromNVS(savedRx)) {
        currentPrescription = savedRx;
        Serial.printf("[Setup] Restored last game prescription. GameType: %d\n", currentPrescription.gameType);
    }

    // Create a mutex to protect shared telemetry data across cores
    telemetryMutex = xSemaphoreCreateMutex();

    // Spawn the background network task on Core 0
    xTaskCreatePinnedToCore(
        networkTask,             // Task function
        "NetworkTask",           // Task name
        8192,                    // Stack size
        NULL,                    // Parameter passed to task
        1,                       // Task priority
        NULL,                    // Task handle
        0                        // Core ID (0 is the Wi-Fi/system core)
    );

    Serial.println("[Glove] Multitasking initialized.");
    Serial.println("[Glove] ESP-NOW initialized. Waiting for Smart Boxes...");
    Serial.println("[Glove] Press the Calibration Button (GPIO 4) to start calibration.");
}

void loop() {
    // Process any deferred calibration commands from the web server
    if (pendingCommand.pending) {
        if (pendingCommand.cmd == "calibrate") {
            // Set uncalibrated state before running blocking calibration so background task uploads it immediately
            isCalibrated = false;
            if (xSemaphoreTake(telemetryMutex, portMAX_DELAY) == pdTRUE) {
                sharedTelemetry.calibrated = false;
                xSemaphoreGive(telemetryMutex);
            }
            // Trigger the remote calibration with requested time
            runSensorCalibration(pendingCommand.time);
        }
        pendingCommand.pending = false; // Reset command
    }

    // Periodically clean up timed-out boxes
    checkBoxTimeouts();

    // Check calibration / start button (triggered wirelessly via ESP-NOW from Main Box)
    if (pendingButtonPress) {
        pendingButtonPress = false;
        
        if (buttonPressIsLong) {
            // Long press: start calibration at any time
            Serial.println("[Button] Long press detected! Starting sensor calibration...");
            isCalibrated = false;
            if (xSemaphoreTake(telemetryMutex, portMAX_DELAY) == pdTRUE) {
                sharedTelemetry.calibrated = false;
                xSemaphoreGive(telemetryMutex);
            }
            runSensorCalibration(5); // 5-second calibration
        } 
        else {
            // Short press: handle game start/stop
            if (sessionState.active) {
                Serial.println("[Button] Short press: aborting game session.");
                stopGameSession(false);
            } 
            else if (currentPrescription.gameType != GAME_NONE) {
                Serial.println("[Button] Short press: starting game session.");
                startNewGameSession();
            } 
            else {
                // If no prescription loaded, short press falls back to calibration
                Serial.println("[Button] Short press: no prescription loaded, starting calibration...");
                isCalibrated = false;
                if (xSemaphoreTake(telemetryMutex, portMAX_DELAY) == pdTRUE) {
                    sharedTelemetry.calibrated = false;
                    xSemaphoreGive(telemetryMutex);
                }
                runSensorCalibration(5);
            }
        }
    }

    // Read and sample sensors at a fixed frequency of 50Hz (Core 1)
    if (millis() - lastSampleTime >= sampleInterval) {
        lastSampleTime = millis();
        
        if (isCalibrated) {
            int flexRaw[NUM_FINGERS];
            int flexPercent[NUM_FINGERS];
            int forceRaw = 0;
            int forcePercent = 0;
            readAllSensors(flexRaw, flexPercent, forceRaw, forcePercent);

            // Safely write the fresh readings to the shared structure
            if (xSemaphoreTake(telemetryMutex, 0) == pdTRUE) {
                sharedTelemetry.calibrated = true;
                memcpy(sharedTelemetry.flexRaw, flexRaw, sizeof(flexRaw));
                memcpy(sharedTelemetry.flexPercent, flexPercent, sizeof(flexPercent));
                sharedTelemetry.forceRaw = forceRaw;
                sharedTelemetry.forcePercent = forcePercent;
                xSemaphoreGive(telemetryMutex);
            }

            // Print standard serial output for debugging at the print interval
            if (millis() - lastPrintTime >= printInterval) {
                lastPrintTime = millis();
                Serial.print("Flex: [");
                for (int i = 0; i < NUM_FINGERS; i++) {
                    Serial.print(flexPercent[i]);
                    if (i < NUM_FINGERS - 1) Serial.print("%, ");
                }
                Serial.printf("%%] | Force (FSR): %d%%\n", forcePercent);
                printRegistry();
            }
        } 
        else {
            // Uncalibrated state
            if (xSemaphoreTake(telemetryMutex, 0) == pdTRUE) {
                sharedTelemetry.calibrated = false;
                xSemaphoreGive(telemetryMutex);
            }
            
            if (millis() - lastPrintTime >= printInterval) {
                lastPrintTime = millis();
                Serial.println("[Glove] Awaiting sensor calibration. Press the button to begin.");
            }
        }
    }
    
    // Update active game logic state machines
    updateGame();
}
