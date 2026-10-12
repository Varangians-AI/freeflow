#!/usr/bin/env bash
# Latency bench for an OpenAI-compatible /v1/audio/transcriptions endpoint.
# Uses only synthetic audio generated with macOS `say` (never real recordings):
#   - a fixed spoken phrase (known positive: transcript must contain "quarterly")
#   - three seconds of silence (known negative: transcript must not contain it)
#
# Usage: tools/local-stt/bench.sh [runs]
# Env:
#   STT_URL  base URL (default http://127.0.0.1:8178/v1)
#   STT_KEY  bearer token, if the endpoint needs one (default none)
#   STT_MODEL model field sent with the request (default whisper-1)
set -euo pipefail

RUNS="${1:-5}"
STT_URL="${STT_URL:-http://127.0.0.1:8178/v1}"
PHRASE="Please move the quarterly review to Thursday afternoon and send the updated agenda to the whole team before lunch."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

say -v Samantha -o "$WORK/phrase.wav" --data-format=LEI16@16000 "$PHRASE"
say -v Samantha -o "$WORK/silence.wav" --data-format=LEI16@16000 "[[slnc 3000]]"

clip_seconds() {
    afinfo "$1" | awk '/estimated duration/ { print $3 }'
}

transcribe() {
    local auth=()
    if [ -n "${STT_KEY:-}" ]; then
        auth=(-H "Authorization: Bearer $STT_KEY")
    fi
    curl -sS --fail-with-body "${auth[@]+"${auth[@]}"}" \
        -F "model=${STT_MODEL:-whisper-1}" -F response_format=json -F "file=@$1" \
        -w '\n%{time_total}' \
        "$STT_URL/audio/transcriptions"
}

text_of() {
    sed '$d' | python3 -c 'import json,sys; print(json.load(sys.stdin).get("text","").strip())'
}

echo "endpoint=$STT_URL/audio/transcriptions"
echo "clip_seconds=$(clip_seconds "$WORK/phrase.wav")"

negative="$(transcribe "$WORK/silence.wav" | text_of)"
echo "negative_transcript=[$negative]"
if printf '%s' "$negative" | grep -qi quarterly; then
    echo "FAIL: silence produced the positive phrase" >&2
    exit 1
fi

times=()
for i in $(seq 1 "$RUNS"); do
    out="$(transcribe "$WORK/phrase.wav")"
    seconds="$(printf '%s\n' "$out" | tail -n 1)"
    text="$(printf '%s\n' "$out" | text_of)"
    if ! printf '%s' "$text" | grep -qi quarterly; then
        echo "FAIL: run $i transcript missing phrase: [$text]" >&2
        exit 1
    fi
    ms="$(awk -v s="$seconds" 'BEGIN { printf "%d", s * 1000 }')"
    times+=("$ms")
    echo "run=$i ms=$ms transcript=[$text]"
done

median="$(printf '%s\n' "${times[@]}" | sort -n | awk '{ a[NR] = $1 } END { print (NR % 2) ? a[(NR + 1) / 2] : int((a[NR / 2] + a[NR / 2 + 1]) / 2) }')"
echo "runs=$RUNS median_ms=$median min_ms=$(printf '%s\n' "${times[@]}" | sort -n | head -1) max_ms=$(printf '%s\n' "${times[@]}" | sort -n | tail -1)"
