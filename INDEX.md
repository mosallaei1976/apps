# Persian Transcriber: context index

Repository root: apps/. Read `../AGENTS.md` first. The client UI is wired to the
application coordinator through Riverpod; `flutter analyze` is clean and all 214
client tests pass. Native model management exists behind the verified-model port;
Windows microphone capture and native FFmpeg audio preparation exist behind the
audio ports. Native whisper.cpp FFI inference exists behind the engine port and
the ABI is pinned to whisper.cpp v1.8.2. The trusted manifest now pins verified
Fast/Balanced GGML artifacts, but no native shared library is bundled yet and
persistence remains planned.

## Structure
- `client/lib/main.dart`: composition root and Riverpod provider overrides for the
  coordinator and platform audio capture.
- `client/lib/features/transcriber/presentation/`: screen, session controller and
  providers; consumes the coordinator and audio-capture ports only. The session
  records first, stops capture, then starts a transcription job with the opaque
  capture ID.
- `client/lib/features/transcriber/application/`: coordinator, typed job events,
  engine leases, cancellation, chunk offsets and cleanup.
- `client/lib/features/transcriber/domain/`: canonical engine contract, DTOs,
  failures, and audio-capture/audio-preparation/model/cancellation ports.
- `client/lib/platform/`: conditional factories, unavailable Native/WASM engine
  stubs, model manifest/storage/download infrastructure, audio capture and
  preparation composition helpers.
- `client/lib/platform/audio/`: Windows microphone capture through
  `record_windows`, strict RIFF/WAVE validation, verified local FFmpeg execution,
  a dedicated worker isolate with request IDs, managed capture/job temporary
  storage and explicit unavailable fallbacks for missing/non-Windows/web builds.
- `client/test/`: domain/application contracts, platform adapters (models,
  Windows capture, WAV parsing, FFmpeg runner/toolchain and preparation worker),
  presentation/controller tests and widget smoke tests.
- `client/tool/`: operator-only offline artifact pipeline. `model_pins.json` is
  the model source of truth; `fetch_models.ps1` verifies exact sizes/SHA-256 and
  regenerates the manifest; `build_whisper_android.ps1` builds and probes
  `libwhisper.so` for `arm64-v8a`/`armeabi-v7a`.
- `landing/`: static pre-release page. `graphify-out/`: skip for routine context.

## Status and boundaries
- UI -> application/domain only; application -> domain ports only. The composition
  root injects platform adapters: unavailable engine stub, configured or explicit
  unavailable audio preparation, Windows microphone capture, and native model
  verification.
- Flow: UI -> `TranscriptionSessionController` -> `AudioCapture` start/stop ->
  `TranscriptionCoordinator` -> `AbstractEngineInterface`. Idle, recording,
  preparing, processing, completed, cancelled and error states are tested;
  progress and partial revisions forward.
- Windows capture requests 16 kHz mono PCM WAV and falls back to 48 kHz stereo for
  devices that reject it. Files live only under
  `<temp>/persian_transcriber/captures/<captureId>/capture.wav`; stopped captures
  are discarded after success, failure or cancellation. FFmpeg canonicalizes and
  validates the audio before inference.
- Native audio preparation is enabled only by explicit local configuration:
  `PERSIAN_TRANSCRIBER_FFMPEG_PATH` (absolute) and
  `PERSIAN_TRANSCRIBER_FFMPEG_SHA256` (exact digest), with no PATH search or
  download. The adapter verifies the binary, runs an offline capability
  self-test, converts `0:a:0` to PCM format 1 mono 16 kHz 16-bit WAV under
  `<temp>/persian_transcriber/jobs/<jobId>/prepared.wav`, and runs FFmpeg in a
  dedicated worker isolate with request-scoped cancellation and bounded stderr.
  Input protocols are restricted to `file`; cleanup is idempotent and job-scoped.
  A startup sweep removes job scopes older than 24 hours. Missing or invalid
  configuration reports a typed local error. See
  `client/lib/platform/audio/README.md`.
- Microphone permission denial, unavailable capture, busy capture, unsafe IDs,
  recorder start/stop failures and temp cleanup are covered by platform tests.
  Non-Windows and web captures report typed local errors; web preparation is
  explicitly unavailable.
- Engines remain unavailable stubs and show honest local errors. Model management
  is implemented natively: strict trusted-manifest parsing, streaming SHA-256
  verification of installed artifacts, resumable `.part` downloads with
  ETag/Last-Modified checks, cancellation and atomic promotion.
  `ModelManagementController` exposes typed states (not downloaded, downloading
  with progress/speed, verifying SHA-256, paused, ready, error, unavailable) and
  the Settings -> Model Management screen offers explicit download, pause,
  resume, retry and delete actions for the Fast/Balanced profiles. Initialization
  only reads local state; no download starts without a user action.
  `assets/models/manifest.json` pins the verified Fast (`ggml-base-q8_0.bin`,
  81,768,585 bytes) and Balanced (`ggml-small-q5_1.bin`, 190,085,487 bytes)
  artifacts at an immutable Hugging Face revision, so the controller resolves
  both profiles as not downloaded instead of `modelUnavailable`; web remains
  unavailable. See `client/lib/platform/models/README.md`.
- Native whisper.cpp inference runs through FFI behind the engine port and
  decodes the prepared
  `<temp>/persian_transcriber/jobs/<jobId>/prepared.wav` audio in a dedicated
  worker isolate. The library is enabled only by explicit local configuration
  (`PERSIAN_TRANSCRIBER_WHISPER_PATH` and
  `PERSIAN_TRANSCRIBER_WHISPER_SHA256`), is streamed through SHA-256 before
  loading, and its `whisper_full_params` layout is pinned to the whisper.cpp
  v1.8.2 ABI. A runtime check rejects a mismatched build rather than
  transcribing with the wrong offsets. See
  `client/lib/platform/whisper/README.md`.
- Next priority: run `client/tool/build_whisper_android.ps1` on a machine with
  an Android NDK, then build and pin desktop/iOS/macOS libraries. Android
  bundled-library discovery and deployed WASM remain unimplemented.


  # Persian Transcriber - Project Index & Status Handoff

## Current Status (Step 3: WIP)
- **Step 1 (Windows Microphone Capture):** Complete and verified. Uses `record_windows`, 16 kHz mono WAV.
- **Step 2 (Real Audio-Only FFmpeg Preparation):** Complete and verified. Strict RIFF/WAVE validation, SHA-256 toolchain verification, atomic rename, and 24-hour stale sweeps.
- **Step 3 (Bind whisper.cpp FFI):** In Progress / WIP. Typed FFI bindings pinned to the whisper.cpp v1.8.2 ABI, a long-lived worker isolate that owns the native context, SHA-256 library verification, a runtime ABI compatibility check, and 30-second decode windows with between-window cancellation. The manifest now pins verified Fast/Balanced GGML models; the Android build/probe pipeline exists but no built `libwhisper.so` is bundled yet.

## Verification Command
- `flutter test --no-pub` (Current baseline: 214 tests passing)
- `flutter analyze --no-pub`

