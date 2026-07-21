#pragma once
#include <Arduino.h>
#include <esp_now.h>
#include "../parameters.h"

// References to the Main Box MAC address tracked in glove.ino / glove_espnow.h
extern uint8_t mainBoxMac[6];
extern bool mainBoxRegistered;
extern bool isAPMode;

inline void setupAudio() {
    // Glove does not have local serial connection for audio.
    // Audio commands are routed wirelessly via ESP-NOW to the Main Box.
    Serial.println("[Audio] Wireless audio routing initialized.");
}

inline void sendDfPlayerCmd(uint8_t cmd, uint8_t high_arg, uint8_t low_arg) {
    if (!mainBoxRegistered) {
        Serial.println("[Audio] Warning: Main Box not registered yet. Drop audio command.");
        return;
    }
    
    AppMessage msg;
    msg.type = MSG_TYPE_COMMAND;
    msg.event = BOX_CMD_PLAY_AUDIO;
    msg.uid_len = 3;
    msg.uid[0] = high_arg; // Folder index / parameter high
    msg.uid[1] = low_arg;  // Track index / parameter low
    msg.uid[2] = cmd;      // DFPlayer command (e.g. 0x0F for folder, 0x06 for volume)
    
    // Ensure Main Box is in the peer list
    if (!esp_now_is_peer_exist(mainBoxMac)) {
        esp_now_peer_info_t peerInfo;
        memset(&peerInfo, 0, sizeof(peerInfo));
        memcpy(peerInfo.peer_addr, mainBoxMac, 6);
        peerInfo.channel = 0;
        peerInfo.encrypt = false;
        peerInfo.ifidx = isAPMode ? WIFI_IF_AP : WIFI_IF_STA;
        esp_now_add_peer(&peerInfo);
    }
    
    esp_now_send(mainBoxMac, (uint8_t *)&msg, sizeof(msg));
}

// Audio Queue Data Structure & Methods to prevent audio files from interrupting each other
struct AudioQueueItem {
    uint8_t folder;
    uint8_t track;
    uint16_t durationMs;
};

#define AUDIO_QUEUE_CAPACITY 16
static AudioQueueItem audioQueue[AUDIO_QUEUE_CAPACITY];
static int audioQueueHead = 0;
static int audioQueueTail = 0;
static unsigned long currentAudioEndTime = 0;
static bool isAudioPlaying = false;

inline uint16_t getTrackDurationMs(uint8_t folder, uint8_t track) {
    if (folder == 4) {
        if (track == 3) return 400; // Short countdown beep
        if (track == 1 || track == 2 || track == 14 || track == 15) return 800; // Success/fail chimes
        if (track == 6 || track == 12) return 1500; // Warnings / connect chime
        if (track == 7) return 2000; // Hold prompt
        return 2500; // Verbal prompts (8, 4, 5, 16, 17, 18)
    }
    // Folders 1, 2, 3 are long verbal intro / instruction prompts
    return 3500;
}

inline void queueAudioTrack(uint8_t folder, uint8_t track) {
    int nextTail = (audioQueueTail + 1) % AUDIO_QUEUE_CAPACITY;
    if (nextTail == audioQueueHead) {
        Serial.println("[AudioQueue] Warning: Queue full! Overwriting oldest pending audio.");
        audioQueueHead = (audioQueueHead + 1) % AUDIO_QUEUE_CAPACITY;
    }
    audioQueue[audioQueueTail].folder = folder;
    audioQueue[audioQueueTail].track = track;
    audioQueue[audioQueueTail].durationMs = getTrackDurationMs(folder, track);
    audioQueueTail = nextTail;
}

inline void clearAudioQueue() {
    audioQueueHead = 0;
    audioQueueTail = 0;
    isAudioPlaying = false;
    currentAudioEndTime = 0;
}

inline void updateAudioQueue() {
    unsigned long now = millis();

    // Wait if current track is still playing
    if (isAudioPlaying) {
        if (now < currentAudioEndTime) {
            return;
        }
        isAudioPlaying = false;
    }

    // Process next item in queue
    if (audioQueueHead != audioQueueTail) {
        AudioQueueItem item = audioQueue[audioQueueHead];
        audioQueueHead = (audioQueueHead + 1) % AUDIO_QUEUE_CAPACITY;

        sendDfPlayerCmd(0x0F, item.folder, item.track);
        isAudioPlaying = true;
        currentAudioEndTime = now + item.durationMs;
        Serial.printf("[AudioQueue] Playing queued track: Folder %d, Track %d (%dms)\n", 
                      item.folder, item.track, item.durationMs);
    }
}

// Set volume between 0 and 30
inline void setVolume(uint8_t vol) {
    if (vol > 30) vol = 30;
    sendDfPlayerCmd(0x06, 0x00, vol);
}

// Play track F_xx.mp3 in folder F (1-99) via queue
inline void playTrack(uint8_t folder, uint8_t track) {
    queueAudioTrack(folder, track);
}

// Feedback and countdown sound wrappers
inline void playSuccessSound() {
    playTrack(4, 1);
}

inline void playFailureSound() {
    playTrack(4, 2);
}

inline void playCountdownBeep() {
    playTrack(4, 3);
}

inline void playCompletionSound() {
    playTrack(4, 4);
}

inline void playCubesBoxesSuccess() {
    playSuccessSound();
}

inline void playPinchSuccess() {
    playTrack(4, 14);
}

inline void playBendSuccess() {
    playTrack(4, 15);
}

inline void playCubesBoxesCompletion() {
    playTrack(4, 16);
}

inline void playPinchCompletion() {
    playTrack(4, 17);
}

inline void playBendCompletion() {
    playTrack(4, 18);
}

inline void playTimeoutSound() {
    playTrack(4, 5);
}

inline void playForceWarning() {
    playTrack(4, 6);
}

inline void playHoldPrompt() {
    playTrack(4, 7);
}

inline void playReleasePrompt() {
    playTrack(4, 8);
}

inline void playStartPrompt(int gameType, int level) {
    if (gameType == 1) { // Cubes & Boxes
        if (level == 1) playTrack(1, 2);
        else if (level == 2) playTrack(1, 3);
        else if (level == 3) playTrack(1, 4);
        else playTrack(1, 1);
    }
    else if (gameType == 2) { // Pinch
        playTrack(2, 1);
    }
    else if (gameType == 3) { // Bend
        playTrack(3, 1);
    }
}
