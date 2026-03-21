#!/bin/bash
# Whisper Model Benchmark: whisper-large-v3-turbo vs whisper-large-v3
# Usage: GROQ_API_KEY=gsk_... bash scripts/benchmark-whisper.sh [audio_dir]
#
# Sends each .wav file in audio_dir (default: /tmp/ember-benchmark/)
# to both models and compares latency + output.
# Expects 16kHz mono WAV files.

set -euo pipefail

API_KEY="${GROQ_API_KEY:-}"
AUDIO_DIR="${1:-/tmp/ember-benchmark}"
MODELS=("whisper-large-v3-turbo" "whisper-large-v3")

if [ -z "$API_KEY" ]; then
  # Try loading from config
  CFG="$HOME/.config/ember/config.env"
  if [ -f "$CFG" ]; then
    API_KEY=$(grep '^GROQ_API_KEY=' "$CFG" | cut -d= -f2)
  fi
fi

if [ -z "$API_KEY" ]; then
  echo "Error: GROQ_API_KEY not set. Export it or add to ~/.config/ember/config.env"
  exit 1
fi

if [ ! -d "$AUDIO_DIR" ]; then
  echo "No audio directory found at $AUDIO_DIR"
  echo ""
  echo "To run this benchmark:"
  echo "  1. Create $AUDIO_DIR"
  echo "  2. Record 3+ WAV files (16kHz mono) of varying length:"
  echo "     - short.wav  (~3s)"
  echo "     - medium.wav (~15s)"
  echo "     - long.wav   (~60s)"
  echo "  3. Run: bash scripts/benchmark-whisper.sh"
  exit 1
fi

echo "# Whisper Model Benchmark"
echo ""
echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""
echo "| File | Size | Model | Latency (ms) | Text Length | First 80 chars |"
echo "|------|------|-------|-------------|-------------|----------------|"

for wav in "$AUDIO_DIR"/*.wav; do
  [ -f "$wav" ] || continue
  fname=$(basename "$wav")
  fsize=$(stat -f%z "$wav" 2>/dev/null || stat -c%s "$wav" 2>/dev/null)
  fsize_kb=$((fsize / 1024))

  for model in "${MODELS[@]}"; do
    # Build multipart body
    start_ms=$(($(date +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1000000000))') / 1000000))

    response=$(curl -s -w "\n%{time_total}" \
      -X POST "https://api.groq.com/openai/v1/audio/transcriptions" \
      -H "Authorization: Bearer $API_KEY" \
      -F "file=@$wav" \
      -F "model=$model" \
      -F "response_format=verbose_json" 2>&1)

    # Split response and timing
    body=$(echo "$response" | head -n -1)
    curl_time=$(echo "$response" | tail -1)
    latency_ms=$(python3 -c "print(int(float('$curl_time') * 1000))")

    # Parse text from JSON
    text=$(echo "$body" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('text',''))" 2>/dev/null || echo "PARSE_ERROR")
    text_len=${#text}
    preview=$(echo "$text" | head -c 80 | tr '\n' ' ')

    echo "| $fname | ${fsize_kb}KB | $model | $latency_ms | $text_len | $preview |"
  done
done

echo ""
echo "## Notes"
echo "- Latency includes network round-trip to Groq API"
echo "- Both models use verbose_json response format"
echo "- Compare text output manually for accuracy differences"
