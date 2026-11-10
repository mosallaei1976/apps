# Native whisper.cpp inference

This directory binds `whisper.cpp` in-process through `dart:ffi`. Work runs in a
dedicated long-lived worker isolate; the UI isolate only exchanges plain event
objects. No audio or transcript leaves the device, and no analytical or network
call is made from this code path.

## Verified local library only

There is no PATH lookup, package-manager discovery, download or bundled guess.
The composition root reads two environment variables:

```text
PERSIAN_TRANSCRIBER_WHISPER_PATH=C:\absolute\path\to\whisper.dll
PERSIAN_TRANSCRIBER_WHISPER_SHA256=<64 lowercase hex characters>
```

- The path must be absolute when supplied. If it is omitted, the digest-only
  form resolves the app-relative managed location
  `<application support>/whisper/whisper.dll`.
- A SHA-256 digest is always required. A half-configured environment is a
  `FormatException` at composition time, which becomes an honest unavailable
  engine instead of a guess.
- Before any symbol is resolved, the worker streams the file through SHA-256 and
  refuses to load it on a mismatch, an empty file or a path that is not a plain
  file.

Missing or invalid configuration produces a typed local error. Nothing is
downloaded to satisfy it.

## Pinned ABI

The bindings target the **whisper.cpp v1.8.2** x64 C ABI for
`whisper_full_params`. This is not cosmetic: `whisper.cpp` inserts fields in the
middle of the struct between releases. v1.8.1 added `carry_initial_prompt`,
`prompt_tokens` and `prompt_n_tokens` immediately before `language`, which
shifts every later field by 24 bytes. If a library with the older layout were
loaded with these bindings, `language` would land at the wrong offset and
`whisper.cpp` would fall back to its built-in default of `"en"` — silently
transcribing Persian as English.

To make that failure loud instead of silent, the worker calls
`WhisperBindings.assertCompatibleLayout()` right after loading. It reads the
documented default values written by
`whisper_full_default_params(WHISPER_SAMPLING_GREEDY)` through the declared
field offsets and rejects a mismatched build with an `unsupported` failure. The
check compares values only; it never dereferences a pointer, so a mismatched
library cannot crash it.

`client/test/platform/whisper_bindings_layout_test.dart` pins the expected byte
offsets (`language` at 104, the v1.8.1 prompt fields at 80/88/96, the decoding
tail at 264/272) and the minimum native size (304 bytes on x64). Update that
test deliberately whenever the target ABI changes.

## Android build pipeline

`client/tool/build_whisper_android.ps1` produces `libwhisper.so` for
`arm64-v8a` and `armeabi-v7a` from the pinned whisper.cpp tag `v1.8.2`
(commit `4979e04f5dcaccb36057e059bbaed8a2f5288315`). It requires an installed
Android NDK, CMake and Ninja; it never downloads a prebuilt library and never
runs during application startup or tests.

The script:

- clones or checks out the pinned commit and fails if `HEAD` differs;
- builds `libwhisper.so` with `BUILD_SHARED_LIBS=ON` for each ABI;
- compiles `client/tool/abi/whisper_layout_probe.c` against the v1.8.2
  `whisper.h` for each ABI, so a changed `whisper_full_params` offset fails the
  build instead of producing a silently wrong library;
- checks the ELF machine and required exported symbols;
- copies the libraries to `android/app/src/main/jniLibs/<abi>/libwhisper.so`
  and writes `whisper-artifacts.json` with exact sizes and SHA-256 digests.

`client/tool/verify_whisper_android.ps1` re-verifies the copied artifacts against
that metadata. The runtime still requires an explicit
`PERSIAN_TRANSCRIBER_WHISPER_PATH`/`PERSIAN_TRANSCRIBER_WHISPER_SHA256`
configuration on desktop; Android bundled-library discovery is a separate,
not-yet-implemented milestone.

## Audio input

Inference accepts only the canonical prepared file produced by the FFmpeg
adapter: PCM format 1, mono, 16,000 Hz, 16-bit, at
`<temp>/persian_transcriber/jobs/<jobId>/prepared.wav`. The worker re-validates
the container with `WavFormat` before reading samples and converts signed
16-bit little-endian PCM to normalized `float32` (`int16 / 32768`).

Long recordings are decoded in 30-second windows. `whisper_full` is a
synchronous native call, so cancellation is checked between windows rather than
mid-decode; a cancel request bounded by the current window finishes with
`WhisperInferenceCancelled` instead of a partial transcript. Segment
`t0`/`t1` are returned in centiseconds and converted to microseconds
(`value * 10000`), then clamped to the prepared audio duration.

## Remaining work

- Run the Android build pipeline on a machine with the NDK and record the
  resulting digests; build and pin desktop/iOS/macOS binaries separately.
- Decide whether to enable GPU or flash attention per platform; the current
  bindings round-trip the library defaults for `whisper_context_params`.
- Add an integration test against a small pinned model plus a known fixture
  once a licensed artifact is available.
- Evaluate a progress or abort callback so cancellation is not limited to
  window boundaries.
- Surface streaming partials. The request already carries `emitPartials`, but
  the worker currently emits only per-window final segments; live partial text
  would need a `new_segment_callback` or finer windows.
