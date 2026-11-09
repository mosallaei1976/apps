# Local model management

This directory implements the native half of the model-acquisition contract in
PRD section 5. It does not bind `whisper.cpp`; an engine still receives only the
opaque `ModelSpec` produced here.

## Layout

```text
<application support>/models/<artifactId>.bin       verified installed artifact
<application support>/downloads/<artifactId>.part   resumable download
<application support>/downloads/<artifactId>.part.json
```

`ModelStorage` owns both directories. It never reads or deletes user source media,
transcripts, exports or other application files. Installed models and partial
downloads are deliberately separated: job-cache cleanup must not remove either.

## Trusted manifest

`assets/models/manifest.json` is the only trusted source of model identity. The
bundled file is intentionally empty until a real artifact has been pinned,
licensed, measured and tested with the selected engine build. Do not add an entry
from a guessed URL, size or hash.

Illustrative schema version 1 shape (every value below is a placeholder; the
bundled manifest must not contain an entry until it is real):

```json
{
  "schemaVersion": 1,
  "models": [
    {
      "id": "whisper-base-q5",
      "tier": "fast",
      "family": "base",
      "quantization": "q5_k",
      "version": "1.0.0",
      "byteLength": 1,
      "sha256": "<64 lowercase hex characters>",
      "source": "https://<pinned artifact URL>",
      "license": "<artifact license>",
      "engines": ["nativeFfi"]
    }
  ]
}
```

Rules enforced by `ModelManifest.parse`:

- `schemaVersion` must be `1`.
- `tier` is `fast` or `balanced`; `family` is `base` or `small`; fast must be
  Base-based and balanced must be Small-based.
- `quantization` is `int8` or `q5_k`. They are distinct formats, not aliases.
- `byteLength` is the exact artifact size and `sha256` the exact digest.
- `source` must be `https`.
- At most one artifact per `(tier, engine)` profile and unique artifact IDs.
- Unknown enum values and missing/invalid fields fail closed. Unknown object keys
  are ignored for forward compatibility.

`LocalVerifiedModelAccess` selects the profile for the requested tier and the
current engine, then re-verifies the installed file's exact size and SHA-256.
Missing, truncated or modified files report `modelUnavailable`; the engine is
never asked to load them. A manifest that is absent or invalid is also a typed
`modelUnavailable` failure.

## Download and promotion

`ModelDownloader` works with the transport-neutral `ModelDownloadTransport`
interface; `DartModelDownloadTransport` is the native `dart:io` adapter.

- A fresh response must be `200` with the exact manifest size (when provided).
- A resume sends `Range: bytes=<offset>-` plus `If-Range` from a strong ETag or
  Last-Modified value stored in `.part.json`.
- A valid `206` must start at the requested offset and report the exact manifest
  total size. A mismatched validator, invalid range or `416` restarts from zero.
- A `200` to a ranged request also restarts from zero, because the server either
  ignored the range or the artifact changed.
- The complete `.part` file is streamed through SHA-256 and compared with the
  manifest before the atomic promotion to `models/<artifactId>.bin`.
- A resumed file that fails verification is discarded and retried once from
  scratch. A corrupt fresh file is discarded and never promoted.
- Cancellation aborts the response body, preserves `.part` and `.part.json`, and
  reports `cancelled`. Calling `download` again resumes.
- Stale `.part`/metadata files older than seven days can be removed with
  `ModelStorage.sweepStaleDownloads()`.

Callers must not delete or replace an artifact while an engine is loading or
using it. The engine lease and UI flow that enforce that rule do not exist yet.

## Remaining work

- Pin and validate real Fast/Balanced artifacts, including licenses and exact
  sizes, before adding manifest entries.
- Measure verification time; resolution currently re-hashes the complete artifact
  on every job. Add a trusted, invalidated verification cache only if measurements
  justify it.
- Add a model-management UI with size, progress, pause/resume, retry, switching,
  deletion, cache usage and low-disk checks.
- Implement the browser IndexedDB/blob equivalent; web builds still use
  `UnavailableVerifiedModelAccess`.
- Run the startup sweep from the composition root once a job/cache lifecycle
  exists.
