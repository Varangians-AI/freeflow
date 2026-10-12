# Local transcription endpoint

Runs [whisper.cpp](https://github.com/ggml-org/whisper.cpp) (MIT) on this
machine behind the OpenAI transcription API, so FreeFlow can transcribe without
a third-party provider. Audio never leaves `127.0.0.1`.

## Run

```bash
tools/local-stt/run-whisper-server.sh base     # or small, large-v3-turbo-q5_0, ...
```

The first run clones whisper.cpp (pinned tag, `WHISPER_CPP_REF`), builds
`whisper-server` with CMake and downloads the model into
`~/.local/share/freeflow-stt` (`FREEFLOW_STT_HOME`). Requires `git`, `cmake`
and the Command Line Tools; no Xcode.

The server listens on `http://127.0.0.1:8178` (`PORT`) and serves
`POST /v1/audio/transcriptions`. It starts with `--language auto` because
FreeFlow omits the language field on Auto-detect and whisper.cpp would
otherwise assume English.

## Point FreeFlow at it

Settings → provider settings:

- **Transcription API URL**: `http://127.0.0.1:8178/v1`
- **Transcription API key**: any non-empty placeholder (the server ignores it).
  Leaving it empty makes FreeFlow fall back to the cleanup provider's key
  (`AppState.resolvedTranscriptionAPIKey`) and send it to this endpoint.
- **API Base URL / API key**: the cleanup (LLM) provider, unchanged. Setup
  validates that provider with `GET /models`, which whisper.cpp does not serve,
  so do not use the local server as the API Base URL.

## Measure

```bash
tools/local-stt/bench.sh 5
```

Generates a fixed synthetic phrase and a silence clip with `say`, checks the
phrase is transcribed (known positive) and silence is not (known negative), then
prints per-run wall time and `median_ms`. `STT_URL` targets another endpoint.
