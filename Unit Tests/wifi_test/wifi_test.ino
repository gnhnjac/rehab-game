/*
  ESP32 MAC Address printout
  wifi_test.ino
  Prints MAC Address to Serial Monitor
 
  DroneBot Workshop 2022
  https://dronebotworkshop.com
*/
 
// Include WiFi Library
#include "WiFi.h"
#include "soc/rtc_cntl_reg.h"
 
void setup() {
  WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0);
  // Setup Serial Monitor
  Serial.begin(115200);
  
  Serial.print("Connecting to wifi:");
  // Put ESP32 into Station mode
  WiFi.mode(WIFI_MODE_STA);
 
  // Print MAC Address to Serial monitor
  Serial.print("MAC Address: ");
  Serial.println(WiFi.macAddress());
}
 
void loop() {
 
}
