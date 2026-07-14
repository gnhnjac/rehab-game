import numpy as np

def fit_calibration_curve(datapoints, degree=3):
    """
    Fits a polynomial of specified degree to FSR ADC vs Grams data.
    datapoints: list of tuples (raw_adc, grams)
    degree: polynomial degree (e.g., 2 or 3)
    """
    adcs = np.array([pt[0] for pt in datapoints], dtype=float)
    grams = np.array([pt[1] for pt in datapoints], dtype=float)
    
    # Fit polynomial: G = c[0]*X^d + c[1]*X^(d-1) + ... + c[d]
    coeffs = np.polyfit(adcs, grams, degree)
    
    print("=" * 60)
    print(" FSR CALIBRATION FITTER RESULTS")
    print("=" * 60)
    print(f"Data points fitted: {len(datapoints)}")
    for adc, g in datapoints:
        print(f"  ADC: {adc:4d} -> Actual Weight: {g:4.1f}g")
        
    print("\nFitted Coefficients (highest degree first):")
    for i, c in enumerate(coeffs):
        print(f"  c{degree-i}: {c:.8e}")
        
    # Generate C++ evaluation snippet using Horner's Method
    # Horner's method evaluates a0 + x*(a1 + x*(a2 + ...)) which saves CPU multiplications
    print("\n" + "-" * 60)
    print("COPY & PASTE THIS C++ FUNCTION INTO glove_game.h:")
    print("-" * 60)
    
    cpp_code = "inline float getFsrForceGrams(int raw) {\n"
    cpp_code += "    float x = (float)raw;\n"
    
    # Construct Horner's method formula:
    # Example for degree 3: (((c0 * x + c1) * x + c2) * x + c3)
    expr = f"{coeffs[0]:.8e}"
    for i in range(1, degree + 1):
        expr = f"({expr} * x + {coeffs[i]:.8e})"
        
    cpp_code += f"    float grams = {expr};\n"
    cpp_code += "    return grams < 0.0f ? 0.0f : grams; // Clamp negative values\n"
    cpp_code += "}"
    
    print(cpp_code)
    print("-" * 60)
    
    # Show fitting errors
    predictions = np.polyval(coeffs, adcs)
    errors = predictions - grams
    mae = np.mean(np.abs(errors))
    max_error = np.max(np.abs(errors))
    print(f"Mean Absolute Error (MAE): {mae:.2f} grams")
    print(f"Max Absolute Error: {max_error:.2f} grams")
    print("=" * 60)

if __name__ == "__main__":
    # Example calibration data: (raw_adc, actual_grams)
    # REPLACE WITH YOUR ACTUAL CALIBRATION DATAPOINTS
    sample_data = [
        (4095, 0),    # FSR idle (pull-up configuration)
        (3500, 20),
        (2500, 100),
        (1500, 250),
        (500, 500)
    ]
    
    fit_calibration_curve(sample_data, degree=3)
