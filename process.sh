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

log "Starting media sync and processing..."

##################################
# Step 0: Pull required .mp4 and .mp3 based on remote-only diff
##################################
if [[ "$USE_REMOTE_MEDIA" == "true" ]]; then
  log "🔍 Step 0: Resolving missing media based on remote files..."

  # Clear old records
  > /tmp/pulled_mp4_files.txt
  > /tmp/pulled_mp3_files.txt

  remote_mp4s=$(ssh "$REMOTE_SSH_ALIAS" "find $REMOTE_VIDEO_DIRS -type f -iname '*.mp4'")
  remote_mp3s=$(ssh "$REMOTE_SSH_ALIAS" "find $REMOTE_AUDIO_DIRS -type f -iname '*.mp3'")
  remote_txts=$(ssh "$REMOTE_SSH_ALIAS" "find $REMOTE_TRANSCRIPT_DIR -type f -iname '*.txt'")

  log "📼 Total remote MP4s: $(echo \"$remote_mp4s\" | wc -l)"
  log "🎧 Total remote MP3s: $(echo \"$remote_mp3s\" | wc -l)"
  log "📝 Total remote TXTs: $(echo \"$remote_txts\" | wc -l)"

  # Get base names
  mp4_basenames=$(echo "$remote_mp4s" | sed 's#.*/##' | sed 's/\.mp4$//' | sort)
  mp3_basenames=$(echo "$remote_mp3s" | sed 's#.*/##' | sed 's/\.mp3$//' | sort)
  txt_basenames=$(echo "$remote_txts" | sed 's#.*/##' | sed "s/$TRANSCRIPT_SUFFIX\$//" | sort)

  # 1. MP4s missing MP3s → download MP4
  missing_mp3s=$(comm -23 <(echo "$mp4_basenames") <(echo "$mp3_basenames"))
  for name in $missing_mp3s; do
    remote_path=$(echo "$remote_mp4s" | grep "/$name.mp4" | head -n 1)
    if [[ -n "$remote_path" ]]; then
      timestamp=$(ssh "$REMOTE_SSH_ALIAS" stat -c %Y "$remote_path")
    else
      log "⚠️ Skipping stat: remote_path is empty"
      continue
    fi
    subfolder=$(date -d @"$timestamp" +"$VIDEO_FOLDER_FORMAT")
    mkdir -p "$VIDEO_DIR/$subfolder"
    log "📥 Downloading missing mp4 source video: $remote_path"
    rsync -az "$REMOTE_SSH_ALIAS:$remote_path" "$VIDEO_DIR/$subfolder/"
    echo "$VIDEO_DIR/$subfolder/$name.mp4" >> /tmp/pulled_mp4_files.txt
  done

  # 2. MP3s missing TXTs → download MP3
  missing_txts=$(comm -23 <(echo "$mp3_basenames") <(echo "$txt_basenames"))
  for name in $missing_txts; do
    remote_path=$(echo "$remote_mp3s" | grep "/$name.mp3" | head -n 1)
    if [[ -n "$remote_path" ]]; then
      timestamp=$(ssh "$REMOTE_SSH_ALIAS" stat -c %Y "$remote_path")
    else
      log "⚠️ Skipping stat: remote_path is empty"
      continue
    fi
    subfolder=$(date -d @"$timestamp" +"$AUDIO_FOLDER_FORMAT")
    mkdir -p "$AUDIO_DIR/$subfolder"
    log "📥 Downloading missing transcript source audio: $remote_path"
    rsync -az "$REMOTE_SSH_ALIAS:$remote_path" "$AUDIO_DIR/$subfolder/"
    echo "$AUDIO_DIR/$subfolder/$name.mp3" >> /tmp/pulled_mp3_files.txt
  done

  log "✅ Step 0 complete — missing .mp4 and .mp3 files pulled."
fi


log "📂 Local MP4 files:"
find "$VIDEO_DIR" -type f -iname "*.mp4" | tee -a "$LOG_FILE"

log "🎵 Local MP3 files:"
find "$AUDIO_DIR" -type f -iname "*.mp3" | tee -a "$LOG_FILE"

log "📝 Local Transcript TXT files:"
find "$TRANSCRIPT_DIR" -type f -iname "*.txt" | tee -a "$LOG_FILE"


##################################
# Step 1: Convert Videos to MP3
##################################

log "🎞️ Converting videos to MP3..."

find "$VIDEO_DIR" -type f -iname "*.mp4" | while read -r mp4_file; do
  base_filename=$(basename "$mp4_file" .mp4)
  timestamp=$(stat -c %Y "$mp4_file")
  mp3_subfolder=$(date -d @"$timestamp" +"$AUDIO_DIR/$AUDIO_FOLDER_FORMAT")
  mkdir -p "$mp3_subfolder"
  mp3_file_path="$mp3_subfolder/${base_filename}.mp3"

  if [[ -f "$mp3_file_path" ]]; then
    log "⚠️ Skipping $mp4_file — MP3 already exists locally."
    continue
  fi

  log "🎬 Converting $mp4_file to $mp3_file_path..."
  start_time=$(date +%s)

  if ffmpeg -i "$mp4_file" -b:a "$AUDIO_BITRATE" -vn "$mp3_file_path" -y < /dev/null; then
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    log "✅ Video to MP3 conversion took ${duration}s for $mp4_file"
    rm -f "$mp4_file"
  else
    log "❌ Failed to convert $mp4_file"
    echo "$mp4_file" >> /tmp/failed_mp4_to_mp3.txt
  fi
