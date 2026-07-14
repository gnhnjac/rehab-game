import os
import sys
import wave
import math
import struct

# Auto-install gTTS if not present
try:
    from gtts import gTTS
except ImportError:
    print("[TTS] gTTS library not found. Installing via pip...")
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "gTTS"])
    from gtts import gTTS

def generate_beep_wav(filepath, duration_ms, frequency, volume=0.5):
    """Generates a pure sine wave beep in WAV format."""
    sample_rate = 44100
    num_samples = int(sample_rate * (duration_ms / 1000.0))
    
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    with wave.open(filepath, 'wb') as wav_file:
        wav_file.setnchannels(1)  # Mono
        wav_file.setsampwidth(2) # 16-bit
        wav_file.setframerate(sample_rate)
        
        for i in range(num_samples):
            # Sine wave formula
            t = float(i) / sample_rate
            value = int(32767.0 * volume * math.sin(2.0 * math.pi * frequency * t))
            data = struct.pack('<h', value)
            wav_file.writeframes(data)
            
    print(f"Generated Alert Beep: {filepath} ({frequency}Hz, {duration_ms}ms)")

def generate_hebrew_tts(filepath, text):
    """Synthesizes Hebrew text to an MP3 file using Google Text-to-Speech (gTTS)."""
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    
    # Synthesize with Hebrew ('iw') locale
    tts = gTTS(text=text, lang='iw', slow=False)
    tts.save(filepath)
    print(f"Generated Hebrew Voice Prompt: {filepath}")


def main():
    output_dir = r"c:\Users\gnhnj\Programming\rehab-game\Documentation\audio_assets"
    print(f"Starting audio assets generation in: {output_dir}\n")

    # Define the SD card folder structure and prompts
    # Folder 01: Cubes & Boxes
    folder_01 = {
        "001.mp3": "מתחילים בתרגיל קוביות וקופסאות.",
        "002.mp3": "רמה אחת. צבע קבוע. אנא העבר קוביות בצבע המבוקש לקופסה המוארת.",
        "003.mp3": "רמה שתיים. צבעים ומשקלים משתנים. העבר את הקוביות לפי ההנחיות.",
        "004.mp3": "רמה שלוש. התאמת צורה וצבע. התאם את צורת הקובייה לחור בקופסה.",
        "005.mp3": "התאם והכנס קובייה משולשת אדומה.",
        "006.mp3": "התאם והכנס קובייה עגולה כחולה.",
        "007.mp3": "התאם והכנס קובייה מרובעת ירוקה."
    }

    # Folder 02: Pinch Grip
    folder_02 = {
        "001.mp3": "מתחילים בתרגיל כוח אחיזה.",
        "002.mp3": "אנא הרם את הקובייה בעזרת האגודל והאצבע המבוקשת.",
        "003.mp3": "הורמת קובייה לא נכונה. אנא הרם את הקובייה הנכונה.",
        "004.mp3": "שים לב שאתה משתמש באצבע המורה במקום באמה."
    }

    # Folder 03: Range of Motion (Bend)
    folder_03 = {
        "001.mp3": "מתחילים בתרגיל טווחי תנועה.",
        "002.mp3": "כופף את האצבע והחזק אותה מכופפת."
    }

    # Folder 04: General/Feedback prompts and alarms
    folder_04_verbal = {
        "004.mp3": "כל הכבוד, סיימת את התרגיל בהצלחה!",
        "005.mp3": "תם הזמן!",
        "006.mp3": "לחץ חזק יותר.",
        "007.mp3": "החזק.",
        "008.mp3": "שחרר את האצבע."
    }

    # Generate Folder 01 prompts
    for filename, text in folder_01.items():
        path = os.path.join(output_dir, "01", filename)
        generate_hebrew_tts(path, text)

    # Generate Folder 02 prompts
    for filename, text in folder_02.items():
        path = os.path.join(output_dir, "02", filename)
        generate_hebrew_tts(path, text)

    # Generate Folder 03 prompts
    for filename, text in folder_03.items():
        path = os.path.join(output_dir, "03", filename)
        generate_hebrew_tts(path, text)

    # Generate Folder 04 prompts (verbal)
    for filename, text in folder_04_verbal.items():
        path = os.path.join(output_dir, "04", filename)
        generate_hebrew_tts(path, text)

    # Generate Folder 04 Alert Beeps (WAV format)
    # 001.wav -> Success chime (Dual-frequency pleasant chord)
    # DFPlayer Mini supports both MP3 and WAV, so we save alerts as WAV
    generate_beep_wav(os.path.join(output_dir, "04", "001.wav"), duration_ms=400, frequency=1200, volume=0.4)
    # 002.wav -> Error alarm (Low frequency buzzer beep)
    generate_beep_wav(os.path.join(output_dir, "04", "002.wav"), duration_ms=300, frequency=220, volume=0.6)
    # 003.wav -> Countdown/Tick sound (Short high-pitch tick)
    generate_beep_wav(os.path.join(output_dir, "04", "003.wav"), duration_ms=50, frequency=1000, volume=0.3)

    print("\n" + "=" * 60)
    print(" AUDIO ASSETS GENERATION COMPLETE")
    print("=" * 60)
    print(f"All files saved in: {output_dir}")
    print("Copy the folders '01', '02', '03', and '04' directly to the root of the micro SD card.")
    print("=" * 60)

if __name__ == "__main__":
    main()
