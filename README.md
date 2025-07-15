# video-transcriber

Dockerized media transcription pipeline with full support for video-to-audio conversion and AI-based multilingual transcription.

### 🔧 Key Capabilities:
- 🎞️ Convert `.mp4` videos to `.mp3` using `ffmpeg`
- 🎙️ Transcribe `.mp3` audio files using OpenAI Whisper (`faster-whisper`)
- 🧠 Auto-detect spoken language from media files
- 🌍 Translate transcripts into a target language (if configured)
- 🗂️ Automatically organize output into Year → Month folder structure
- 🌐 Works with both **local and remote media folders** (via SSHFS)
- ⚙️ Fully customizable via a `.env` configuration file
- 🚀 Supports parallel processing of conversion and transcription tasks
- 🌍 Whisper supports transcription/translation of over **90 languages**, including English, Urdu, Hindi, Arabic, Spanish, Chinese, and many more. You can choose whether to:
  - Transcribe to the **same spoken language** (e.g., English → English)
  - Automatically **translate** the audio into a **different target language** (e.g., Urdu → English)
  - Use the `WHISPER_TASK` config option to control this behavior

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
- Fully configurable using `.env` file (see `transcriber.env` for reference)
- Language detection and optional translation using Whisper

---

## ⚙️ Configuration
All runtime options are defined in a `.env` file. See `transcriber.env` for reference.
It includes options such as:
- Remote vs local folder mode
- Audio/video/text directories
- SSH connection config (if using remote server)
- Folder structure logic
- Whisper transcription behavior and output (same language or translated)

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
- `WHISPER_TASK=transcribe` → Detects and transcribes spoken language as-is (ignores output language setting)
- `WHISPER_TASK=translate` → Detects language and translates to `WHISPER_OUTPUT_LANGUAGE`
- Whisper supports transcription/translation of over **90 languages**, including support for scripts such as Latin, Arabic, Cyrillic, and Devanagari.

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
