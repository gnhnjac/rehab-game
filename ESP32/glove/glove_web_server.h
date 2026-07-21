#ifndef GLOVE_WEB_SERVER_H
#define GLOVE_WEB_SERVER_H

#include <WiFi.h>
#include <WebServer.h>
#include <DNSServer.h>
#include <Preferences.h>
#include <ESPmDNS.h>
#include <esp_wifi.h>
#include "glove_secrets.h"
#include "../parameters.h"
#include "glove_game.h"


extern SessionStopReason lastSessionExitReason;

// Web Server instance on port 80
extern WebServer server;

// DNS Server instance (for captive portal)
extern DNSServer dnsServer;

// Preferences instance (persistent NVS storage)
extern Preferences preferences;

// Network State
extern bool isAPMode;
extern String connectedSSID;
extern IPAddress localIP;

// Scanned networks cache
extern String scanResultsHtml;

// Shared structures (declared extern to link with glove.ino)
extern SensorTelemetryData sharedTelemetry;
extern SemaphoreHandle_t telemetryMutex;

// Command queue to communicate from HTTP task to Core 1
struct CommandEvent {
    String cmd;
    int time;
    volatile bool pending;
};

extern CommandEvent pendingCommand;



inline void scanNetworks() {
    Serial.println("[Wi-Fi] Scanning local networks...");
    int n = WiFi.scanNetworks();
    Serial.printf("[Wi-Fi] Scan done. Found %d networks.\n", n);
    
    scanResultsHtml = "";
    if (n == 0) {
        scanResultsHtml = "<option value=\"\">No networks found</option>";
    } else {
        // Sort networks by signal strength (RSSI)
        int indices[n];
        for (int i = 0; i < n; i++) indices[i] = i;
        for (int i = 0; i < n; i++) {
            for (int j = i + 1; j < n; j++) {
                if (WiFi.RSSI(indices[j]) > WiFi.RSSI(indices[i])) {
                    std::swap(indices[i], indices[j]);
                }
            }
        }
        
        // Remove duplicates and compile HTML options
        String* seenSSIDs = new String[n];
        int uniqueCount = 0;
        for (int i = 0; i < n; i++) {
            String ssid = WiFi.SSID(indices[i]);
            bool duplicate = false;
            for (int j = 0; j < uniqueCount; j++) {
                if (seenSSIDs[j] == ssid) {
                    duplicate = true;
                    break;
                }
            }
            if (!duplicate && ssid.length() > 0) {
                seenSSIDs[uniqueCount++] = ssid;
                int rssi = WiFi.RSSI(indices[i]);
                int quality = 2 * (rssi + 100);
                if (quality < 0) quality = 0;
                if (quality > 100) quality = 100;
                scanResultsHtml += "<option value=\"" + ssid + "\">" + ssid + " (" + String(quality) + "%)</option>\n";
            }
        }
        delete[] seenSSIDs;
    }
}

