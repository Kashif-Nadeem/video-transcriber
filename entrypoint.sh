#!/bin/bash
#sleep 3600
set -e

# Ensure .ssh folder and permissions
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Create known_hosts to avoid interactive fingerprint prompt
touch ~/.ssh/known_hosts
chmod 644 ~/.ssh/known_hosts

# Add remote host fingerprint (optional)
if [ -n "$REMOTE_HOST" ]; then
  echo "[INFO] Adding $REMOTE_HOST to known_hosts"
  ssh-keyscan -H "$REMOTE_HOST" >> ~/.ssh/known_hosts || true
else
  echo "[WARN] REMOTE_HOST is not set"
fi

# Create SSH config directly
cat > ~/.ssh/config <<EOF
Host $REMOTE_SSH_ALIAS
    HostName $REMOTE_HOST
    User $REMOTE_SSH_USER
    IdentityFile $PRIVATE_KEY_PATH
    StrictHostKeyChecking no
EOF
chmod 600 ~/.ssh/config

# Create working directories
mkdir -p /app/audios /app/videos /app/transcripts /app/logs

# Delegate all media processing logic to process.sh
exec /app/process.sh

