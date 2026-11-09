# Transcription application slice

`TranscriptionCoordinator` depends only on the canonical engine and the two domain
ports in `../domain/ports/`. Construct it with an engine, `AudioPreparation` and
`VerifiedModelAccess`. Native builds inject the trusted-manifest adapter from
`../../platform/models`; Windows microphone capture is injected separately into
the session controller through `AudioCapture`. Audio preparation and inference
adapters remain unavailable. No fake is wired into production; recording creates
a real managed capture, but with the bundled empty manifest a job still stops at
model resolution and reports `modelUnavailable`. Once a verified model is
configured, the opaque capture ID reaches the unavailable preparation adapter and
fails honestly.

## Port obligations

- `VerifiedModelAccess.resolveVerified` returns an exact compatible `ModelSpec`
  for the requested tier only after its local artifact has passed SHA-256
  verification against a trusted manifest. Missing/corrupt artifacts fail with
  `EngineFailureCode.modelUnavailable`. This slice does not download or hash
  models; the native infrastructure in `../../platform/models` implements
  manifest validation, resumable acquisition and verification behind the port.
- `AudioPreparation.prepare` accepts an opaque source ID and a unique job scope.
  It standardizes audio using the required minimal audio-only FFmpeg build, then
  returns ordered, non-overlapping, contiguous speech chunks. Each `PreparedAudio`
  describes one continuous interval from the original source; its `sourceOffset`
  includes any preceding removed silence. Never concatenate across a VAD gap into
  a single descriptor. An empty list means no speech. Audio IDs must be distinct
  within a batch; the coordinator freezes and validates the returned list.
- Both ports must observe `CancellationSignal`, signal their real worker/operation
  to stop, and settle their Future only after workers release resources. They may
  use `throwIfCancelled()` to report typed cancellation. Cancelling a Future/UI
  listener alone is insufficient. The coordinator joins operations rather than
  racing/abandoning them, so resources cannot be cleaned while preparation runs.
- `AudioPreparation.cleanup(jobId)` is idempotent and restricted to temporary
  artifacts registered under that exact scope, including partially prepared
  audio. It must be safe even if preparation never started. It must never delete
  source media, exports, transcripts, installed models or resumable downloads.
  Startup orphan recovery/cache expiry remain infrastructure responsibilities.

## Job semantics

`transcribe(jobId, sourceId, tier, options)` is single-subscription and starts on
listen. Stages are readiness -> verified model access -> audio preparation ->
model loading -> sequential chunk transcription -> cleanup. Silent input skips
model loading/inference. Model and inference progress use typed job wrappers;
overall inference progress is weighted by prepared speech duration, not silence.
When the engine's loading Future succeeds and its status confirms `ready`, the
coordinator emits a final model-progress fraction of 1 if the asynchronous model
stream has not delivered it yet. Failures and cancellation never synthesize it.

Each engine instance has one lease shared across coordinator instances in the
same isolate. The lease includes preparation and cleanup. Rejected jobs report
`busy` without disturbing the active job or invoking its ports. The composition
root must give coordinators exclusive access to their engine; unrelated direct
engine calls cannot participate in this application lease.

Engine job IDs and temporary scopes are generated internally and differ from the
public job ID. `JobSegment.segment` preserves the raw engine segment with relative
timestamps; `sourceStart`/`sourceEnd` map it to the original recording once. UI
state must upsert revisions by `JobSegment.key`, not append every partial. Keys
include the chunk index so segment IDs can repeat across chunks. Final segments
are immutable; invalid IDs, out-of-bounds timestamps, post-terminal events,
unresolved partials and missing completion are rejected. `JobCompleted.segments`
is an immutable, ordered snapshot with only the committed final revisions.

Failures are `EngineFailure` stream errors after cleanup, followed by closure;
platform exceptions are normalized without copying platform details. Normal
cancellation emits `JobCancelled` with committed segments only, discarding partial
revisions. Per-chunk completion becomes one job completion only after all chunks
and cleanup succeed. Cleanup failure reports an error instead of false success
or cancellation; a primary failure is preserved if cleanup also fails. A failed
cleanup adapter must retain/retry its orphan records during recovery.

`cancel(jobId)` is idempotent, targets only this coordinator's active matching job,
and waits for joined operations and temporary cleanup. During transcription it
calls and awaits the actual engine's `cancel(engineJobId)` and cancels the engine
subscription. Cancelling/pausing the outward subscription cannot orphan a worker;
subscription cancellation follows the same stop-and-cleanup path. Pausing applies
backpressure to engine consumption; model-progress samples may be dropped while
paused. Unknown/completed job IDs are harmless. Cancellation wins until the final
terminal decision; cleanup failures still surface through the stream/cancel Future.

Initialization/model loading lack independent cancellation in the existing engine
contract. If cancelled then, the coordinator waits for that operation to settle
before stopping the job and cleaning up; it never starts subsequent inference.
Actual adapters must obey their engine lifecycle and resource-release contracts.
Coordinator `dispose()` cancels its active job and rejects new work; engine lifetime
belongs to the composition root, so coordinator disposal does not dispose it.

## Functionality and validation

Orchestration, leases, event forwarding/replacement, timestamp mapping and cleanup
coordination are implemented and unit tested against controlled adapters. Windows
microphone capture is implemented behind `AudioCapture` with managed temporary
files, but real audio-only FFmpeg preparation, native FFI/WASM inference and
worker cancellation are still needed before end-to-end transcription. Trusted
local artifact resolution, resumable model downloads and verification now exist
natively; the bundled manifest intentionally has no released profile yet. No
database, server, network transcription or new platform engine implementation is
introduced.

Run `flutter test --no-pub test/domain test/application test/platform` for the
focused suite.
