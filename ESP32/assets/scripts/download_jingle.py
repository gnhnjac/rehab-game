import urllib.request
import os

def download_jingle():
    url = "https://incompetech.com/music/royalty-free/mp3-royaltyfree/Pixel%20Peeker%20Polka%20-%20faster.mp3"
    output_dir = os.path.join("ESP32", "assets", "audio_assets", "04")
    os.makedirs(output_dir, exist_ok=True)
    output_path = os.path.join(output_dir, "011.mp3")
    
    print(f"Downloading royalty-free retro jingle from: {url}")
    try:
        # Use a browser User-Agent header to avoid basic scraping blocks
        req = urllib.request.Request(
            url, 
            headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'}
        )
        with urllib.request.urlopen(req) as response:
            with open(output_path, 'wb') as out_file:
                out_file.write(response.read())
        print(f"Download complete! Saved to: {output_path}")
    except Exception as e:
        print(f"Error downloading jingle: {e}")

if __name__ == "__main__":
    download_jingle()
