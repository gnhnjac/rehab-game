#include <Wire.h>
#include <Adafruit_PN532.h>

// Define I2C pins for ESP32
#define SDA_PIN 21
#define SCL_PIN 22

Adafruit_PN532 nfc(SDA_PIN, SCL_PIN);

void setup(void) {
  Serial.begin(115200);
  Serial.println("Looking for PN532...");

  nfc.begin();

  uint32_t versiondata = nfc.getFirmwareVersion();
  if (!versiondata) {
    Serial.print("Didn't find PN532 board. Check your wiring!");
    while (1); // Halt
  }
  
  // Found the board! Print chip details
  Serial.print("Found chip PN532 "); 
  Serial.println((versiondata >> 24) & 0xFF, HEX); 
  Serial.print("Firmware ver. "); 
  Serial.print((versiondata >> 16) & 0xFF, DEC); 
  Serial.print('.'); Serial.println((versiondata >> 8) & 0xFF, DEC);
  
  // Configure the board to read RFID tags
  nfc.SAMConfig();
  
  Serial.println("Waiting for an NFC/RFID card...");
}

void loop(void) {
  uint8_t success;
  uint8_t uid[] = { 0, 0, 0, 0, 0, 0, 0 };  // Buffer to store the returned UID
  uint8_t uidLength;                        // Length of the UID (4 or 7 bytes)

  // Wait for an ISO14443A type card (Mifare, etc.)
  success = nfc.readPassiveTargetID(PN532_MIFARE_ISO14443A, uid, &uidLength);

  if (success) {
    Serial.println("Found a card!");
    Serial.print("UID Length: ");Serial.print(uidLength, DEC);Serial.println(" bytes");
    Serial.print("UID Value: ");
    
    // Print the UID in Hex format
    for (uint8_t i=0; i < uidLength; i++) {
      Serial.print(" 0x");Serial.print(uid[i], HEX);
    }
    Serial.println("");
    
    delay(1000); // 1 second delay to avoid printing the same tag multiple times instantly
  }
}
