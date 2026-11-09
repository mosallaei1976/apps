# Engine domain contract

The canonical contract is `engine/abstract_engine_interface.dart`, with immutable
DTOs in `engine/engine_types.dart` and failures in `engine/engine_failure.dart`.
The former root `abstract_engine_interface.dart` only re-exports that contract for
import compatibility; it does not preserve the superseded API or define another
interface. The domain has no Flutter, filesystem, FFI, WASM or platform imports.

## Inputs and responsibilities

`initialize()` initializes the engine runtime; `loadModel(ModelSpec)` separately
loads an already acquired, verified artifact identified by an opaque `artifactId`.
Fast is quantized multilingual Base (~80 MB); balanced is quantized multilingual
Small (~200 MB), with INT8 and q5_k represented as distinct quantizations. Sizes
are approximate product targets, not manifest sizes or RAM estimates. Artifact
resolution, compatibility, download/resume and SHA-256 verification stay in
infrastructure; model loading must never start a download.

`PreparedAudio.audioId` identifies locally prepared 16kHz signed 16-bit mono PCM
WAV in an injected audio repository. IDs are opaque domain identifiers, never file
paths, URLs, byte buffers or platform handles. Audio preparation, VAD, file/blob
ownership and temporary cache cleanup belong to application/infrastructure
services. The engine neither preprocesses nor deletes the source. `duration` is
strictly positive; `sourceOffset` is nonnegative and locates the prepared chunk
on the original recording timeline. A silence-only input can complete without
segments; zero-duration input must be filtered before engine invocation.

## Lifecycle and status

- Start `uninitialized`. Successful `initialize()` ends `initialized` (no model).
  It is idempotent when already initialized/ready. Initialization failure throws
  `EngineFailure` and sets `failed`; retry initialization or dispose afterward.
- `loadModel` requires initialized/ready state and no active operation. Replacing
  a model releases the old one, enters `loadingModel`, emits progress for that
  model ID, then enters `ready`. Failure throws a typed failure, releases partial
  resources and returns to `initialized` without a model. `unloadModel()` releases
  a loaded model and returns to `initialized`; without a model it is a no-op.
- Lifecycle mutation during loading/transcription/cancellation rejects with `busy`;
  it must not disrupt the active operation. Transcription requires `ready`.
- `status` is the current snapshot. `statusChanges` and `modelLoadProgress` are
  broadcast, do not replay history, and do not carry errors. Update the snapshot
  before notifying subscribers; emit only changes. Progress fractions are null
  when unknown or finite in [0, 1], monotonic within one operation when known.
  Successful model loading ends with fraction 1; failure must not emit fake 100%.

## Job streams, segments and failures

- Each `transcribe` result is a single-subscription stream. Admission happens on
  listen, not at stream construction. Accept at most one active job per engine,
  including its cleanup; reject concurrent requests with a `busy` stream error,
  without queueing, cancelling or changing the active job's status. Require a
  nonempty job ID; callers supply unique IDs for the engine lifetime to prevent
  stale cancellation requests from targeting another job.
- All events identify the admitted job. Enter `transcribing` on admission.
  Partial segments replace earlier revisions of the same `segmentId`; never
  append each revision as new text. A segment with `isFinal: true` commits that
  segment and must never be revised or emitted again. Different segment IDs are
  independent. `emitPartials: false` suppresses partials, not final segments.
- Segment `start`/`end` are relative to the supplied prepared audio, with
  `0 <= start <= end <= audio.duration`. `sourceStart(audio)` and
  `sourceEnd(audio)` validate the upper bound and add `audio.sourceOffset` once.
  Consumers must use the matching job's audio descriptor and must not add the
  offset again. Confidence is null if unavailable or finite in [0, 1].
- Normal success emits all committed segments, optional progress 1, then exactly
  one `TranscriptionCompleted`, then closes. No unresolved partial may remain on
  success. No events follow a terminal event. Completion is separate from final
  segments because a job can have many segments or no speech at all.
- Expected failures use exactly one `EngineFailure` stream error followed by
  closure, without completed/cancelled events. Translate backend errors to typed
  codes; never expose raw platform exceptions or handles. Rejected jobs do not
  alter the active engine. After accepted-job failure and cleanup, return to
  `ready` if the model remains usable, otherwise `initialized`; irrecoverable
  runtime failure sets `failed`. Recoverable I/O/timeout errors retain the model.

## Cancellation and disposal

- `cancel(jobId)` cancels only the matching active transcription. Unknown,
  completed and disposed job requests are harmless. Repeated cancellation waits
  for the same cleanup. Enter `cancelling`, signal worker cancellation promptly,
  await resource release, emit one `TranscriptionCancelled`, and close the stream.
  Return to `ready` once cleanup finishes. Cancellation is a normal terminal
  event, not a stream error; retain committed segments and discard partials.
- Cancelling the stream subscription must also cancel its matching job and wait
  for cleanup before admitting another. The cancelled listener cannot receive a
  terminal event, so do not depend on it for engine cleanup. Pause must not permit
  unbounded buffering; implementations must apply worker backpressure.
- `dispose()` is idempotent, rejects new work immediately, cancels any active
  job, awaits in-flight model/runtime initialization and cleanup, releases model
  and engine resources, enters `disposed`, then closes status/progress streams.
  If disposal interrupts initialization/loading, that Future rejects with
  `disposed`. If it interrupts transcription, cancellation semantics apply.
  All later operations except `dispose` and `cancel` reject with `disposed`;
  transcription reports that code through its stream. Snapshot reads remain valid.

## Scaffold status and migration

Factories now return this contract. NativeFfiEngine and WasmWebWorkerEngine remain
explicitly unavailable stubs: initialize throws `unsupported`, load/transcribe
reject with `notReady`, and neither reads audio nor fabricates inference output.
The UI records through the injected `AudioCapture` port, then hands the opaque
capture ID to the application coordinator for preparation and inference. Windows
microphone capture and native FFmpeg preparation are implemented; real FFI/WASM
workers and their cancellation/backpressure conformance remain implementation
work. See `../application/README.md` and `../../platform/audio/README.md`. Native
model infrastructure validates a trusted manifest, verifies installed artifacts
with streaming SHA-256, and supports resumable downloads with atomic promotion
(`../../platform/models/README.md`). The bundled manifest is empty until a real
artifact is pinned. The `cancelled` failure code is available for cooperative
port cancellation; engine transcription cancellation remains a normal terminal
event. Domain tests use a deterministic in-memory fixture to specify successful
job, concurrency and cancellation behavior; they do not validate native
inference or deployed WASM readiness.
