#!/bin/bash
set -e

# Load environment variables
source transcriber.env

# Mount remote directories if needed
if [ "$USE_REMOTE_MEDIA" = "true" ]; then
  IFS=',' read -ra AUDIO <<< "$REMOTE_AUDIO_DIRS"
  IFS=',' read -ra VIDEO <<< "$REMOTE_VIDEO_DIRS"

  mkdir -p /mnt/audios /mnt/videos /mnt/text_transcripts

  for i in "${!AUDIO[@]}"; do
    sshfs -o IdentityFile=$SSH_PRIVATE_KEY_PATH -o StrictHostKeyChecking=no \
      $REMOTE_SSH_USER@$REMOTE_HOST:${AUDIO[$i]} /mnt/audios_$i
  done

  for i in "${!VIDEO[@]}"; do
    sshfs -o IdentityFile=$SSH_PRIVATE_KEY_PATH -o StrictHostKeyChecking=no \
      $REMOTE_SSH_USER@$REMOTE_HOST:${VIDEO[$i]} /mnt/videos_$i
  done

  sshfs -o IdentityFile=$SSH_PRIVATE_KEY_PATH -o StrictHostKeyChecking=no \
    $REMOTE_SSH_USER@$REMOTE_HOST:$REMOTE_TRANSCRIPT_DIR /mnt/text_transcripts
fi

# Start the transcriber
exec python3 transcriber.py
