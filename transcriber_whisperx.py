import sys
import os
from pathlib import Path
import torch
import whisperx
from datetime import timedelta


# Set Hugging Face cache to TORCH_CACHE_DIR
#torch_cache_dir = os.getenv("TORCH_CACHE_DIR", "/app/torch-cache")
#os.environ["TORCH_HOME"] = torch_cache_dir
#os.environ["HF_HOME"] = torch_cache_dir
#os.environ["TRANSFORMERS_CACHE"] = torch_cache_dir
#os.environ["HF_DATASETS_CACHE"] = torch_cache_dir
#os.environ["HF_METRICS_CACHE"] = torch_cache_dir

# Args
audio_path = Path(sys.argv[1])
output_file = Path(sys.argv[2])
output_file.parent.mkdir(parents=True, exist_ok=True)

# Env vars
model_name = os.getenv("WHISPER_MODEL", "small")
compute_type = os.getenv("COMPUTE_TYPE", "int8")
output_suffix = os.getenv("TRANSCRIPT_SUFFIX", "_transcript.txt")
hf_token = os.getenv("HF_TOKEN")
enable_diarization = os.getenv("ENABLE_DIARIZATION", "false").lower() == "true"

# Device
device = "cuda" if torch.cuda.is_available() else "cpu"

print("🔁 Loading model...", flush=True)
model = whisperx.load_model(model_name, device, compute_type=compute_type)
print("✅ Model loaded. Starting transcription...", flush=True)

# Transcribe
#result = model.transcribe(str(audio_path))
task = os.getenv("WHISPER_TASK", "transcribe")
result = model.transcribe(str(audio_path), task=task)

print("🧠 Aligning...", flush=True)
align_model, metadata = whisperx.load_align_model(language_code=result["language"], device=device)
aligned = whisperx.align(result["segments"], align_model, metadata, str(audio_path), device)
print("📌 Alignment done.", flush=True)

segments = aligned["segments"]
#print(f"🛠 Segments content: {segments}", flush=True)


# Conditional diarization
if enable_diarization:
    if hf_token:
        try:
            print("🧑‍🤝‍🧑 Performing speaker diarization...", flush=True)
            diarize_model = whisperx.DiarizationPipeline(
                use_auth_token=hf_token,
                device=device
            )
            diarize_segments = diarize_model(str(audio_path))
            segments = whisperx.assign_speakers(aligned["segments"], diarize_segments, strategy="max")
            print("✅ Diarization complete.", flush=True)
        except Exception as e:
            print(f"⚠️ Diarization failed: {e}", flush=True)
            print("⚠️ Proceeding without speaker labels.", flush=True)
    else:
        print("⚠️ ENABLE_DIARIZATION is true, but HF_TOKEN not provided. Skipping diarization.", flush=True)
else:
    print("ℹ️ Diarization disabled via .env", flush=True)

# Speaker label mapping
speaker_map = {}
speaker_count = 1

def get_friendly_speaker(speaker_id):
    global speaker_map, speaker_count
    if speaker_id not in speaker_map:
        speaker_map[speaker_id] = f"Speaker {speaker_count}"
        speaker_count += 1
    return speaker_map[speaker_id]


print(f"📊 Total segments: {len(segments)}", flush=True)


print(f"📝 Writing transcript to {output_file}", flush=True)

with open(output_file, "w", encoding="utf-8") as f:
    for segment in segments:
#        print(f"🔎 Raw segment: {segment}", flush=True)  # Debug print
        start = segment["start"]
        end = segment["end"]
        text = segment["text"].strip()
        speaker_id = segment.get("speaker", None)
        speaker_label = get_friendly_speaker(speaker_id) if speaker_id else "Unknown"
        line = f"[{start:.2f} --> {end:.2f}] {speaker_label}: {text}"
        print(line, flush=True)
        f.write(line + "\n")

print(f"✅ Transcript saved to {output_file}", flush=True)
