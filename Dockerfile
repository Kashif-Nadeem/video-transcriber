FROM python:3.10-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    ffmpeg \
    rsync \
    openssh-client \
    git \
    gcc \
    libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy Python dependencies first
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Install WhisperX and Faster-Whisper from PyPI (recommended)
RUN pip install whisperx && pip install faster-whisper

RUN pip install --upgrade pytorch-lightning

# Copy project files
COPY . .

# Ensure scripts are executable
RUN chmod +x /app/entrypoint.sh /app/process.sh

# Entry point
ENTRYPOINT ["/app/entrypoint.sh"]
