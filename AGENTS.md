# AGENTS.md — Persian Transcriber

## Project identity

Persian Transcriber is a bilingual Persian/English, open-source,
privacy-first speech-to-text project created by Seyed Mohammad Mosallaei.

The planned clients are Android, iOS, Windows, macOS, and a PWA.
Native inference and browser inference have different implementations:
native bindings/FFI versus WebAssembly and Web Workers.

This repository is intended to be fully open source, not open-core.
Our own source code is intended for release under Apache-2.0. Add the
complete canonical LICENSE file and required third-party notices before
a public release. Check the license of every dependency and model
individually. Apache-2.0 does not itself grant trademark rights.

## Non-negotiable product rules

- Never send user audio or transcripts to a transcription server.
- Do not add analytics, telemetry, ad SDKs, tracking pixels, remote
  fonts, or third-party embeds to the landing page or client.
- A necessary download of the app or model is not the same as uploading
  user audio. Describe this distinction accurately.
- Say "offline after initial setup" when the app/model must first be
  downloaded. Do not describe visiting the website as air-gapped.
- Do not claim that open-source code, Apache-2.0, or local processing
  alone guarantees security.
- Do not publish unmeasured claims about accuracy, speed, RAM usage,
  subtitle timing, or supported media formats.
- Do not call standard multilingual Whisper weights a custom
  Persian-trained model.
- Do not assume a native binary or Dart FFI runs inside a browser.
- Decode/prepare audio into the required format before feeding
  components that need it; do not present VAD as universally preceding
  audio decoding.
- Do not treat legacy FFmpegKit as an approved maintained dependency.

## Landing-page scope

The landing page lives in apps/landing and uses plain HTML, CSS, and
vanilla JavaScript for the initial scaffold. Avoid adding a framework
or build pipeline without a concrete need.

Required visible areas:
- Header with Persian/English switch
- Hero with Google Play, App Store, and web-app/PWA CTAs
- Concise privacy and architecture explanations
- About/creator attribution and contact path
- A clear statement of availability and browser limitations

The initial page is a pre-release page. Do not invent store listings,
a working /app route, a GitHub repository URL, wallet addresses, or
payment-gateway URLs.

Store CTAs may show a "Coming soon" information dialog. Do not collect
email addresses until a self-hosted submission endpoint, consent text,
storage/retention policy, and privacy-policy update actually exist.

The web-app CTA must remain disabled until a real deployed app URL is
configured. Once available, the CTA should open the app; installation
instructions and browser-specific install behavior belong in a
subsequent, tested implementation.

Only publish BTC/USDT addresses after the owner confirms the exact
address and network. Only publish GitHub Sponsors and rial-gateway
links after those destinations exist.

## Internationalization and accessibility

- Persian is the initial language; English is selectable.
- Update the root HTML `lang` and `dir` attributes together.
- Translate visible text, page title, description, and control labels.
- Use CSS logical properties rather than duplicating RTL/LTR layouts.
- Preserve keyboard navigation, visible focus, semantic landmarks,
  accessible dialogs, and reduced-motion preferences.
- Do not put untrusted strings into `innerHTML`; use `textContent`.
- Store language preference locally when storage is available.

## Implementation discipline

- Work in small, reviewable changes; preserve the agreed product scope.
- Do not add a PWA manifest or service worker merely to make the
  landing page appear installable. The actual app needs its own tested
  offline and model-cache strategy.
- Keep the landing page functional without external CDNs.
- Before completing a change, test both languages, mobile layout,
  keyboard navigation, all three CTA states, and missing-link behavior.
- Document unresolved integration points instead of masking them with
  placeholder URLs or nonfunctional submit buttons.

## Current client architecture baseline

The Flutter client is organized around a presentation / application / domain / platform boundary. UI code calls the transcription session controller and coordinator; domain contracts define engine and audio/model ports; the composition root injects platform adapters. Keep platform APIs, native handles, and infrastructure out of presentation and domain code. The coordinator owns job sequencing, engine leases, progress/events, cancellation, and cleanup. Microphone capture completes and stops before the resulting opaque capture ID is submitted as a transcription job.

The current audio path includes Windows microphone capture, strict RIFF/WAVE validation, and native FFmpeg preparation behind audio ports. FFmpeg is enabled only with explicit local configuration (`PERSIAN_TRANSCRIBER_FFMPEG_PATH` and `PERSIAN_TRANSCRIBER_FFMPEG_SHA256`); there is no PATH lookup or automatic binary download. Preparation produces 16 kHz, mono, signed 16-bit PCM WAV in a job-scoped temporary location. Missing/invalid configuration and unsupported platform paths return typed local errors. Temporary job data is cleaned on success, error, or cancellation; stale job scopes older than 24 hours are swept. Do not imply FFmpeg or microphone support is universal across platforms.

## Model management: implemented baseline and guardrails

Native model management exists behind the verified-model port in `client/lib/platform/models/`. It includes strict trusted-manifest parsing, streaming SHA-256 verification of installed artifacts, resumable `.part` downloads with ETag/Last-Modified identity checks, cancellation, and atomic promotion after verification. Keep model storage/download concerns separate from inference and job-temporary storage. Incomplete or unverified artifacts must never be loadable; preserve typed failures and explicit local behavior when a model is unavailable. See `client/lib/platform/models/README.md` for adapter details.

`assets/models/manifest.json` is intentionally empty until a real model artifact is pinned. Consequently, model resolution currently reports `modelUnavailable`: model-management infrastructure is present, but there are no distributable/usable model weights in the baseline. Do not describe model downloads or transcription with real weights as currently available. Before adding an artifact, validate and pin its source and license, exact version/quantization, engine compatibility, size, and SHA-256 in the trusted manifest. The product profiles remain Fast/Low-Resource (quantized multilingual Base) and Precision/Balanced (quantized multilingual Small); approximate size targets are not verified artifact sizes or RAM/performance guarantees.

## Inference bridge and FFI baseline

The application uses the canonical engine abstraction in the domain and the coordinator consumes it through an injected engine lease. Native and web engine implementations are currently unavailable stubs; no working `whisper.cpp` Dart FFI inference or deployed WASM/Web Worker inference is present. Do not treat mock/canned output or a stub as a functioning transcription engine, and do not claim browser readiness.

Next inference milestone: implement the native `whisper.cpp` bridge through Dart FFI, invoked and owned by a Dart Worker Isolate, consuming the already-prepared job WAV and a verified compatible model. Keep FFI pointers, native lifecycle, and platform imports inside the native adapter; use platform-safe conditional factories so browser builds never import `dart:ffi`. The engine contract must cover readiness/capabilities, model load/unload, progress and timestamped partial/final results, cancellation, typed failures, and disposal. Audio preparation, model acquisition, persistence, and export remain separate services rather than responsibilities of the engine bridge.

A web engine is a separate, gated future implementation: WASM plus Web Workers, and only after deployment passes secure-context, COOP/COEP, `crossOriginIsolated`, `SharedArrayBuffer`, multithreaded-worker, asset-loading, offline, and storage validation. Never assume Dart FFI or a native binary can run in the browser; unsupported platforms must return clear local errors, with no server fallback.

## Baseline verification and status discipline

The current context index reports `flutter analyze` clean and 155 client tests passing. Use the repository's current verification commands (`flutter analyze --no-pub` and `flutter test --no-pub`) when changing client code, and report newly observed results rather than assuming the baseline still holds. Update `INDEX.md` when implementation status changes, and keep implemented capabilities distinct from roadmap contracts and PRD targets.

