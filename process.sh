#!/bin/bash
export PYTHONUNBUFFERED=1
set -e

source /app/.env

AUDIO_DIR="/app/audios"
VIDEO_DIR="/app/videos"
TRANSCRIPT_DIR="/app/text_transcripts"
LOG_FILE="/app/process_log.txt"

touch "$LOG_FILE"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting media sync and processing..."

##################################
# Step 1: Sync Required Videos
##################################

if [[ "$USE_REMOTE_MEDIA" == "true" ]]; then
  log "🔍 Checking which videos need to be pulled from remote..."

  find "$VIDEO_DIR" -type f -iname "*.mp4" -delete 2>/dev/null || true

  ssh "$REMOTE_SSH_ALIAS"  "find $REMOTE_VIDEO_DIRS -type f -iname '*.mp4'" | while read -r remote_video; do
    base_name=$(basename "$remote_video" .mp4)
    timestamp=$(ssh "$REMOTE_SSH_ALIAS" stat -c %Y "$remote_video")
    subfolder=$(date -d @"$timestamp" +"$VIDEO_FOLDER_FORMAT")
    mp3_target="$AUDIO_DIR/$subfolder/$base_name.mp3"

    if [[ ! -f "$mp3_target" ]]; then
      log "📥 Pulling $remote_video (no matching mp3 found)"
      mkdir -p "$VIDEO_DIR/$subfolder"
      rsync -az "$REMOTE_SSH_ALIAS:$remote_video" "$VIDEO_DIR/$subfolder/"
    fi
  done
fi

##################################
# Step 2: Convert MP4 to MP3
##################################

log "🎞️ Converting videos to MP3..."

find "$VIDEO_DIR" -type f -iname "*.mp4" | while read -r video; do
  [ -f "$video" ] || continue
  base_name=$(basename "$video" .mp4)
  timestamp=$(stat -c %Y "$video")
  audio_subfolder=$(date -d @"$timestamp" +"$AUDIO_FOLDER_FORMAT")
  audio_target_dir="$AUDIO_DIR/$audio_subfolder"
  output="$audio_target_dir/$base_name.mp3"

  mkdir -p "$audio_target_dir"


  if [[ ! -f "$output" ]]; then
    log "🎧 Converting $video → $output"
    ffmpeg -i "$video" -vn -acodec libmp3lame -b:a "$AUDIO_BITRATE" "$output"

    rm -f "$video"

    if [[ "$USE_REMOTE_MEDIA" == "true" ]]; then
      log "🚀 Pushing $output to remote..."
      ssh "$REMOTE_SSH_ALIAS"  "mkdir -p $REMOTE_AUDIO_DIRS/$audio_subfolder"
      rsync -az "$output" "$REMOTE_SSH_ALIAS:$REMOTE_AUDIO_DIRS/$audio_subfolder/"
    fi
  fi
done

##################################
# Step 3: Sync Required MP3s
##################################

if [[ "$USE_REMOTE_MEDIA" == "true" ]]; then
  log "🔍 Checking which MP3s need to be pulled from remote..."

  ssh "$REMOTE_SSH_ALIAS" "find $REMOTE_AUDIO_DIRS -type f -iname '*.mp3'" | while read -r remote_audio; do
    base_name=$(basename "$remote_audio" .mp3)
    timestamp=$(ssh "$REMOTE_SSH_ALIAS" stat -c %Y "$remote_audio")
    subfolder=$(date -d @"$timestamp" +"$TRANSCRIPT_FOLDER_FORMAT")
    transcript_target="$TRANSCRIPT_DIR/$subfolder/${base_name}${TRANSCRIPT_SUFFIX}"

    if [[ ! -f "$transcript_target" ]]; then
      audio_subfolder=$(date -d @"$timestamp" +"$AUDIO_FOLDER_FORMAT")
      mkdir -p "$AUDIO_DIR/$audio_subfolder"
      rsync -az "$REMOTE_SSH_ALIAS:$remote_audio" "$AUDIO_DIR/$audio_subfolder/"
    fi
  done
fi

##################################
# Step 4: Transcribe MP3 using WhisperX
##################################

log "📝 Transcribing audio to text..."

find "$AUDIO_DIR" -type f -iname "*.mp3" | while read -r audio; do
  [ -f "$audio" ] || continue
  base_name=$(basename "$audio" .mp3)
  timestamp=$(stat -c %Y "$audio")
  subfolder=$(date -d @"$timestamp" +"$TRANSCRIPT_FOLDER_FORMAT")
  transcript_target="$TRANSCRIPT_DIR/$subfolder/${base_name}${TRANSCRIPT_SUFFIX}"

  mkdir -p "$TRANSCRIPT_DIR/$subfolder"

  if [[ ! -f "$transcript_target" ]]; then
    log "✍️ Transcribing $audio → $transcript_target"
    python3 -u /app/transcriber_whisperx.py "$audio" "$transcript_target"


    if [[ "$USE_REMOTE_MEDIA" == "true" ]]; then
      log "🚀 Pushing transcript to remote..."
      ssh "$REMOTE_SSH_ALIAS" "mkdir -p $REMOTE_TRANSCRIPT_DIR/$subfolder"
      rsync -az -e "ssh -i $PRIVATE_KEY_PATH -o StrictHostKeyChecking=no" "$transcript_target" "$REMOTE_SSH_USER@$REMOTE_HOST:$REMOTE_TRANSCRIPT_DIR/$subfolder/"
    fi
  fi
done

##################################
# Step 5: Ensure .mp3 is pushed and cleanup after transcript
##################################

if [[ "$USE_REMOTE_MEDIA" == "true" ]]; then
  log "🧹 Ensuring remote has all .mp3 files and cleaning up local copies if transcript exists..."

  find "$AUDIO_DIR" -type f -iname "*.mp3" | while read -r mp3_file; do
    [ -f "$mp3_file" ] || continue
    base_name=$(basename "$mp3_file" .mp3)
    timestamp=$(stat -c %Y "$mp3_file")
    audio_subfolder=$(date -d @"$timestamp" +"$AUDIO_FOLDER_FORMAT")
    transcript_subfolder=$(date -d @"$timestamp" +"$TRANSCRIPT_FOLDER_FORMAT")
    transcript_path="$TRANSCRIPT_DIR/$transcript_subfolder/${base_name}${TRANSCRIPT_SUFFIX}"
    remote_mp3_path="$REMOTE_AUDIO_DIRS/$audio_subfolder/$base_name.mp3"

    # Check and push if not on remote
    if ! ssh "$REMOTE_SSH_ALIAS" "[ -f \"$remote_mp3_path\" ]"; then
      log "🔁 Re-pushing missing $mp3_file to remote..."
      ssh "$REMOTE_SSH_ALIAS" "mkdir -p $REMOTE_AUDIO_DIRS/$audio_subfolder"
      rsync -az "$mp3_file" "$REMOTE_SSH_ALIAS:$REMOTE_AUDIO_DIRS/$audio_subfolder/"
    fi

    # Cleanup local .mp3 if transcript exists
    if [[ -f "$transcript_path" ]]; then
      log "🧹 Cleaning up local $mp3_file (transcript confirmed)"
      rm -f "$mp3_file"
    fi
  done
fi



log "✅ Processing completed."
