Here is the complete, modular UI/UX layout and component architecture specification for **Persian Transcriber**, drafted in clear technical English.

---

# UI/UX & Component Architecture Specification

Architecture alignment: PRD v1.1 (2026-11-05) governs platform readiness, model artifacts, and resource lifecycle. Desktop/mobile are primary; Web/PWA is secondary and gated by validated cross-origin isolation and WASM workers. All inference uses the `AbstractEngineInterface` bridge. The PRD's `AbstractEngine` label refers to this same contract, not a second interface. Section 6 defines module boundaries and the transition from the current scaffold.

## 1. Design System Foundations

### 1.1 Bidirectional Layout Engine (RTL / LTR)
The marketing landing page uses a global direction provider (`dir="rtl"` for Persian, `dir="ltr"` for English). The transcription client's application shell is strictly RTL in every locale, including settings, navigation, dialogs, and transcript editing; isolate LTR technical values within that layout.
* **Typography:** 
  * Primary (FA & EN): `Vazirmatn` (Weights: 400 Regular, 500 Medium, 600 SemiBold, 700 Bold), bundled and registered natively in Flutter and served locally on web; no remote font requests.
  * Monospace (Code, Model specs, Hashes): `JetBrains Mono` or `Fira Code`.
* **Spatial System:** CSS logical properties (`margin-inline-start`, `padding-inline-end`, `inset-inline-start`) ensure fluid layout mirroring without stylesheet duplication.
* **Palette:**
  * Background: Surface Neutral (`#0F172A` Dark / `#F8FAFC` Light).
  * Container / Cards: Raised Neutral (`#1E293B` Dark / `#FFFFFF` Light) with fine borders (`#334155` / `#E2E8F0`).
  * Primary Accent: Deep Persian Indigo (`#4F46E5`).
  * Secondary Accent: Cyan / Mint (`#06B6D4` / `#10B981`) for on-device and privacy-positive status signals.
  * Muted / Meta: Slate (`#64748B` / `#94A3B8`).

---

## 2. Landing Page Component Breakdown

```
LandingPage (Root Layout)
├── StickyHeader
│   ├── BrandIdentity (Logo + Product Name)
│   ├── NavigationMenu
│   ├── LanguageSwitcher (FA / EN)
│   └── GitHubRepoButton
│
├── HeroSection
│   ├── HeroCopy (Value Proposition + Technical Subtitle)
│   ├── PrimaryCTAButtonGroup
│   │   ├── StoreButton (Google Play — Badge: "Coming Soon")
│   │   ├── StoreButton (App Store — Badge: "Coming Soon")
│   │   └── PWAInstallButton (Web App — Disabled until deployment readiness passes)
│   ├── ReleaseInterestForm (Primary pre-release goal; gated by signup infrastructure)
│   └── AppMockupPreview (Visual transcription player)
│
├── TrustMetricsBar
│   └── 4x TrustCard (Offline after initial setup, Zero Telemetry, Apache-2.0, Zero Trackers)
│
├── ArchitectureSection
│   ├── PipelineVisualizer (Ingestion -> FFmpeg -> optional VAD -> AbstractEngineInterface -> Local DB)
│   └── PlatformMatrixTab (Native FFI vs. WebAssembly comparison)
│
├── FeaturesGrid
│   └── FeatureCard (File Ingestion, Mic Record, SRT/VTT Export, Local Search)
│
├── WebLimitationsAdvisory (Technical notice: Browser RAM limits vs. Native)
│
├── EnterpriseAndSponsorsSection
│   ├── ArchitectBioCard (Seyed Mohammad Mosallaei — Software Architect)
│   ├── DonationWidget (GitHub Sponsors, BTC/USDT Wallets, Local Rial Link)
│   └── EnterpriseInquiryCard (Contact Form + Direct Telegram `@msli1976`)
│
├── NotificationModal (Triggered by Play Store / App Store CTAs)
└── Footer
    ├── CopyrightNotice
    ├── LegalNotice (Apache-2.0, Disclaimers)
    └── FooterLinks (GitHub Repo, Issues, Documentation)
```

---

## 3. Detailed Component Specifications

### 3.1 `StickyHeader`
* **Properties / State:** `currentLang: 'fa' | 'en'`, `isScrolled: boolean`.
* **Elements:**
  * `BrandIdentity`: Vector waveform icon paired with the text mark `Persian Transcriber`.
  * `NavigationMenu`: Jump-links (`#features`, `#architecture`, `#enterprise`, `#about`). Hidden on small screens behind a slide-over mobile drawer.
  * `LanguageSwitcher`: Toggle button toggling `locale` and document root `dir`.
  * `GitHubRepoButton`: Static button linking directly to the Apache-2.0 repository. Zero external third-party tracking scripts.

