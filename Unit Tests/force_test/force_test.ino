// FSR Force Calibration Unit Test with Running Average Filter
const unsigned int FORCE_PIN = 36; // Labeled VP on the DOIT ESP32 board (aligned with parameters.h)

const int WINDOW_SIZE = 20; // Size of the moving average window
int samples[WINDOW_SIZE];
int sampleIdx = 0;
long sampleSum = 0;

// Convert raw FSR ADC value to grams using fitted polynomial regression (Horner's Method)
float getFsrForceGrams(float x) {
    // Fitted 3rd degree polynomial coefficients: c3=-3.98314766e-09, c2=6.66920065e-05, c1=-3.69648297e-01, c0=6.68495729e+02
    float grams = (((-3.98314766e-09 * x + 6.66920065e-05) * x + -3.69648297e-01) * x + 6.68495729e+02);
    return grams < 0.0f ? 0.0f : grams; // Clamp negative values
}

void setup() {
  Serial.begin(115200);
  delay(1000);
  Serial.println("\n--- [FSR Force Unit Test & Calibration] ---");
  Serial.println("Place known weights on the FSR sensor to collect calibration coordinates (smoothed raw ADC, actual weight).");
  Serial.println("Feed these coordinates to the fsr_calibration_fitter.py Python script to adjust coefficients.");
  Serial.println("-----------------------------------------------------------------------------------------------------");

  pinMode(FORCE_PIN, INPUT);

  // Initialize moving average buffer with first reading to avoid initial ramp-up delay
  int initialRead = analogRead(FORCE_PIN);
  for (int i = 0; i < WINDOW_SIZE; i++) {
      samples[i] = initialRead;
  }
  sampleSum = (long)initialRead * WINDOW_SIZE;
}

void loop() {
  // Read FSR ADC value
  int rawRead = analogRead(FORCE_PIN);

  // Update moving average (running average) buffer
  sampleSum -= samples[sampleIdx];
  samples[sampleIdx] = rawRead;
  sampleSum += rawRead;
  sampleIdx = (sampleIdx + 1) % WINDOW_SIZE;

  float smoothedRaw = (float)sampleSum / WINDOW_SIZE;
  float calculatedGrams = getFsrForceGrams(smoothedRaw);

  // Print raw values, smoothed values, and calculated weight
  Serial.printf("Raw ADC: %4d | Smoothed ADC: %6.1f | Calculated Weight: %5.1fg\n", 
                rawRead, smoothedRaw, calculatedGrams);

  delay(100); // Sample & print every 100ms
}
