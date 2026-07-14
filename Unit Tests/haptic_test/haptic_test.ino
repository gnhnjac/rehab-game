#include <Wire.h>
#include <Adafruit_DRV2605.h>

Adafruit_DRV2605 drv;

const uint8_t vibrationEffects[] = {1, 5, 12, 58, 14, 15};
const int totalEffects = sizeof(vibrationEffects) / sizeof(vibrationEffects[0]);

void setup(void) {
  Serial.begin(115200);
  Serial.println("--- Test: NFC + Haptic Only ---");

  if (drv.begin()) {
    drv.selectLibrary(1);             
    drv.setMode(DRV2605_MODE_INTTRIG); 
    Serial.println("Haptic Ready.");
  } else {
    Serial.println("Warning: Didn't find DRV2605.");
  }

}

void loop(void) {
                     
  int randomIndex = random(0, totalEffects);
  drv.setWaveform(0, vibrationEffects[randomIndex]);  
  drv.setWaveform(1, 0);       
  drv.go();                    
  
  delay(1500); 
  
}