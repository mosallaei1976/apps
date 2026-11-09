# Native audio capture and preparation

## Managed temporary layout

```text
<temp>/persian_transcriber/captures/<captureId>/capture.wav  microphone source
<temp>/persian_transcriber/jobs/<jobId>/prepared.wav         canonical 16 kHz mono PCM
```

Capture IDs and job IDs are opaque application values. Paths never cross the
domain ports. `FfmpegAudioPreparation` accepts only the strict identifier shape
`^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$`, so a job cannot escape its managed
directory. Cleanup is scoped to one job directory, is idempotent and never
deletes captures, models, transcripts or exports.

## Verified local FFmpeg only

There is no PATH lookup, package-manager discovery, download or bundled guess.
The composition root reads two environment variables:

```text
PERSIAN_TRANSCRIBER_FFMPEG_PATH=C:\absolute\path\to\ffmpeg.exe
PERSIAN_TRANSCRIBER_FFMPEG_SHA256=<64 lowercase hex characters>
```

Both must be set together. The path must be absolute. On first use the adapter
computes the binary's streaming SHA-256 and refuses to run it on a mismatch.
It then runs an offline capability self-test (synthetic 16 kHz mono source into
the PCM WAV encoder) before accepting work. The digest check and self-test are
cached for the worker's lifetime. If configuration is absent or invalid, the app
injects `UnavailableAudioPreparation` and reports a typed local error instead of
inventing a prepared file.

Conversion selects `0:a:0`, drops video/subtitle/data streams and metadata, and
writes PCM format 1, mono, 16,000 Hz, 16-bit WAV. The FFmpeg input protocol
whitelist is restricted to `file`; the adapter never passes a URL and never
opens a network connection. Stderr is retained only as a bounded tail for local
error messages.

## Worker and cleanup

FFmpeg runs in a dedicated worker isolate. Each request carries an opaque request
ID; cancellation is sent to that exact request, and stale cancellation requests
are harmless. Cancellation and timeouts terminate the process and wait for it to
exit before the Future settles. The output is written as `prepared.wav.part`,
validated with `WavFormat`, then atomically renamed to `prepared.wav`.

`FfmpegAudioPreparation.sweepStaleJobs()` removes job directories whose latest
file activity is older than 24 hours by default. The composition root runs it at
startup; failures are best effort and retried by a later sweep.
