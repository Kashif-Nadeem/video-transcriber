# video-transcriber

Dockerized media transcription pipeline with full support for video-to-audio conversion and AI-based multilingual transcription.

### 🔧 Key Capabilities:
- 🎞️ Convert `.mp4` videos to `.mp3` using `ffmpeg`
- 🎧 Transcribe `.mp3` audio files using [WhisperX](https://github.com/m-bain/whisperx)
- 🧠 Auto-detect spoken language from media files
- 👥 Speaker diarization support (optional, enabled via `ENABLE_DIARIZATION=true`)
- 📌 Accurate word-level alignment using WhisperX
- 🗂️ Automatically organize output into Year → Month folder structure
- 🌐 Works with both **local and remote media folders** (via SSH, no SSHFS required)
- ⚙️ Fully customizable via a `.env` configuration file
- 🚀 Supports parallel processing of conversion and transcription tasks
- 🌍 WhisperX supports transcription of over **90 languages**, including English, Urdu, Hindi, Arabic, Spanish, Chinese, and more

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
└── text_transcripts/
    └── 2025_Text_Transcripts/
        └── 07_2025_Text_Transcripts/
```

---

## 🚀 Features
- Automatically converts `.mp4` files to `.mp3` using `ffmpeg`
- Transcribes `.mp3` files using WhisperX with alignment
- Optional speaker diarization with HuggingFace token
- Organizes files into Year → Month folders
- Works with **local or remote media folders** using SSH + `rsync`
- Automatically deletes processed `.mp4` and `.mp3` files to save disk space
- Fully configurable using `.env` file (see `transcriber.env` for reference)

---

## ⚙️ Configuration
All runtime options are defined in a `.env` file. See `transcriber.env` for reference.

Includes options for:
- Remote vs local folder mode
- Media directory paths (local and remote)
- SSH credentials and key path
- Folder naming logic using date format
- Whisper model configuration
- Diarization toggle and HuggingFace token

---

## 🛠️ Build & Run with Docker Compose

### 1. Clone the repository
```bash
git clone https://github.com/Kashif-Nadeem/video-transcriber.git
cd video-transcriber
```

### 2. Create your `.env` file
```bash
cp transcriber.env transcriber.prod.env
```
Edit `transcriber.prod.env` with your production configuration.

### 3. Use `docker-compose.yml`
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

### 4. Build & Start
```bash
docker-compose up --build -d
```

> 🚨 Any changes to `Dockerfile`, `requirements.txt`, or source files will trigger a rebuild.

---

## 📌 Notes
- Audio transcripts will be saved with `_transcript.txt` suffix
- Example:
  - Input video: `hello_world.mp4`
  - MP3 output: `hello_world.mp3`
  - Transcript: `hello_world_transcript.txt`
- Files are grouped by audio last modified time into Month-Year folders
- `.mp4` is deleted after MP3 conversion, `.mp3` is deleted after transcript is generated and pushed to remote

---

## 🧠 WhisperX Modes
- `WHISPER_TASK=transcribe` → Transcribe audio in its original language
- `WHISPER_TASK=translate` → Translate spoken audio into `WHISPER_OUTPUT_LANGUAGE` (currently not used with WhisperX)
- `ENABLE_DIARIZATION=true` → Labels segments with speaker tags like Speaker 1, Speaker 2 (requires HF_TOKEN)

---

## 🔐 .gitignore Recommendation
Ensure the following are not committed to Git:
```
.env
transcriber.env
transcriber.prod.env
__pycache__/
*.pyc
```

---

## 👨‍💼 Author
**Kashif Nadeem** — [github.com/Kashif-Nadeem](https://github.com/Kashif-Nadeem)

> Built with ❤️ to simplify transcription workflows across local and remote media sources.