### 3.2 `HeroSection` & `PrimaryCTAButtonGroup`
* **Copy Block:**
  * Title (FA): گفتار فارسی را به متن تبدیل کنید؛ روی دستگاه خودتان.
  * Title (EN): Transcribe Persian Speech to Text; 100% On-Device.
  * Subtitle (FA/EN): Explicit mention of quantized Whisper models, local inference, and zero audio transmission.
* **Component `PrimaryCTAButtonGroup` (3 Target Slots):**
  1. `StoreButton [Google Play]`:
     * State: Disabled / Informational.
     * Visual Badge: Floating pill label `Coming Soon` / `به‌زودی`.
     * Action: Opens release information (target: Google Play); email signup is available only when Section 3.3's prerequisites pass.
  2. `StoreButton [App Store]`:
     * State: Disabled / Informational.
     * Visual Badge: Floating pill label `Coming Soon` / `به‌زودی`.
     * Action: Opens release information (target: App Store); email signup is available only when Section 3.3's prerequisites pass.
  3. `PWAInstallButton [Web App]`:
     * State: Disabled with an accessible explanation until the PRD's deployed WASM readiness and app validation gates pass and a real app URL exists.
     * Action after activation: Open the configured app URL; offer installation instructions only after browser-specific testing. Do not invent an `/app` destination or make the landing page installable.
     * Readiness: The app server must return `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp`. Validate a secure context, `crossOriginIsolated`, `SharedArrayBuffer`, multithreaded WASM/Web Workers, and compatible asset loading before implementing/releasing the secondary web target.

### 3.3 `NotificationModal`
* **Purpose:** The landing page prioritizes optional email interest collection until the WASM environment is fully validated, without external mailing-list trackers.
* **Fields when enabled:** Release interest (including Web/PWA), email address, explicit consent, Submit, and Dismiss controls; accessible validation, success, and failure states.
* **Activation gate:** A working self-hosted endpoint, consent text, published retention/deletion policy, and updated privacy policy must exist before collecting email, consistent with `AGENTS.md`. Until then, show signup-unavailable/release information without a nonfunctional submit control; link to releases only if a real URL exists. Explain that opt-in email submission uses the network while audio and transcripts remain local.

### 3.4 `TrustMetricsBar`
A horizontal 4-column responsive grid containing minimal vector badges:
* **No Cloud Processing:** Audio and transcripts remain on-device, including local files and database storage.
* **Zero Telemetry:** No analytics scripts, no tracking pixels, zero phone-home calls.
* **100% Open Source:** Released entirely under the Apache-2.0 license.
* **Offline-Ready:** Offline after initial app/model setup and validation of required local assets.

### 3.5 `ArchitectureSection` (`PipelineVisualizer`)
A technical, high-credibility visual diagram showing the audio ingestion stages:
1. `Audio Ingestion`: Microphone stream or file; advertise only formats validated against the selected audio-only build.
2. `Preprocessing`: All inputs pass through a minimal audio-only FFmpeg build to 16 kHz, signed 16-bit mono PCM WAV (`pcm_s16le`), then optional Silero VAD with original timeline offsets preserved. Disable video processing/encoding and network protocols; container audio extraction requires explicit validation.
3. `Inference Engine`: UI -> application logic -> injected `AbstractEngineInterface` -> `NativeFfiEngine` (`whisper.cpp` + Dart FFI) or `WasmWebWorkerEngine` (WASM + Web Workers). Keep platform imports and handles inside adapters. The shared contract covers readiness, model lifecycle, transcription progress/results, cancellation, typed failures, and disposal.
4. `Background Execution`: Native heavy preprocessing, VAD, hashing/loading, and inference must use Dart Worker Isolates. Browser equivalents use Web Workers, including FFmpeg WASM. Keep the UI responsive through bounded jobs, progress events, and cancellation.
5. `Local Persistence`: Native Isar / browser IndexedDB behind a repository contract for jobs, transcript segments/edits, settings, and model/download metadata. Store large binaries as managed files/blobs, not database records.
6. `Export Pipeline`: Plaintext (`TXT`), SubRip (`SRT`), WebVTT (`VTT`); retained exports and transcripts live outside job caches.
7. `Resource Lifecycle`: Per-job audio intermediates use `TemporaryDirectory` on native and managed temporary blobs/worker storage on web. Clean automatically after completion/persistence, failure, or cancellation. Sweep interrupted-job orphans and inactive files older than 24 hours at startup and before new jobs; skip active jobs and retry failed deletions. Check disk/quota before work and offer clear-cache. Keep installed models persistent and resumable downloads separate; partial downloads expire after 7 inactive days or explicit cancellation/deletion/integrity failure. Never delete original media or retained outputs during cache cleanup.