done

################################################
# Step 2: Transcribe Audio to Text Using WisperX
################################################

log "📝 Transcribing audio to text..."

find "$AUDIO_DIR" -type f -iname "*.mp3" | while read -r mp3_file; do
  base_filename=$(basename "$mp3_file" .mp3)

  timestamp=$(stat -c %Y "$mp3_file")
  year=$(date -d @"$timestamp" +"%Y")
  month=$(date -d @"$timestamp" +"%m")
  month_year="${month}_${year}_Text_Transcripts"
  transcript_subfolder="$TRANSCRIPT_DIR/${year}_Text_Transcripts/$month_year"

  mkdir -p "$transcript_subfolder"
  transcript_file="$transcript_subfolder/${base_filename}${TRANSCRIPT_SUFFIX}"

  if [[ -f "$transcript_file" ]]; then
    log "🧠 Skipping $mp3_file — transcript already exists locally."
    continue
  fi

  log "🎤 Transcribing $mp3_file to $transcript_file..."
  log "📁 Transcript will be saved to $transcript_file"

  start_time=$(date +%s)

 echo "🗣️  Whisper task mode: $WHISPER_TASK"

  python3 -u /app/transcriber_whisperx.py "$mp3_file" "$transcript_file"
  end_time=$(date +%s)

  duration=$((end_time - start_time))
  log "⏱️ MP3 to transcript conversion took ${duration}s for $mp3_file"

  rm -f "$mp3_file"
done



##################################
# Step 3: Push processed files to remote and clean up
##################################

log "📤 Step 3: Upload new .mp3 and .txt files to remote, cleanup pulled media..."

# --------- 1. Remove all pulled .mp4 and .mp3 ----------
if [[ -f /tmp/pulled_mp4_files.txt ]]; then
  log "🗑️ Deleting pulled .mp4 files..."
  while read -r mp4; do
    [[ -f "$mp4" ]] && rm -f "$mp4" && log "✅ Deleted $mp4"
  done < /tmp/pulled_mp4_files.txt
fi

if [[ -f /tmp/pulled_mp3_files.txt ]]; then
  log "🗑️ Deleting pulled .mp3 files..."
  while read -r mp3; do
    [[ -f "$mp3" ]] && rm -f "$mp3" && log "✅ Deleted $mp3"
  done < /tmp/pulled_mp3_files.txt
fi

# --------- 2. Push new .mp3 files (not pulled) ----------
log "📤 Uploading new .mp3 files to $REMOTE_HOST..."

find "$AUDIO_DIR" -type f -iname "*.mp3" | while read -r mp3_file; do
  # Skip if in pulled list
  if grep -qxF "$mp3_file" /tmp/pulled_mp3_files.txt 2>/dev/null; then
    log "⏩ Skipping $mp3_file (was pulled earlier)"
    continue
  fi

  relative_path="${mp3_file#"$AUDIO_DIR"/}"
  remote_path="$REMOTE_AUDIO_DIRS/$relative_path"
  remote_dir=$(dirname "$remote_path")

 # ssh -i "$PRIVATE_KEY_PATH" "$REMOTE_SSH_USER@$REMOTE_HOST" "mkdir -p \"$remote_dir\""
 # scp -i "$PRIVATE_KEY_PATH" "$mp3_file" "$REMOTE_SSH_USER@$REMOTE_HOST:\"$remote_path\""

  ssh "$REMOTE_SSH_ALIAS" "mkdir -p '$remote_dir'"
  scp "$mp3_file" "$REMOTE_SSH_ALIAS:$remote_path"


  if [[ $? -eq 0 ]]; then
    log "✅ Pushed $mp3_file. Deleting local copy..."
    rm -f "$mp3_file"
  else
    log "⚠️ Failed to push $mp3_file. Retaining local copy."
  fi
done

# --------- 3. Push all .txt transcript files ----------
log "📤 Uploading .txt transcripts to $REMOTE_HOST..."

find "$TRANSCRIPT_DIR" -type f -iname "*.txt" | while read -r txt_file; do
  relative_path="${txt_file#"$TRANSCRIPT_DIR"/}"
  remote_path="$REMOTE_TRANSCRIPT_DIR/$relative_path"
  remote_dir=$(dirname "$remote_path")

  ssh "$REMOTE_SSH_ALIAS" "mkdir -p '$remote_dir'"
  scp "$txt_file" "$REMOTE_SSH_ALIAS:$remote_path"

  if [[ $? -eq 0 ]]; then
    log "✅ Pushed $txt_file. Deleting local copy..."
    rm -f "$txt_file"
  else
    log "⚠️ Failed to push $txt_file. Retaining local copy."
  fi
done

log "✅ Step 3 complete: Uploaded files and cleaned up where needed."


log "✅ Processing completed."
log "⏳ Sleeping for $SCAN_INTERVAL seconds before next scan..."
sleep "$SCAN_INTERVAL"

done

