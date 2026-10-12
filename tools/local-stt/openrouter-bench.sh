#!/usr/bin/env bash
# Bench OpenRouter's /api/v1/audio/transcriptions across candidate models with bench.sh.
# Reads the key from OPENROUTER_API_KEY; never prints it. Paid calls per model = 1 + RUNS.
# Usage: OPENROUTER_API_KEY=... tools/local-stt/openrouter-bench.sh [runs] [model ...]
set -euo pipefail
: "${OPENROUTER_API_KEY:?set OPENROUTER_API_KEY}"
RUNS="${1:-2}"; shift || true
MODELS=("$@")
[ ${#MODELS[@]} -gt 0 ] || MODELS=(google/gemini-2.5-flash-lite mistralai/voxtral-small-24b-2507 openai/gpt-audio-mini)
DIR="$(cd "$(dirname "$0")" && pwd)"
for m in "${MODELS[@]}"; do
    echo "== $m"
    STT_URL=https://openrouter.ai/api/v1 STT_KEY="$OPENROUTER_API_KEY" STT_MODEL="$m" \
        "$DIR/bench.sh" "$RUNS" 2>&1 | grep -v '^endpoint=' || echo "FAILED: $m"
done