### 3.6 `WebLimitationsAdvisory`
A transparent, engineer-grade callout card explaining browser sandbox limits:
* Highlights that the Web (PWA) version operates inside the browser's WASM memory sandbox.
* Publish supported browsers, model limits, and audio-duration guidance only after measurement and the PRD readiness gate; do not promise an untested duration threshold.
* Points mobile browser users to the upcoming Native builds for intensive workloads.

### 3.7 `EnterpriseAndSponsorsSection`
Split into two balanced visual columns:

#### Column A: Sponsorship & Personal Leadership
* Architect profile: **Seyed Mohammad Mosallaei** — Software Architect.
* Mission statement regarding community-owned Persian language tooling.
* Donation mechanisms:
  * International: GitHub Sponsors link.
  * Cryptocurrency: Dedicated copy-to-clipboard cards for Bitcoin (BTC) and Tether (USDT - TRC20) with QR code modals.
  * Local Iran: Direct Rial gateway link (ZarinPal / Remit).

#### Column B: Custom Enterprise Deployments (B2B)
* Focus areas: On-premise air-gapped transcription servers, specialized acoustic vocabularies (legal, medical, corporate), and customized internal desktop suites.
* Quick Contact Elements:
  * Direct Telegram Link: Dedicated button routing to `@msli1976`.
  * Embedded Lightweight Form: Name, Corporate Email / Phone, Inquiry Scope, Submit.

### 3.8 `Footer`
* Strict Apache-2.0 declaration.
* Disclaimer: Whisper is an open model architecture created by OpenAI; `Persian Transcriber` is an independent, community-driven on-device implementation.
* Direct textual links to repository root, Issue tracker, Architecture docs, and Security disclosures.

---

## 4. In-App View Specifications (The 3 Core App Views)

To maintain absolute parity between landing claims and app UX, these three core views inside the client must share the exact same technical taxonomy:

### 4.1 View: `AboutScreen`
* Displays running client version, active Git commit hash, and engine build target (`Native-FFI` or `Wasm-Worker`).
* Author attribution: Seyed Mohammad Mosallaei.
* Upstream credits: `whisper.cpp` (Georgi Gerganov), `Silero VAD`, `FFmpeg`.
* License details: Apache License 2.0 full text link.
* Enterprise assistance & sponsorship channels mirroring the landing page.

### 4.2 View: `SettingsScreen`
* **Locale Setting:** Explicit toggle between Persian and English (overrides OS default).
* **Inference Model Selection:**
  * `Fast / Low-Resource`: Quantized multilingual Base-based artifact, approximately 80 MB download target; optimized for speed and lower-resource devices.
  * `Precision / Balanced`: Quantized multilingual Small-based artifact, approximately 200 MB download target, using a validated INT8 or `q5_k` artifact; intended for better conversational Persian/slang accuracy, subject to evaluation.
  * These are approximate artifact targets, not RAM figures or interchangeable quantization formats. Show exact released sizes and capabilities from the trusted model manifest; validate compatibility with each engine.
  * Storage management: On-demand download, progress/cancel/resume with artifact identity checks, full SHA-256 verification before activation, safe retries, switching, and deletion. Never load incomplete/corrupt artifacts. Explain the separate 7-day inactive partial-download retention policy.
* **VAD Sensitivity:** High, Medium, Low, or Disabled (forces full-length transcription).
* **Local Data Hygiene:** Single-click "Purge All Transcriptions" clears transcription records and owned transcript artifacts in local Isar / IndexedDB while preserving settings and model/download metadata.
* **Cache Management:** Show temporary cache usage and clear-cache without deleting active jobs, installed models, retained downloads, original media, or exports.

### 4.3 View: `PrivacyPolicyScreen`
* Formatted in clean, accessible legal-technical English and Persian.
* Explicit doctrine clauses:
  1. **Local Transcription:** Audio, transcripts, and transcription metadata stay on-device; no telemetry or server transcription. App/model downloads require initial network access. Optional landing signup sends only email, release interest, and necessary consent data to the disclosed self-hosted endpoint after its privacy prerequisites pass.
  2. **No Analytics:** No unique device fingerprinting, advertising SDKs, or session replay trackers exist within the binary.
  3. **Data Sovereignty:** Model weights downloaded by the user are stored locally in the application sandbox. The user maintains sole ownership and deletion rights over generated files.

---

## 5. Responsive Breakpoints & State Flow

| Viewport | Breakpoint | Header Layout | Hero Layout | Store Buttons |
|---|---|---|---|---|
| **Mobile** | `< 640px` | Brand + Lang Switcher + Drawer Menu | Stacked vertically | Full-width vertical stack |
| **Tablet** | `640px - 1024px` | Standard bar, compact links | 2-row layout | 3-column inline row |
| **Desktop**| `> 1024px` | Full nav bar + GitHub button | 2-column split (Copy left/right depending on RTL, Mockup opposite) | 3-column horizontal cluster |

