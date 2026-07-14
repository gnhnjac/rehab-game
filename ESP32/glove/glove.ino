#include <Arduino.h>
#include <Adafruit_DRV2605.h>
#include "soc/soc.h"
#include "soc/rtc_cntl_reg.h"

Adafruit_DRV2605 hapticDrv;
bool hapticEnabled = false;

#include "glove_haptic.h"
#include "glove_sensors.h"
#include "glove_audio.h"
#include "glove_game.h"
#include "glove_firebase.h"
#include "glove_espnow.h"
#include "glove_web_server.h"
#include "glove_sync.h"

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


// Time tracking
unsigned long lastPrintTime = 0;
const unsigned long printInterval = 500; // Print sensor states every 500ms
unsigned long lastSampleTime = 0;
const unsigned long sampleInterval = 20; // Sample sensors at 50Hz (every 20ms)

// Background upload task pinned to Core 0 (handling all Wi-Fi / HTTPS uploads)
void telemetryUploadTask(void* parameter) {
    unsigned long lastUploadTime = 0;
    const unsigned long uploadInterval = 500; // Upload telemetry to Firebase every 500ms
    
    for (;;) {
        // Sleep for a short duration to yield CPU to other Core 0 system tasks (like Wi-Fi stack)
        vTaskDelay(pdMS_TO_TICKS(20));

        // Handle local HTTP / captive portal requests
        handleNetworkRequests();
        
        // 1. Process any deferred Firebase BoxAction uploads from the ESP-NOW queue
        BoxActionEvent pendingEvent;
        if (popEvent(pendingEvent)) {
            uploadBoxAction(pendingEvent.cubeId, pendingEvent.timestamp, pendingEvent.isPlaced, pendingEvent.boxIndex);
        }

        // 2. Run sync bridge to upload any buffered offline logs
        static unsigned long lastSyncTime = 0;
        if (millis() - lastSyncTime >= 5000) { // Check sync queue every 5 seconds
            lastSyncTime = millis();
            syncBufferedLogs();
        }

        // 3. Periodically upload live telemetry (Disabled to prevent blocking local HTTP requests)
        /*
        if (millis() - lastUploadTime >= uploadInterval) {
            lastUploadTime = millis();
            
            SensorTelemetryData localData;
            // Safely fetch a local copy of the shared telemetry data
            if (xSemaphoreTake(telemetryMutex, portMAX_DELAY) == pdTRUE) {
                localData = sharedTelemetry;
                xSemaphoreGive(telemetryMutex);
            }
            
            if (localData.calibrated) {
                uploadLiveTelemetry(true, localData.flexRaw, localData.flexPercent, localData.forceRaw, localData.forcePercent);
            } else {
                uploadLiveTelemetry(false, nullptr, nullptr, 0, 0);
            }
        }
        */
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
    setupWebServer();

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

    // Create a mutex to protect shared telemetry data across cores
    telemetryMutex = xSemaphoreCreateMutex();

    // Spawn the background uploading task on Core 0
    xTaskCreatePinnedToCore(
        telemetryUploadTask,     // Task function
        "TelemetryUploadTask",   // Task name
        8192,                    // Stack size (8KB is plenty for WiFiClientSecure/HTTPS)
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

    // Check calibration / start button (now triggered wirelessly via ESP-NOW from Main Box)
    if (pendingButtonPress) {
        pendingButtonPress = false;
        
        if (sessionState.active) {
            // If game session is running, button stops it
            Serial.println("[Button] Game session aborted by wireless button press.");
            stopGameSession(false);
        } 
        else if (currentPrescription.gameType != GAME_NONE) {
            // If prescription is loaded but game is not active, button starts it
            Serial.println("[Button] Starting game session by wireless button press.");
            startNewGameSession();
        } 
        else {
            // Default calibration mode
            isCalibrated = false;
            if (xSemaphoreTake(telemetryMutex, portMAX_DELAY) == pdTRUE) {
                sharedTelemetry.calibrated = false;
                xSemaphoreGive(telemetryMutex);
            }
            runSensorCalibration(5); // Default 5 seconds
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
