#!/usr/bin/env bash
# Build (once) and run a local whisper.cpp server that speaks the OpenAI
# transcription API at /v1/audio/transcriptions, so FreeFlow's Transcription
# API URL can point at it. Everything stays on this machine.
#
# Usage: tools/local-stt/run-whisper-server.sh [model]
#   model: whisper.cpp ggml model name, default "base" (e.g. small, large-v3-turbo-q5_0)
# Env:
#   FREEFLOW_STT_HOME  checkout/model dir   (default ~/.local/share/freeflow-stt)
#   WHISPER_CPP_REF    whisper.cpp git tag  (default v1.9.5)
#   PORT               listen port          (default 8178, bound to 127.0.0.1)
#   THREADS            inference threads    (default: physical cores)
set -euo pipefail

MODEL="${1:-base}"
STT_HOME="${FREEFLOW_STT_HOME:-$HOME/.local/share/freeflow-stt}"
REF="${WHISPER_CPP_REF:-v1.9.5}"
PORT="${PORT:-8178}"
THREADS="${THREADS:-$(sysctl -n hw.physicalcpu 2>/dev/null || echo 4)}"
SRC="$STT_HOME/whisper.cpp"
SERVER_BIN="$SRC/build/bin/whisper-server"
MODEL_FILE="$SRC/models/ggml-$MODEL.bin"

mkdir -p "$STT_HOME"

if [ ! -d "$SRC/.git" ]; then
    git clone --depth 1 --branch "$REF" https://github.com/ggml-org/whisper.cpp.git "$SRC"
fi

if [ ! -x "$SERVER_BIN" ]; then
    cmake -S "$SRC" -B "$SRC/build" -DCMAKE_BUILD_TYPE=Release -DWHISPER_BUILD_TESTS=OFF
    cmake --build "$SRC/build" --config Release -j "$THREADS" --target whisper-server
fi

if [ ! -f "$MODEL_FILE" ]; then
    bash "$SRC/models/download-ggml-model.sh" "$MODEL" "$SRC/models"
fi

# Metal on Intel Macs returns empty transcripts (verified 2026-10-12: same clip, same
# model → "" with GPU, correct text with --no-gpu). Default to CPU on x86_64;
# override with WHISPER_GPU=1 / WHISPER_GPU=0.
GPU_ARGS=()
if [ "${WHISPER_GPU:-$([ "$(uname -m)" = x86_64 ] && echo 0 || echo 1)}" = 0 ]; then
    GPU_ARGS=(--no-gpu)
fi

# --language auto: FreeFlow omits the language field on Auto-detect, and the
# server would otherwise fall back to English.
exec "$SERVER_BIN" \
    --host 127.0.0.1 \
    --port "$PORT" \
    --threads "$THREADS" \
    --model "$MODEL_FILE" \
    --language auto \
    --inference-path /v1/audio/transcriptions \
    "${GPU_ARGS[@]+"${GPU_ARGS[@]}"}"
