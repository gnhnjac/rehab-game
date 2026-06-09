const unsigned int FORCE_PIN = 32;

void setup() {
  // Configure force pin
  Serial.begin(115200);
  pinMode(FORCE_PIN, INPUT);
  

}

void loop() {
  // put your main code here, to run repeatedly:
  Serial.print("Analog force reading: ");
  Serial.print(analogRead(FORCE_PIN));
  Serial.println();
}
