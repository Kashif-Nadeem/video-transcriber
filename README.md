# 📄 video-transcriber

A Dockerized solution to transcribe or translate `.mp4` and `.mp3` media files to text using FFmpeg and Whisper.

## 📊 Use Case
This system is ideal where media files are uploaded to a shared server, and another container (in the same VNet) processes them for:
- Audio extraction from video
- Transcription of speech
- Optional translation of audio into another language

## 🛠 Folder Structure & Workflow

Input media is expected in:
```
/transcripts/media/
├── audios/
├── videos/

/transcripts/text_transcripts/
└── 2025_Text_Transcripts/
    └── 07_2025_Text_Transcripts/
```

### Output Directory Format
Subfolders are dynamically created based on file modification timestamp:
- `%Y_Audios/%m_%Y_Audios`
- `%Y_Videos/%m_%Y_Videos`
- `%Y_Text_Transcripts/%m_%Y_Text_Transcripts`

### File Naming
- `video.mp4` → `video.mp3`
- `video.mp3` → `video_transcript.txt`

## 🌍 Language Modes

Set via `transcriber.env`:
```
WHISPER_TASK=transcribe       # Output in spoken language
WHISPER_TASK=translate        # Translate to another language
WHISPER_OUTPUT_LANGUAGE=en    # Required if translate is set
```

> If `WHISPER_TASK=transcribe` and `WHISPER_OUTPUT_LANGUAGE` is set, it will be ignored.

## 🚀 Features
- Mounts remote media directories via SSHFS
- Automatically scans and processes media
- Uses parallel workers for FFmpeg and Whisper
- Organizes output by month/year
- Lightweight and self-contained

## 📦 Deployment
1. Define `transcriber.env`
2. Build container with `Dockerfile`
3. Mount Whisper model at `/models`
4. Run the container
# video-transcriber