---

## 6. Platform Bridge and Module Contracts

### 6.1 Boundaries and Dependency Direction

The target client structure keeps feature modules under `apps/client/lib/features/transcriber/` and platform composition under `apps/client/lib/platform/`. These are architectural requirements; planned modules are not claims of implemented functionality.

| Module | Owns | Allowed dependencies |
|---|---|---|
| Presentation (`presentation/`) | RTL views, accessible controls, view state, progress and error display | Application commands/state and domain abstractions; no concrete engine, FFmpeg, database, FFI, or worker APIs |
| Application (`application/`, planned) | Job orchestration, cancellation, pipeline sequencing and cleanup coordination | Domain entities and ports only; implementations are injected |
| Domain (`domain/`) | `AbstractEngineInterface`, transcript entities, typed events/errors and preprocessing, persistence, model-storage and cache ports | Platform-neutral Dart types; no Flutter, `dart:ffi`, browser APIs, database SDKs, or infrastructure imports |
| Infrastructure (`infrastructure/`, planned) | Audio-only FFmpeg adapters, model downloads/integrity, Isar/IndexedDB repositories, temporary-file lifecycle | Domain contracts and platform services; never presentation |
| Platform bridges (`lib/platform/`) | `NativeFfiEngine`, `WasmWebWorkerEngine`, worker ownership and platform factory | Implement domain contracts; platform-safe conditional imports keep native code out of browser builds |

The composition root wires concrete adapters into application services; views receive abstractions rather than choosing implementations. The engine bridge owns inference only: audio preparation, model acquisition, persistence, and export remain separate services. Use platform-neutral model/audio references and transcript events across boundaries; keep native pointers, worker handles, filesystem paths, and browser blob handles inside adapters.

### 6.2 Engine and Worker Contract

`AbstractEngineInterface` must support readiness/capabilities, model load/unload, transcription with progress and partial/final timestamped segments, cancellation, typed failures, and disposal. `NativeFfiEngine` runs `whisper.cpp` via Dart FFI in Dart Worker Isolates. `WasmWebWorkerEngine` delegates WASM inference to Web Workers after the deployment readiness gate. Heavy preprocessing, VAD, hashing, and model loading also execute off the UI thread using the appropriate platform workers.

Bound queued work and audio buffers, preserve job identifiers and original timeline offsets, and propagate cancellation through preprocessing and inference. Release handles before cleanup on success, error, cancellation, and disposal. Both implementations must pass shared contract checks; unsupported capabilities surface explicit local errors without server fallback.

### 6.3 Model and Audio Resource Contracts

Expose exactly the two product profiles: Fast/Low-Resource (quantized multilingual Base, ~80 MB) and Precision/Balanced (quantized multilingual Small, ~200 MB, validated INT8 or `q5_k`). Sizes are download targets; publish exact artifact bytes and measured device limits. Pin quantization, engine compatibility, version, source/license, and SHA-256 in a trusted manifest. On-demand downloads must resume safely after interruption, verify artifact identity and the complete SHA-256, and promote verified files atomically before loading.

Every input follows audio-only minimal FFmpeg -> 16kHz, signed 16-bit mono PCM WAV -> optional VAD -> engine -> local persistence/export. FFmpeg must omit video processing/encoding and network protocols; support container audio extraction only when tested. Native intermediates belong in per-job `TemporaryDirectory` folders, with equivalent temporary blob/worker storage on web. Finalization removes them after persistence, failure, or cancellation; startup and pre-job recovery remove orphaned caches and inactive intermediates older than 24 hours while preserving active jobs. Retry deletion failures and check free space/browser quota before work.

Keep verified models and retained exports/transcripts outside temporary caches. Resumable partial downloads have their own managed area and survive job cleanup; delete them on explicit cancellation/deletion, integrity failure, or 7 days of inactivity. Clear-cache must preserve active jobs, installed models, retained downloads, original media, and final outputs.

### 6.4 Current Scaffold and Lightweight Context

The current domain contract is `TranscriberEngine` in `apps/client/lib/features/transcriber/domain/transcriber_engine.dart`. `apps/client/lib/platform/engine_factory.dart` contains `NativeTranscriberEngine` and `MockWebTranscriberEngine` stubs that emit canned segments; they do not demonstrate native inference or WASM readiness. Migrate this contract and these adapters to the names and behavior specified above when implementing the bridge; do not introduce parallel competing engine contracts. The application/infrastructure layers and full worker/download/cache lifecycle remain planned.

Use `apps/INDEX.md` at the Git repository root as the default context entry point. It records the current structure, planned boundaries, and essential contracts; consult individual source files and these specifications only as needed. Maintain it manually when module boundaries change. Do not regenerate or load full `graphify-out/` snapshots for routine context gathering unless explicitly requested.
