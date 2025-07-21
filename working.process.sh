#!/bin/bash
export PYTHONUNBUFFERED=1
set -e
while true; do

source /app/.env

AUDIO_DIR="/app/audios"
VIDEO_DIR="/app/videos"
TRANSCRIPT_DIR="/app/text_transcripts"
LOG_FILE="/app/process_log.txt"

touch "$LOG_FILE"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

##

check_and_delete_local_audio_if_fully_synced() {
  local base_name="$1"
  local audio_subfolder="$2"
  local video_subfolder="$3"
  local transcript_subfolder="$4"

  local remote_audio_path="$REMOTE_AUDIO_DIRS/$audio_subfolder/${base_name}.mp3"
  local remote_video_path="$REMOTE_VIDEO_DIRS/$video_subfolder/${base_name}.mp4"
  local remote_transcript_path="$REMOTE_TRANSCRIPT_DIR/$transcript_subfolder/${base_name}${TRANSCRIPT_SUFFIX}"
  local local_audio_path="$AUDIO_DIR/$audio_subfolder/${base_name}.mp3"

  if [ -f "$local_audio_path" ]; then
    if ssh "$REMOTE_SSH_USER@$REMOTE_HOST" "[ -f \"$remote_audio_path\" ] && [ -f \"$remote_video_path\" ] && [ -f \"$remote_transcript_path\" ]"; then
      log "🧹 Deleting local audio file $local_audio_path — already processed on remote"
      rm -f "$local_audio_path"
    fi
  fi
}



log "Starting media sync and processing..."
log "📂 Local MP4 files:"
find "$VIDEO_DIR" -type f -iname "*.mp4" | tee -a "$LOG_FILE"

log "🎵 Local MP3 files:"
find "$AUDIO_DIR" -type f -iname "*.mp3" | tee -a "$LOG_FILE"

log "📝 Local Transcript TXT files:"
find "$TRANSCRIPT_DIR" -type f -iname "*.txt" | tee -a "$LOG_FILE"



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
    start_time=$(date +%s)
    ffmpeg -i "$video" -vn -acodec libmp3lame -b:a "$AUDIO_BITRATE" "$output"
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    log "⏱️ Video-to-audio conversion took $duration seconds"
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
  # If transcript already exists locally, skip
  if [[ -f "$transcript_target" ]]; then
    log "🛑 Skipping $audio — transcript already exists locally."
    check_and_delete_local_audio_if_fully_synced "$base_name" "$audio_subfolder" "$video_subfolder" "$transcript_subfolder"
    continue
  fi

  mkdir -p "$TRANSCRIPT_DIR/$subfolder"

  remote_exists=false
  if [[ "$USE_REMOTE_MEDIA" == "true" ]]; then
    expected_remote_path="$REMOTE_TRANSCRIPT_DIR/$subfolder/${base_name}${TRANSCRIPT_SUFFIX}"
    if ssh -i "$PRIVATE_KEY_PATH" "$REMOTE_SSH_USER@$REMOTE_HOST" "[ -f '$expected_remote_path' ]"; then
      log "🛑 Skipping $audio — transcript already exists on remote."
      remote_exists=true
    fi
  fi

  if [[ ! -f "$transcript_target" && "$remote_exists" == "false" ]]; then
    log "✍️ Transcribing $audio → $transcript_target"
    start_time=$(date +%s)
    if python3 -u /app/transcriber_whisperx.py "$audio" "$transcript_target"; then
      log "✅ Transcription completed for $audio"
      end_time=$(date +%s)
      duration=$((end_time - start_time))
      log "✅ Transcription completed for $audio"
      log "⏱️ Audio-to-transcript conversion took $duration seconds"

      if [[ "$USE_REMOTE_MEDIA" == "true" ]]; then
        log "🚀 Pushing transcript to remote..."
        ssh -i "$PRIVATE_KEY_PATH" "$REMOTE_SSH_USER@$REMOTE_HOST" "mkdir -p '$REMOTE_TRANSCRIPT_DIR/$subfolder'"
       scp -i "$PRIVATE_KEY_PATH" "$transcript_target" "$REMOTE_SSH_USER@$REMOTE_HOST:$REMOTE_TRANSCRIPT_DIR/$subfolder/"

       if [[ $? -eq 0 ]]; then
         log "🧹 Cleaning up local transcript file: $transcript_target"
         rm -f "$transcript_target"
      else
        log "⚠️ Failed to push transcript to remote. Skipping deletion."
      fi
    fi

    else
      log "❌ ERROR: Transcription failed for $audio"
      log "📄 Check transcriber_whisperx.py and logs above for details."
      continue
    fi
  fi
done

##################################
# Step 5: Ensure .mp3 is pushed and cleanup after transcript
##################################

