import sys
import os
from pathlib import Path
from faster_whisper import WhisperModel

# Args
audio_path = Path(sys.argv[1])
output_dir = Path(sys.argv[2])
output_dir.mkdir(parents=True, exist_ok=True)

# Env vars
model_path = os.getenv("MODEL_PATH")
task = os.getenv("WHISPER_TASK", "transcribe")
lang = os.getenv("WHISPER_LANGUAGE", "en")
compute_type = os.getenv("COMPUTE_TYPE", "int8")
transcript_suffix = os.getenv("TRANSCRIPT_SUFFIX", "_transcript.txt")

# Load model
#model = WhisperModel(model_path, compute_type=compute_type)
model = WhisperModel(model_path, compute_type=compute_type, local_files_only=True)

# Transcribe
segments, _ = model.transcribe(str(audio_path), task=task, language=lang)

# Write output
output_file = output_dir / f"{audio_path.stem}{transcript_suffix}"
with open(output_file, "w", encoding="utf-8") as f:
    for segment in segments:
        line = segment.text.strip()
        f.write(line + "\n")
        print(line)  # ✅ Correctly aligned with the rest of the loop

print(f"✅ Transcript saved to {output_file}")  # ✅ Outside the loop

