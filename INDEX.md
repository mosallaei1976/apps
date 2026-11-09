# Persian Transcriber: context index

Repository root: apps/. Read `../AGENTS.md` first. The client UI is wired to the
application coordinator through Riverpod; `flutter analyze` is clean and all 155
client tests pass. Native model management exists behind the verified-model port;
Windows microphone capture and native FFmpeg audio preparation exist behind the
audio ports. Native inference and persistence remain planned.

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
  `assets/models/manifest.json` is intentionally empty until a real artifact is
  pinned, so resolution reports `modelUnavailable`; web remains unavailable. See
  `client/lib/platform/models/README.md`.
- Next priority: bind whisper.cpp FFI to the prepared
  `<temp>/persian_transcriber/jobs/<jobId>/prepared.wav` audio. Pin real
  Fast/Balanced artifacts into the manifest only after license, size, hash and
  engine compatibility are validated. No FFI or deployed WASM exists yet.
