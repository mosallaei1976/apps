# Persian Transcriber: context index

Repository root: apps/. Read `../AGENTS.md` first. The client UI is wired to the
application coordinator through Riverpod; `flutter analyze` is clean and all 52
client tests pass. Native inference, real audio preparation, model management and
persistence remain planned.

## Structure
- `client/lib/main.dart`: composition root and Riverpod provider overrides.
- `client/lib/features/transcriber/presentation/`: screen, session controller and
  providers; consumes the coordinator only.
- `client/lib/features/transcriber/application/`: coordinator, typed job events,
  engine leases, cancellation, chunk offsets and cleanup.
- `client/lib/features/transcriber/domain/`: canonical engine contract, DTOs,
  failures, and audio/model/cancellation ports.
- `client/lib/platform/`: conditional factory, unavailable Native/WASM engine
  stubs, temporary audio/model stubs, and composition helper.
- `client/test/`: domain/application contracts plus presentation smoke tests.
- `landing/`: static pre-release page. `graphify-out/`: skip for routine context.

## Status and boundaries
- UI -> application/domain only; application -> domain ports only. The composition
  root injects platform stubs.
- Flow: UI -> `TranscriptionSessionController` -> `TranscriptionCoordinator` ->
  `AbstractEngineInterface`. Idle, recording/preparing, processing, completed,
  cancelled and error states are tested; progress and partial revisions forward.
- Stub engines and unavailable audio/model adapters show honest local errors.
- Next priority: implement Windows native audio capture (or model management/
  manifest) per the PRD, then bind whisper.cpp FFI. No FFI or downloads exist yet.
