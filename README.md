# video-transcriber

Dockerized media transcription pipeline for converting `.mp4` videos to `.mp3` and generating text transcripts using [Whisper](https://github.com/openai/whisper). Supports remote folders via SSHFS, automatic folder organization by month/year, and customizable transcription options.

---

## 📂 Folder Structure
```
transcripts/
├── media/
│   ├── audios/
│   │   └── 2025_Audios/
│   │       └── 07_2025_Audios/
│   └── videos/
│       └── 2025_Videos/
│           └── 07_2025_Videos/
├── text_transcripts/
│   └── 2025_Text_Transcripts/
│       └── 07_2025_Text_Transcripts/
└── summaries/
    └── 2025_Summaries/
        └── 07_2025_Summaries/
```

---

## 🚀 Features
- Automatically converts `.mp4` files to `.mp3` using `ffmpeg`
- Transcribes `.mp3` files using `faster-whisper`
- Organizes files into Year → Month folders
- Works with **local or remote media folders** via SSHFS
- Parallel processing of video conversion and transcription
- Fully configurable using `.env` file

---

## ⚙️ Configuration (`transcriber.env`)
Example:
```ini
# --- Paths ---
USE_REMOTE_MEDIA=true
REMOTE_HOST=10.0.0.10
REMOTE_SSH_USER=jitsiadmin
SSH_PRIVATE_KEY_PATH=/root/.ssh/id_rsa

REMOTE_AUDIO_DIRS=/var/www/.../audios/2025_Audios/07_2025_Audios
REMOTE_VIDEO_DIRS=/var/www/.../videos/2025_Videos/07_2025_Videos
REMOTE_TRANSCRIPT_DIR=/var/www/.../text_transcripts/2025_Text_Transcripts

AUDIO_DIRS=/mnt/audios_0
VIDEO_DIRS=/mnt/videos_0
TRANSCRIPT_DIR=/mnt/text_transcripts

AUDIO_FOLDER_FORMAT=%m_%Y_Audios
TRANSCRIPT_FOLDER_FORMAT=%m_%Y_Text_Transcripts

# --- Whisper Settings ---
WHISPER_TASK=transcribe
WHISPER_OUTPUT_LANGUAGE=
MODEL_PATH=/models/ggml-model.q4_0.gguf
TRANSCRIPT_SUFFIX=_transcript.txt

# --- Performance Tuning ---
SCAN_INTERVAL=30
AUDIO_BITRATE=128k
MAX_CONVERT_WORKERS=2
MAX_TRANSCRIBE_WORKERS=2
```

---

## 🛠️ Build & Run with Docker Compose

### 1. Create your `.env` file
```bash
cp transcriber.env transcriber.prod.env
```
Edit `transcriber.prod.env` with your production configuration.

### 2. Use `docker-compose.yml`
```yaml
version: '3.8'
services:
  transcriber:
    build: .
    env_file:
      - transcriber.prod.env
    volumes:
      - /mnt/data/audios:/mnt/audios_0
      - /mnt/data/videos:/mnt/videos_0
      - /mnt/data/text_transcripts:/mnt/text_transcripts
    restart: unless-stopped
```

### 3. Build & Start
```bash
docker-compose up --build -d
```

> 🚨 Any changes to `Dockerfile`, `requirements.txt`, or copied source files will trigger a rebuild.

---

## 📌 Notes
- Audio transcripts will be saved with `_transcript.txt` suffix.
- Example:
  - Input video: `hello_world.mp4`
  - MP3 output: `hello_world.mp3`
  - Transcript: `hello_world_transcript.txt`
- Transcripts are grouped by audio file's last modified time (Month-Year).
- When `WHISPER_TASK=transcribe`, output language is the same as spoken language.
- When `WHISPER_TASK=translate`, transcript will be in the language defined by `WHISPER_OUTPUT_LANGUAGE`.

---

## 🧠 Whisper Language Modes
- `WHISPER_TASK=transcribe` → same language as audio (even if output language is specified)
- `WHISPER_TASK=translate` → always outputs translated transcript in `WHISPER_OUTPUT_LANGUAGE`

---

## 🔒 .gitignore Recommendation
Ensure the following are not committed to Git:
```
.env
transcriber.env
transcriber.prod.env
__pycache__/
*.pyc
```

---

## 👨‍💻 Author
**Kashif Nadeem** — [github.com/Kashif-Nadeem](https://github.com/Kashif-Nadeem)

> Built with ❤️ to simplify transcription workflows across local and remote media sources.
