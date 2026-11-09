# Persian Transcriber: context index

Repository root: apps/. Read `../AGENTS.md` first. The client UI is wired to the
application coordinator through Riverpod; `flutter analyze` is clean and all 82
client tests pass. Native model management now exists behind the verified-model
port. Native inference, real audio preparation and persistence remain planned.

## Structure
- `client/lib/main.dart`: composition root and Riverpod provider overrides.
- `client/lib/features/transcriber/presentation/`: screen, session controller and
  providers; consumes the coordinator only.
- `client/lib/features/transcriber/application/`: coordinator, typed job events,
  engine leases, cancellation, chunk offsets and cleanup.
- `client/lib/features/transcriber/domain/`: canonical engine contract, DTOs,
  failures, and audio/model/cancellation ports.
- `client/lib/platform/`: conditional factories, unavailable Native/WASM engine
  stubs, temporary audio stub, model manifest/storage/download infrastructure,
  and composition helpers.
- `client/test/`: domain/application contracts, model infrastructure tests and
  presentation smoke tests.
- `landing/`: static pre-release page. `graphify-out/`: skip for routine context.

## Status and boundaries
- UI -> application/domain only; application -> domain ports only. The composition
  root injects platform adapters: unavailable engine/audio stubs and native model
  verification.
- Flow: UI -> `TranscriptionSessionController` -> `TranscriptionCoordinator` ->
  `AbstractEngineInterface`. Idle, recording/preparing, processing, completed,
  cancelled and error states are tested; progress and partial revisions forward.
- Stub engines and the unavailable audio adapter show honest local errors.
- Model management is implemented natively: strict trusted-manifest parsing,
  streaming SHA-256 verification of installed artifacts, resumable `.part`
  downloads with ETag/Last-Modified checks, cancellation and atomic promotion.
  `assets/models/manifest.json` is intentionally empty until a real artifact is
  pinned, so resolution reports `modelUnavailable`; web remains unavailable.
  See `client/lib/platform/models/README.md`.
- Next priority: implement Windows native audio capture and the audio-only FFmpeg
  preparation path, then bind whisper.cpp FFI. Pin real Fast/Balanced artifacts
  into the manifest only after license, size, hash and engine compatibility are
  validated. No FFI or deployed WASM exists yet.
