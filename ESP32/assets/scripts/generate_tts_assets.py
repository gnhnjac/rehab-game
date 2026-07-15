import os
import sys

# Auto-install gTTS if not present
try:
    from gtts import gTTS
except ImportError:
    print("[TTS] gTTS library not found. Installing via pip...")
    import subprocess
    try:
        subprocess.check_call([sys.executable, "-m", "pip", "install", "gTTS"])
    except Exception:
        print("[TTS] sys.executable pip failed. Trying system-wide pip...")
        subprocess.check_call(["pip", "install", "gTTS"])
    from gtts import gTTS

def generate_hebrew_tts(filepath, text):
    """Synthesizes Hebrew text to an MP3 file using Google Text-to-Speech (gTTS)."""
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    
    # Synthesize with Hebrew ('iw') locale
    tts = gTTS(text=text, lang='iw', slow=False)
    tts.save(filepath)
    print(f"Generated Hebrew Voice Prompt: {filepath}")

def main():
    # Resolve output directory relative to script path
    script_dir = os.path.dirname(os.path.abspath(__file__))
    output_dir = os.path.abspath(os.path.join(script_dir, "..", "audio_assets"))
    
    print(f"Starting audio assets generation in: {output_dir}\n")

    # Folder 01: Cubes & Boxes
    folder_01 = {
        "001.mp3": "מתחילים בתרגיל קוביות וקופסאות.",
        "002.mp3": "רמה אחת. צבע קבוע. אנא העבר קוביות בצבע המבוקש לקופסה המוארת.",
        "003.mp3": "רמה שתיים. צבעים משתנים. אנא העבר קוביות בצבע המבוקש לקופסה המוארת.",
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
        "004.mp3": "שים לב שאתה משתמש באצבע המורה במקום באמה.",
        "005.mp3": "אנא הנח את המשקל המתאים בקופסה.",
        "006.mp3": "הרם והחזק באוויר למשך חמש שניות.",
        "007.mp3": "הרם והחזק באוויר למשך עשר שניות.",
        "008.mp3": "הרם והחזק באוויר למשך חמש עשרה שניות.",
        "009.mp3": "הרם והחזק באוויר למשך עשרים שניות.",
        "010.mp3": "הרם והחזק באוויר למשך עשרים וחמש שניות.",
        "011.mp3": "הרם והחזק באוויר למשך שלושים שניות."
    }

    # Folder 03: Range of Motion (Bend)
    folder_03 = {
        "001.mp3": "מתחילים בתרגיל טווחי תנועה.",
        "002.mp3": "כופף את האצבע והחזק אותה מכופפת."
    }

    # Folder 04: General/Feedback prompts and alarms (Only MP3, no WAVs)
    folder_04 = {
        "001.mp3": "הצלחה!",
        "002.mp3": "שגיאה!",
        "003.mp3": "טיק.",
        "004.mp3": "כל הכבוד, סיימת את התרגיל בהצלחה!",
        "005.mp3": "תם הזמן!",
        "006.mp3": "לחץ חזק יותר.",
        "007.mp3": "החזק.",
        "008.mp3": "שחרר את האצבע.",
        "009.mp3": "עשר שניות.",
        "010.mp3": "חמש שניות.",
        "011.mp3": "ג'ינגל רקע למשחק.",
        "012.mp3": "התחבר בהצלחה.",
        "013.mp3": "כל הכבוד.",
        "014.mp3": "כל הכבוד.",
        "015.mp3": "כיפוף מעולה, שחרר את האצבע.",
        "016.mp3": "כל הכבוד, סיימת את תרגיל הקוביות בהצלחה!",
        "017.mp3": "כל הכבוד, סיימת את תרגיל האחיזה בהצלחה!",
        "018.mp3": "כל הכבוד, סיימת את תרגיל טווחי התנועה בהצלחה!"
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

    # Generate Folder 04 prompts
    for filename, text in folder_04.items():
        path = os.path.join(output_dir, "04", filename)
        generate_hebrew_tts(path, text)

    print("\n" + "=" * 60)
    print(" AUDIO ASSETS GENERATION COMPLETE")
    print("=" * 60)
    print(f"All files saved in: {output_dir}")
    print("Copy the folders '01', '02', '03', and '04' directly to the root of the micro SD card.")
    print("=" * 60)

if __name__ == "__main__":
    main()