if [[ "$USE_REMOTE_MEDIA" == "true" ]]; then
  log "🧹 Ensuring remote has all .mp3 files and cleaning up local copies if transcript exists..."

  # Print local .mp3, .mp4, and .txt files
  log "📂 Local MP4 files:"
  find "$VIDEO_DIR" -type f -iname "*.mp4" | tee -a "$LOG_FILE"

  log "🎵 Local MP3 files:"
  find "$AUDIO_DIR" -type f -iname "*.mp3" | tee -a "$LOG_FILE"

  log "📝 Local Transcript TXT files:"
  find "$TRANSCRIPT_DIR" -type f -iname "*.txt" | tee -a "$LOG_FILE"

  find "$AUDIO_DIR" -type f -iname "*.mp3" | while read -r mp3_file; do
    [ -f "$mp3_file" ] || continue
    base_name=$(basename "$mp3_file" .mp3)
    timestamp=$(stat -c %Y "$mp3_file")
    audio_subfolder=$(date -d @"$timestamp" +"$AUDIO_FOLDER_FORMAT")
    transcript_subfolder=$(date -d @"$timestamp" +"$TRANSCRIPT_FOLDER_FORMAT")
    transcript_path="$TRANSCRIPT_DIR/$transcript_subfolder/${base_name}${TRANSCRIPT_SUFFIX}"
    remote_mp3_path="$REMOTE_AUDIO_DIRS/$audio_subfolder/$base_name.mp3"
    remote_transcript_path="$REMOTE_TRANSCRIPT_DIR/$transcript_subfolder/${base_name}${TRANSCRIPT_SUFFIX}"

    # Check and push MP3 if not on remote
    if ! ssh "$REMOTE_SSH_ALIAS" "[ -f \"$remote_mp3_path\" ]"; then
      log "🔁 Re-pushing missing $mp3_file to remote..."
      ssh "$REMOTE_SSH_ALIAS" "mkdir -p $REMOTE_AUDIO_DIRS/$audio_subfolder"
      rsync -az "$mp3_file" "$REMOTE_SSH_ALIAS:$REMOTE_AUDIO_DIRS/$audio_subfolder/"
    fi

    # Push transcript to remote if missing
    if [[ -f "$transcript_path" ]]; then
      if ! ssh -i "$PRIVATE_KEY_PATH" "$REMOTE_SSH_USER@$REMOTE_HOST" "[ -f '$remote_transcript_path' ]"; then
        log "🚀 Pushing missing transcript $transcript_path to remote..."
        ssh -i "$PRIVATE_KEY_PATH" "$REMOTE_SSH_USER@$REMOTE_HOST" "mkdir -p '$REMOTE_TRANSCRIPT_DIR/$transcript_subfolder'"
        scp -i "$PRIVATE_KEY_PATH" "$transcript_path" "$REMOTE_SSH_USER@$REMOTE_HOST:$REMOTE_TRANSCRIPT_DIR/$transcript_subfolder/"

        if [[ $? -eq 0 ]]; then
          log "✅ Successfully pushed $transcript_path to remote."
        else
          log "⚠️ Failed to push $transcript_path to remote."
        fi
      else
        log "✅ Transcript already exists on remote: $remote_transcript_path"
      fi
    fi

    # Cleanup local .mp3 if transcript exists
    if [[ -f "$transcript_path" ]]; then
      log "🧹 Cleaning up local $mp3_file (transcript confirmed)"
      rm -f "$mp3_file"
    fi
  done
fi

##################################
# Step 6: Push any remaining .txt transcripts to remote
##################################

if [[ "$USE_REMOTE_MEDIA" == "true" ]]; then
  log "🧮 Checking for any local transcripts that were not uploaded yet..."

  find "$TRANSCRIPT_DIR" -type f -name "*.txt" | while read -r transcript_file; do

    [ -f "$transcript_file" ] || continue
    base_name=$(basename "$transcript_file")
    log "📤 Evaluating local transcript: $transcript_file"
    log "📄 Base name: $base_name"

    # Normalize path to derive correct relative subfolder
    relative_path=$(realpath --relative-to="$TRANSCRIPT_DIR" "$transcript_file")
    subfolder_path=$(dirname "$relative_path")
    remote_path="$REMOTE_TRANSCRIPT_DIR/$subfolder_path/$base_name"
   log "📁 Derived subfolder: $subfolder_path"
   log "📤 Remote path will be: $remote_path"


    if ! ssh -i "$PRIVATE_KEY_PATH" "$REMOTE_SSH_USER@$REMOTE_HOST" "[ -f '$remote_path' ]"; then
      log "🚀 Uploading orphan transcript: $transcript_file → $remote_path"
      ssh -i "$PRIVATE_KEY_PATH" "$REMOTE_SSH_USER@$REMOTE_HOST" "mkdir -p '$REMOTE_TRANSCRIPT_DIR/$subfolder_path'"
      scp -i "$PRIVATE_KEY_PATH" "$transcript_file" "$REMOTE_SSH_USER@$REMOTE_HOST:$REMOTE_TRANSCRIPT_DIR/$subfolder_path/"

      if [[ $? -eq 0 ]]; then
        log "✅ Successfully uploaded orphan transcript: $base_name"
        rm -f "$transcript_file"
        log "🧹 Deleted local transcript: $transcript_file"
      else
        log "⚠️ Failed to upload: $base_name"
      fi
    else
      log "✅ Transcript already exists remotely: $remote_path"
      log "🧹 Deleting local copy: $transcript_file"
      rm -f "$transcript_file"
    fi
  done
fi

log "✅ Processing completed."
log "⏳ Sleeping for $SCAN_INTERVAL seconds before next scan..."
sleep "$SCAN_INTERVAL"
done