inline void handleRoot() {
    // If in AP mode, force redirect any request to 192.168.4.1 (captive portal behavior)
    if (isAPMode && server.hostHeader() != "192.168.4.1") {
        server.sendHeader("Location", "http://192.168.4.1/");
        server.send(302, "text/plain", "");
        return;
    }
    
    // Scan networks if dropdown is empty
    if (scanResultsHtml.length() == 0) {
        scanNetworks();
    }
    
    String html = R"rawhtml(
<!DOCTYPE html>
<html>
<head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Rehab Glove Wi-Fi Config</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background-color: #0d0e15; color: #cbd5e1; padding: 20px; display: flex; justify-content: center; }
        .container { max-width: 400px; width: 100%; background: #141722; padding: 24px; border-radius: 12px; border: 1px solid #232a3d; box-shadow: 0 4px 12px rgba(0,0,0,0.5); }
        h2 { color: #8b5cf6; margin-top: 0; font-size: 22px; text-align: center; }
        .form-group { margin-bottom: 16px; }
        label { display: block; margin-bottom: 6px; font-weight: bold; font-size: 14px; }
        select, input { width: 100%; padding: 10px; border-radius: 6px; border: 1px solid #232a3d; background: #0d0e15; color: #cbd5e1; box-sizing: border-box; font-size: 14px; }
        select:focus, input:focus { border-color: #8b5cf6; outline: none; }
        button { width: 100%; padding: 12px; border: none; border-radius: 6px; background: #8b5cf6; color: white; font-weight: bold; cursor: pointer; font-size: 14px; margin-top: 10px; }
        button:hover { background: #7c3aed; }
        .status { margin-bottom: 16px; font-size: 13px; text-align: center; padding: 8px; border-radius: 6px; background: #1e1b4b; color: #a5b4fc; }
    </style>
</head>
<body>
    <div class="container">
        <h2>Rehab Glove Wi-Fi Setup</h2>
)rawhtml";

    if (connectedSSID.length() > 0) {
        html += "<div class=\"status\">Currently Connected to: <strong>" + connectedSSID + "</strong></div>";
    } else {
        html += "<div class=\"status\">Mode: <strong>Access Point Config Portal</strong></div>";
    }

    html += R"rawhtml(
        <form action="/save" method="POST">
            <div class="form-group">
                <label for="ssid">Select Network</label>
                <select id="ssid" name="ssid">
)rawhtml";

    html += scanResultsHtml;

    html += R"rawhtml(
                </select>
            </div>
            <div class="form-group">
                <label for="pass">Password</label>
                <input type="password" id="pass" name="pass" placeholder="Enter network password">
            </div>
            <button type="submit">CONNECT GLOVE</button>
        </form>
        <button style="background: #374151; margin-top: 8px;" onclick="window.location.reload();">SCAN NETWORKS</button>
    </div>
</body>
</html>
)rawhtml";

    server.send(200, "text/html", html);
}

inline void handleSave() {
    String ssid = server.arg("ssid");
    String pass = server.arg("pass");
    
    Serial.printf("[Network] Saving new Wi-Fi credentials: SSID=%s\n", ssid.c_str());
    
    preferences.begin("wifi-config", false);
    preferences.putString("ssid", ssid);
    preferences.putString("pass", pass);
    preferences.end();
    
    String html = R"rawhtml(
<!DOCTYPE html>
<html>
<head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Credentials Saved</title>
    <style>
        body { font-family: -apple-system, sans-serif; background-color: #0d0e15; color: #cbd5e1; text-align: center; padding: 50px 20px; }
        .container { max-width: 400px; margin: 0 auto; background: #141722; padding: 24px; border-radius: 12px; border: 1px solid #232a3d; }
        h2 { color: #10b981; }
        p { color: #94a3b8; font-size: 14px; line-height: 1.5; }
    </style>
</head>
<body>
    <div class="container">
        <h2>Configuration Saved!</h2>
        <p>The Glove is now restarting to connect to: <strong>)rawhtml" + ssid + R"rawhtml(</strong>.</p>
        <p>Please connect your phone/PC back to your local network and wait 10 seconds.</p>
    </div>
</body>
</html>
)rawhtml";

    server.send(200, "text/html", html);
    delay(2000);
    ESP.restart();
}

// Registry is included via glove_espnow.h

inline void handleTelemetry() {
    RegistryLock lock;
    SensorTelemetryData localData;
    if (xSemaphoreTake(telemetryMutex, portMAX_DELAY) == pdTRUE) {
        localData = sharedTelemetry;
        xSemaphoreGive(telemetryMutex);
    }
    
    int timeRemaining = 0;
    if (sessionState.active) {
        if (sessionState.timerEndMillis > millis()) {
            timeRemaining = (sessionState.timerEndMillis - millis()) / 1000;
        }
    } else {
        timeRemaining = localData.time_remaining;
    }

    String exitReasonStr = "aborted";
    if (lastSessionExitReason == STOP_REASON_SUCCESS) exitReasonStr = "success";
    else if (lastSessionExitReason == STOP_REASON_TIMEOUT) exitReasonStr = "timeout";

    String json = "{";
    json += "\"calibrated\":" + String(localData.calibrated ? "true" : "false") + ",";
    json += "\"calibrating\":" + String(localData.calibrating ? "true" : "false") + ",";
    json += "\"time_remaining\":" + String(timeRemaining) + ",";
    json += "\"session_active\":" + String(sessionState.active ? "true" : "false") + ",";
    json += "\"success_count\":" + String(sessionState.successCount) + ",";
    json += "\"failure_count\":" + String(sessionState.failureCount) + ",";
    json += "\"current_cycle\":" + String(sessionState.currentCycle) + ",";
    json += "\"is_holding\":" + String(sessionState.isHolding ? "true" : "false") + ",";
    json += "\"game_type\":" + String(sessionState.active ? currentPrescription.gameType : 0) + ",";
    json += "\"session_completed_success\":" + String(lastSessionCompletedSuccess ? "true" : "false") + ",";
    json += "\"exit_reason\":\"" + exitReasonStr + "\",";
    
    // flex group
    json += "\"flex\":{";
    json += "\"raw\":[";
    for (int i = 0; i < NUM_FINGERS; i++) {
        json += String(localData.flexRaw[i]);
        if (i < NUM_FINGERS - 1) json += ",";
    }
    json += "],\"percent\":[";
    for (int i = 0; i < NUM_FINGERS; i++) {
        json += String(localData.flexPercent[i]);
        if (i < NUM_FINGERS - 1) json += ",";
    }
    json += "]},";
    
    // force group
    json += "\"force\":{";
    json += "\"raw\":[" + String(localData.forceRaw) + "],";
    json += "\"percent\":[" + String(localData.forcePercent) + "]";
    json += "},";
    
    // boxes list
    json += "\"boxes\":[";
    bool first = true;
    for (const auto& pair : boxRegistry) {
        const RegisteredBox& box = pair.second;
        if (!first) json += ",";
        first = false;
        
        json += "{";
        json += "\"mac\":\"";
        for (int j = 0; j < 6; j++) {
            char hex[3];
            sprintf(hex, "%02X", box.mac[j]);
            json += hex;
            if (j < 5) json += ":";
        }
        json += "\",\"cube\":\"";
        if (box.current_cube_len > 0) {
            for (int j = 0; j < box.current_cube_len; j++) {
                char hex[3];
                sprintf(hex, "%02X", box.current_cube_uid[j]);
                json += hex;
            }
        }
        json += "\"}";
    }
    json += "]";
    json += "}";
    
    server.sendHeader("Access-Control-Allow-Origin", "*"); // CORS
    server.send(200, "application/json", json);
}

inline void handleCommand() {
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.sendHeader("Access-Control-Allow-Headers", "content-type");
    server.sendHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    
    if (server.method() == HTTP_OPTIONS) {
        server.send(204);
        return;
    }
    
    String cmd = server.arg("cmd");
    String timeStr = server.arg("time");
    int timeVal = timeStr.toInt();
    
    if (cmd.length() == 0) {
        server.send(400, "text/plain", "Missing cmd parameter");
        return;
    }
    
    Serial.printf("[Command] Received remote command: %s, time=%d\n", cmd.c_str(), timeVal);
    
    if (cmd == "calibrate") {
        Serial.println("[Command] Calibrate command received (bypassed on Glove, direct calibration used).");
        server.send(200, "text/plain", "Calibration bypassed on Glove");
    } else if (cmd == "identifyBox") {
        int targetIdx = timeVal;
        int idx = 0;
        uint8_t targetMac[6] = {0};
        bool found = false;
        for (const auto& pair : boxRegistry) {
            if (idx == targetIdx) {
                memcpy(targetMac, pair.second.mac, 6);
                found = true;
                break;
            }
            idx++;
        }
        if (found) {
            sendIdentifyToBox(targetMac);
            server.send(200, "text/plain", "Identify command sent to box");
        } else {
            server.send(404, "text/plain", "Box index not found");
        }
    } else if (cmd == "ready" || cmd == "green_light") {
        uint8_t broadcastMac[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
        sendLedColorToBox(broadcastMac, 0, 255, 0); // Green light
        server.send(200, "text/plain", "Ready signal sent (green light)");
    } else {
        server.send(400, "text/plain", "Unsupported command");
    }
}

inline void handleNotFound() {
    if (isAPMode) {
        server.sendHeader("Location", "http://192.168.4.1/");
        server.send(302, "text/plain", "");
        return;
    }
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.send(404, "text/plain", "Not Found");
}

inline void handleGetRawSensors() {
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.sendHeader("Access-Control-Allow-Headers", "content-type");
    server.sendHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    
    if (server.method() == HTTP_OPTIONS) {
        server.send(204);
        return;
    }
    
    int flexRaw[NUM_FINGERS];
    int forceRaw = 0;
    
    if (xSemaphoreTake(telemetryMutex, portMAX_DELAY) == pdTRUE) {
        memcpy(flexRaw, sharedTelemetry.flexRaw, sizeof(flexRaw));
        forceRaw = sharedTelemetry.forceRaw;
        xSemaphoreGive(telemetryMutex);
    }
    
    String json = "{\"flexRaw\":[";
    for (int i = 0; i < NUM_FINGERS; i++) {
        json += String(flexRaw[i]);
        if (i < NUM_FINGERS - 1) json += ",";
    }
    json += "],\"forceRaw\":" + String(forceRaw);
    
    json += ",\"flexMin\":[";
    for (int i = 0; i < NUM_FINGERS; i++) {
        json += String(flexMin[i]);
        if (i < NUM_FINGERS - 1) json += ",";
    }
    
    json += "],\"flexMax\":[";
    for (int i = 0; i < NUM_FINGERS; i++) {
        json += String(flexMax[i]);
        if (i < NUM_FINGERS - 1) json += ",";
    }
    json += "]}";

    
    server.send(200, "application/json", json);
}

inline void handleCalibrateSensor() {
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.sendHeader("Access-Control-Allow-Headers", "content-type");
    server.sendHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    
    if (server.method() == HTTP_OPTIONS) {
        server.send(204);
        return;
    }
    
    String sensorType = server.arg("sensorType");
    if (sensorType == "force") {
        int fMin = server.arg("forceMin").toInt();
        int fMax = server.arg("forceMax").toInt();
        
        if (fMin >= 0 && fMax >= 0) {
            forceMin = fMin;
            forceMax = fMax;
            isCalibrated = true;
            
            preferences.begin("calib", false);
            preferences.putInt("fo_min", forceMin);
            preferences.putInt("fo_max", forceMax);
            preferences.putBool("is_cal", isCalibrated);
            preferences.end();
            
            Serial.printf("[Calib] Saved force: Min=%d, Max=%d\n", forceMin, forceMax);
            server.send(200, "text/plain", "Force sensor calibration saved");
            return;
        }
        server.send(400, "text/plain", "Invalid force parameters");
    }
    else if (sensorType == "flex") {
        int fingerIdx = server.arg("fingerIndex").toInt();
        int fMin = server.arg("flexMin").toInt();
        int fMax = server.arg("flexMax").toInt();
        
        if (fingerIdx >= 0 && fingerIdx < NUM_FINGERS && fMin >= 0 && fMax >= 0 && fMin != fMax) {
            flexMin[fingerIdx] = fMin;
            flexMax[fingerIdx] = fMax;
            isCalibrated = true;
            
            preferences.begin("calib", false);
            char keyMin[16], keyMax[16];
            sprintf(keyMin, "fl_min_%d", fingerIdx);
            sprintf(keyMax, "fl_max_%d", fingerIdx);
            preferences.putInt(keyMin, fMin);
            preferences.putInt(keyMax, fMax);
            preferences.putBool("is_cal", isCalibrated);
            preferences.end();
            
            Serial.printf("[Calib] Saved flex finger %d: Min=%d, Max=%d\n", fingerIdx, fMin, fMax);
            server.send(200, "text/plain", "Flex sensor calibration saved");
            return;
        }
        server.send(400, "text/plain", "Invalid flex parameters");
    } else {
        server.send(400, "text/plain", "Unsupported sensor type");
    }
}

inline void handleActivePrescription() {
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.sendHeader("Access-Control-Allow-Headers", "content-type");
    server.sendHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    
    if (server.method() == HTTP_OPTIONS) {
        server.send(204);
        return;
    }
    
    GamePrescription rx;
    rx.gameType = (GameType)server.arg("gameType").toInt();
    rx.timerSeconds = server.arg("timer").toInt();
    rx.totalCycles = server.arg("cycles").toInt();
    rx.difficulty = server.arg("difficulty").toInt();
    
    String cubesParam = server.arg("cubes");
    rx.cubesCount = 0;
    if (cubesParam.length() > 0) {
        int start = 0;
        for (int i = 0; i <= cubesParam.length(); i++) {
            if (i == cubesParam.length() || cubesParam.charAt(i) == ',') {
                String cubeStr = cubesParam.substring(start, i);
                start = i + 1;
                
                int colons[3] = {0};
                int cIdx = 0;
                for (int j = 0; j < cubeStr.length(); j++) {
                    if (cubeStr.charAt(j) == ':') {
                        colons[cIdx++] = j;
                        if (cIdx >= 3) break;
                    }
                }
                
                if (cIdx == 3 && rx.cubesCount < 8) {
                    String uidHex = cubeStr.substring(0, colons[0]);
                    String color = cubeStr.substring(colons[0] + 1, colons[1]);
                    String shape = cubeStr.substring(colons[1] + 1, colons[2]);
                    int weight = cubeStr.substring(colons[2] + 1).toInt();
                    
                    RxCube c;
                    c.uid_len = 0;
                    for (int k = 0; k < uidHex.length() && c.uid_len < MAX_CUBE_UID_LEN; k += 2) {
                        String byteHex = uidHex.substring(k, k+2);
                        c.uid[c.uid_len++] = (uint8_t)strtol(byteHex.c_str(), NULL, 16);
                    }
                    
                    strncpy(c.color, color.c_str(), sizeof(c.color) - 1);
                    strncpy(c.shape, shape.c_str(), sizeof(c.shape) - 1);
                    c.weightGrams = weight;
                    
                    rx.cubes[rx.cubesCount++] = c;
                }
            }
        }
    }
    
    String boxesParam = server.arg("boxes");
    if (boxesParam.length() > 0) {
        RegistryLock lock;
        int start = 0;
        for (int i = 0; i <= boxesParam.length(); i++) {
            if (i == boxesParam.length() || boxesParam.charAt(i) == ',') {
                String boxMapping = boxesParam.substring(start, i);
                start = i + 1;
                
                int colonIdx = boxMapping.indexOf(':');
                if (colonIdx != -1) {
                    String macStr = boxMapping.substring(0, colonIdx);
                    String shapeStr = boxMapping.substring(colonIdx + 1);
                    
                    uint8_t macBytes[6] = {0};
                    for (int k = 0; k < 6 && k * 2 + 2 <= macStr.length(); k++) {
                        String byteHex = macStr.substring(k * 2, k * 2 + 2);
                        macBytes[k] = (uint8_t)strtol(byteHex.c_str(), NULL, 16);
                    }
                    uint64_t key = 0;
                    for (int k = 0; k < 6; k++) {
                        key = (key << 8) | macBytes[k];
                    }
                    
                    auto it = boxRegistry.find(key);
                    if (it != boxRegistry.end()) {
                        strncpy(it->second.shape, shapeStr.c_str(), sizeof(it->second.shape) - 1);
                        it->second.shape[sizeof(it->second.shape) - 1] = '\0';
                        Serial.printf("[Game] Configured Box %s with shape: %s\n", macStr.c_str(), shapeStr.c_str());
                    } else {
                        RegisteredBox newBox;
                        memcpy(newBox.mac, macBytes, 6);
                        newBox.active = false;
                        newBox.current_cube_len = 0;
                        memset(newBox.current_cube_uid, 0, MAX_CUBE_UID_LEN);
                        newBox.last_seen = millis();
                        strncpy(newBox.shape, shapeStr.c_str(), sizeof(newBox.shape) - 1);
                        newBox.shape[sizeof(newBox.shape) - 1] = '\0';
                        boxRegistry[key] = newBox;
                        Serial.printf("[Game] Pre-registered Box %s with shape: %s\n", macStr.c_str(), shapeStr.c_str());
                    }
                }
            }
        }
    }

    rx.requiredHoldTimeSeconds = server.arg("holdTime").toInt();
    
    String fingersStr = server.arg("activeFingers");
    if (fingersStr.length() > 0) {
        int idx = 0;
        for (int i = 0; i < fingersStr.length() && idx < NUM_FINGERS; i++) {
            if (fingersStr.charAt(i) == '1') rx.activeFingers[idx++] = 1;
            else if (fingersStr.charAt(i) == '0') rx.activeFingers[idx++] = 0;
        }
    }
    
    String romStr = server.arg("requiredRom");
    if (romStr.length() > 0) {
        int idx = 0;
        int start = 0;
        for (int i = 0; i <= romStr.length() && idx < NUM_FINGERS; i++) {
            if (i == romStr.length() || romStr.charAt(i) == ',') {
                rx.requiredRom[idx++] = romStr.substring(start, i).toInt();
                start = i + 1;
            }
        }
    }
    
    String seqStr = server.arg("sequence");
    rx.sequenceCount = 0;
    if (seqStr.length() > 0) {
        int start = 0;
        for (int i = 0; i <= seqStr.length() && rx.sequenceCount < NUM_FINGERS; i++) {
            if (i == seqStr.length() || seqStr.charAt(i) == ',') {
                rx.sequence[rx.sequenceCount++] = seqStr.substring(start, i).toInt();
                start = i + 1;
            }
        }
    }
    
    // Auto-populate sequence if omitted for BEND game
    if (rx.gameType == GAME_BEND && rx.sequenceCount == 0) {
        for (int i = 0; i < NUM_FINGERS; i++) {
            if (rx.activeFingers[i] == 1) {
                rx.sequence[rx.sequenceCount++] = i + 1;
            }
        }
        if (rx.sequenceCount == 0) {
            for (int i = 0; i < NUM_FINGERS; i++) {
                rx.sequence[rx.sequenceCount++] = i + 1;
            }
        }
    }
    
    if (rx.gameType == GAME_NONE) {
        if (sessionState.active) {
            stopGameSession(STOP_REASON_ABORTED);
        }
        server.send(200, "text/plain", "Game stopped");
        return;
    }

    currentPrescription = rx;
    savePrescriptionToNVS(rx); // Persist received prescription!
    Serial.printf("[Rx] Received prescription: type=%d, cycles=%d, timer=%d, diff=%d, holdTime=%d\n",
                  rx.gameType, rx.totalCycles, rx.timerSeconds, rx.difficulty, rx.requiredHoldTimeSeconds);
    
    String patientId = server.arg("patientId");
    if (patientId.length() > 0) {
        preferences.begin("calibration", false);
        preferences.putString("activePatientId", patientId);
        preferences.end();
    }

    // Parse patient calibration values if provided
    String flexMinStr = server.arg("flexMin");
    String flexMaxStr = server.arg("flexMax");
    String forceMinStr = server.arg("forceMin");
    String forceMaxStr = server.arg("forceMax");
    
    if (flexMinStr.length() > 0 && flexMaxStr.length() > 0 && forceMinStr.length() > 0 && forceMaxStr.length() > 0) {
        int idx = 0;
        int startMin = 0;
        int startMax = 0;
        for (int i = 0; i <= flexMinStr.length() && idx < NUM_FINGERS; i++) {
            if (i == flexMinStr.length() || flexMinStr.charAt(i) == ',') {
                flexMin[idx++] = flexMinStr.substring(startMin, i).toInt();
                startMin = i + 1;
            }
        }
        idx = 0;
        for (int i = 0; i <= flexMaxStr.length() && idx < NUM_FINGERS; i++) {
            if (i == flexMaxStr.length() || flexMaxStr.charAt(i) == ',') {
                flexMax[idx++] = flexMaxStr.substring(startMax, i).toInt();
                startMax = i + 1;
            }
        }
        forceMin = forceMinStr.toInt();
        forceMax = forceMaxStr.toInt();
        isCalibrated = true;
        
        preferences.begin("calib", false);
        for (int i = 0; i < NUM_FINGERS; i++) {
            char keyMin[16], keyMax[16];
            sprintf(keyMin, "fl_min_%d", i);
            sprintf(keyMax, "fl_max_%d", i);
            preferences.putInt(keyMin, flexMin[i]);
            preferences.putInt(keyMax, flexMax[i]);
        }
        preferences.putInt("fo_min", forceMin);
        preferences.putInt("fo_max", forceMax);
        preferences.putBool("is_cal", isCalibrated);
        preferences.end();
        
        Serial.printf("[Rx] Updated runtime patient calibration. Force bounds: %d -> %d\n", forceMin, forceMax);
    }

    startNewGameSession();
    
    server.send(200, "text/plain", "Prescription received and game session started");
}


inline void handleClearWifi() {
    preferences.begin("wifi-config", false);
    preferences.clear();
    preferences.end();
    server.send(200, "text/html", "<html><head><meta http-equiv='refresh' content='3;url=/'></head><body><h2>Saved Wi-Fi credentials cleared!</h2><p>Restarting Glove into config mode in 3 seconds...</p></body></html>");
    delay(1000);
    ESP.restart();
}

inline void setupNetwork() {
    preferences.begin("wifi-config", false);
    String ssid = preferences.getString("ssid", "");
    String pass = preferences.getString("pass", "");
    preferences.end();
    
    Serial.println("[Network] Booting network stack...");
    
    bool connected = false;
    String defaultSsid = String(WIFI_SSID);
    bool forceOffline = (defaultSsid == "FORCE_OFFLINE");

    if (forceOffline) {
        Serial.println("[Network] 'FORCE_OFFLINE' specified in glove_secrets.h. Skipping Wi-Fi connection attempts.");
    }
    
    // 1. Attempt connection using saved credentials if they exist
    if (!forceOffline && ssid.length() > 0) {
        Serial.printf("[Network] Attempting connection to saved Wi-Fi: %s\n", ssid.c_str());
        WiFi.mode(WIFI_STA);
        WiFi.begin(ssid.c_str(), pass.c_str());
        
        int retries = 0;
        while (WiFi.status() != WL_CONNECTED && retries < 20) { // 10 seconds timeout
            delay(500);
            Serial.print(".");
            retries++;
        }
        Serial.println();
        
        if (WiFi.status() == WL_CONNECTED) {
            connected = true;
            connectedSSID = ssid;
        } else {
            Serial.println("[Network] Failed to connect to saved Wi-Fi.");
            WiFi.disconnect();
        }
    }
    
    // 2. If saved credentials failed, try default credentials as fallback
    if (!connected && !forceOffline) {
        String defaultPass = String(WIFI_PASSWORD);
        
        if (defaultSsid.length() > 0 && defaultSsid != "YOUR_WIFI_SSID") {
            Serial.printf("[Network] Attempting connection to default Wi-Fi: %s\n", defaultSsid.c_str());
            WiFi.mode(WIFI_STA);
            WiFi.begin(defaultSsid.c_str(), defaultPass.c_str());
            
            int retries = 0;
            while (WiFi.status() != WL_CONNECTED && retries < 20) {
                delay(500);
                Serial.print(".");
                retries++;
            }
            Serial.println();
            
            if (WiFi.status() == WL_CONNECTED) {
                connected = true;
                connectedSSID = defaultSsid;
            } else {
                Serial.println("[Network] Failed to connect to default Wi-Fi.");
                WiFi.disconnect();
            }
        }
    }
    
    // 3. Fallback to Access Point Mode (AP) & Config Portal
    if (!connected) {
        Serial.println("[Network] Starting Access Point mode...");
        isAPMode = true;
        
        // Scan networks for config portal selection
        scanNetworks();
        
        WiFi.mode(WIFI_AP);
        WiFi.softAP("Rehab-Glove-Config", "", 1); // Lock softAP to channel 1
        esp_wifi_set_channel(1, WIFI_SECOND_CHAN_NONE); // Force physical radio to channel 1
        
        IPAddress apIP(192, 168, 4, 1);
        dnsServer.start(53, "*", apIP); // DNS Captive Portal redirection
        Serial.println("[Network] Config Portal running on AP: 'Rehab-Glove-Config' at http://192.168.4.1");
    } else {
        Serial.println("[Network] Wi-Fi connected successfully!");
        localIP = WiFi.localIP();
        Serial.print("[Network] IP Address: ");
        Serial.println(localIP);
        Serial.printf("[Network] Operating Channel: %d\n", WiFi.channel());
        
        // Initialize NTP sync on bootup here!
        configTime(0, 0, "pool.ntp.org", "time.nist.gov");
        Serial.println("[NTP] Initializing background NTP sync on Wi-Fi connection...");
        ntpInitialized = true;
    }

    if (isAPMode) {
        WiFi.softAPConfig(IPAddress(192, 168, 4, 1), IPAddress(192, 168, 4, 1), IPAddress(255, 255, 255, 0));
    }
}

inline void setupWebServer() {
    if (isAPMode) {
        server.on("/save", HTTP_POST, handleSave);
    } else {
        if (MDNS.begin("rehab-glove")) {
            Serial.println("[Network] mDNS responder started: http://rehab-glove.local");
            MDNS.addService("http", "tcp", 80);
        }
        Serial.println("[Network] HTTP Telemetry server running on port 80.");
    }

    // Register all routes globally for easy switching and Web access
    server.on("/", handleRoot);
    server.on("/save", HTTP_POST, handleSave);
    server.on("/clear-wifi", HTTP_GET, handleClearWifi);
    server.on("/forget-wifi", HTTP_GET, handleClearWifi);
    server.on("/api/telemetry", HTTP_GET, handleTelemetry);
    server.on("/api/command", handleCommand);
    server.on("/api/active-prescription", handleActivePrescription);
    server.on("/api/raw-sensors", handleGetRawSensors);
    server.on("/api/calibrate-sensor", handleCalibrateSensor);
    server.onNotFound(handleNotFound);

    server.begin();
}

inline void handleNetworkRequests() {
    if (isAPMode) {
        dnsServer.processNextRequest();
    } else {
        // Periodic Wi-Fi connection check (if in STA mode)
        static unsigned long lastWifiCheck = 0;
        static unsigned long disconnectStartTime = 0;
        if (millis() - lastWifiCheck >= 1000) {
            lastWifiCheck = millis();
            if (WiFi.status() != WL_CONNECTED) {
                if (disconnectStartTime == 0) {
                    disconnectStartTime = millis();
                    Serial.println("[Network] Wi-Fi disconnected. Waiting to see if it reconnects...");
                } else if (millis() - disconnectStartTime > 15000) { // 15 seconds timeout
                    Serial.println("[Network] Wi-Fi lost for 15s. Falling back to AP mode...");
                    
                    // Switch to AP mode
                    WiFi.disconnect();
                    WiFi.mode(WIFI_AP);
                    WiFi.softAP("Rehab-Glove-Config");
                    
                    IPAddress apIP(192, 168, 4, 1);
                    dnsServer.start(53, "*", apIP);
                    
                    isAPMode = true;
                    connectedSSID = "";
                    scanNetworks();
                }
            } else {
                disconnectStartTime = 0; // Reset timer if reconnected
            }
        }
    }
    server.handleClient();
}

#endif // GLOVE_WEB_SERVER_H
