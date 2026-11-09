(**PRD & Landing Specification v1.1 — Platform Bridge**)

# Persian Transcriber — PRD & Landing Specification (v1.1)

Revision date: 2026-11-05. This revision replaces the unconditional Web/PWA launch requirement with a secondary, infrastructure-gated target. The implementation rules in `AGENTS.md` remain applicable, including the prerequisites for email collection. The companion `UX & Component Architecture Specification.md` must follow the engine, model, deployment, and resource requirements below.

## ۱. هویت و راهبرد کلی (Identity & Strategy)
* **نام رسمی پروژه:** Persian Transcriber
* **معمار و طراح سیستم:** سید محمد مصلائی (Seyed Mohammad Mosallaei) — Software Architect
* **مجوز نرم‌افزاری:** Apache License 2.0 (برای تمامی مخازن: کلاینت، وب و لندینگ)
* **دکترین امنیتی:** پردازش ۱۰۰٪ محلی روی دستگاه (On-Device Local Inference)، صفر تلمتری و بدون ردیاب، بدون ارسال حتی یک بایت صوت به هیچ سروری.

---

## ۲. مشخصات و متون لندینگ‌پیج (Landing Page Blueprint)

### ۲.۱. هدر (Sticky Header)
* **لوگو و نام:** Persian Transcriber (با فونت Vazirmatn / نمایش راست‌به‌چپ در فارسی و چپ‌به‌راست در انگلیسی).
* **ناوبری:** امکانات، معماری سیستم، حریم خصوصی، درباره ما.
* **سوئیچ زبان:** FA / EN (تغییر آنی متون و جهت چیدمان صفحه RTL ↔ LTR).
* **دکمه استار گیت‌هاب:** لینک مستقیم به مخزن پروژه (در نسخه بدون اسکریپت ردیاب، به‌صورت بج استاتیک بدون فراخوانی غیرضروری API شخص ثالث).

### ۲.۲. بخش ورود و نصب (Hero Section)
* **تیتر اصلی (فارسی):** گفتار فارسی را به متن تبدیل کنید؛ روی دستگاه خودتان.
* **تیتر اصلی (انگلیسی):** Transcribe Persian Speech to Text; 100% On-Device.
* **زیرتیتر (فارسی):** رونویسی و تولید زیرنویس روی دستگاه با مدل‌های کوانتیزه‌شده چندزبانه Whisper؛ آفلاین پس از دریافت اولیه برنامه و مدل. صوت شما برای رونویسی به سرور ارسال نمی‌شود.
* **چیدمان بلوک سه‌گانه دکمه‌های نصب (Primary CTAs):**
  1. **Google Play:** با آیکون رسمی + برچسب وضعیت **«به‌زودی / Coming Soon»**؛ نمایش اطلاعات انتشار تا زمان وجود لینک واقعی فروشگاه.
  2. **App Store:** با آیکون رسمی + برچسب وضعیت **«به‌زودی / Coming Soon»**؛ نمایش اطلاعات انتشار تا زمان وجود لینک واقعی فروشگاه.
  3. **نسخه تحت وب (PWA):** هدف انتشار ثانویه و مشروط؛ دکمه اجرا تا تأیید محیط WASM و تنظیم آدرس واقعی برنامه غیرفعال می‌ماند. پیش از انتشار، تمرکز لندینگ بر فرم عضویت ایمیلی برای اعلام علاقه‌مندی است، با پیش‌نیازهای بخش ۴.

### ۲.۳. بنر تضمین حریم خصوصی (Trust Bar)
* ۴ کارت مینی‌مال فلت:
  * **بدون آپلود صوت:** پردازش کامل روی پردازنده یا گرافیک دستگاه شما.
  * **استفاده آفلاین:** پس از دریافت اولیه فایل مدل، بی‌نیاز از اتصال شبکه.
  * **کد متن‌باز:** تحت مجوز آپاچی ۲.۰ در گیت‌هاب، قابل بازرسی خط‌به‌خط.
  * **صفر ردیاب:** این صفحه و خود اپلیکیشن فاقد هرگونه کد تلمتری، تبلیغات یا ابزار ردیابی است.

### ۲.۴. معماری فنی پایپ‌لاین (Architecture Showcase)
* مسیر داده: ورودی فایل/میکروفن → FFmpeg حداقلی Audio-only → WAV با PCM مونو، 16kHz و 16-bit → Silero VAD در صورت فعال بودن → رابط `AbstractEngine` → ذخیره‌سازی محلی → خروجی TXT / SRT / VTT.
* مسیر فراخوانی: UI → منطق برنامه → `AbstractEngine` → `NativeFfiEngine` یا `WasmWebWorkerEngine`. جزئیات FFI و WASM نباید وارد UI شوند؛ مشخصات الزام‌آور در بخش ۳ آمده است.

### ۲.۵. بخش حامیان و راهکارهای سازمانی (Sponsors & Enterprise)
* **معرفی معمار:** سید محمد مصلائی (Software Architect).
* **حمایت مالی فردی (Donations):**
  * دکمه حمایت بین‌المللی: GitHub Sponsors.
  * رمزارزها: آدرس‌های عمومی ولت Bitcoin و USDT (شبکه TRC20).
  * حامیان داخلی: لینک پرداخت ریالی (زرین‌پال / ریمیت).
* **استعلام نسخه سفارشی سازمانی (B2B):**
  * تیتر: «پیاده‌سازی سازمانی و درون‌سازمانی (On-Premise) برای شرکت‌ها، بیمارستان‌ها و دفاتر حقوقی».
  * فرم سبک تماس: فیلدهای نام، ایمیل/شماره تماس، موضوع پروژه، متن پیام.
  * ارتباط سریع تلگرام: نمایش لینک مستقیم `@msli1976` با آیکون رسمی تلگرام.

### ۲.۶. سیاست حریم خصوصی و فوتر (Privacy & Footer)
* متن صریح و شفاف: *«صوت و متن رونویسی شما برای پردازش به هیچ سروری ارسال نمی‌شود و روی دستگاه باقی می‌ماند. دانلود اولیه برنامه و مدل به شبکه نیاز دارد. عضویت اختیاری در اعلان انتشار، فقط ایمیل و رضایت شما را به سرویس خودمیزبان ارسال می‌کند؛ بدون تلمتری یا ردیاب.»*
* پیوندهای مخزن گیت‌هاب، گزارش باگ‌ها (Issues)، فایل LICENSE (Apache-2.0) و راه‌های ارتباطی.

---

## 3. Platform Bridge Architecture (Normative)

Desktop/mobile are the primary deployment targets. Web/PWA is a secondary target subject to Section 4. All audio decoding, preprocessing, and inference remain on the user's device.

### 3.1 Abstract Engine Interface

The application layer must depend only on an `AbstractEngine` contract (the Bridge Pattern), injected at the platform composition root. The UI consumes application state and commands; neither the UI nor application logic may import native bindings, WASM modules, or worker implementation details. Platform selection must use platform-safe imports so browser builds never load `dart:ffi` or native-only dependencies.

| Implementation | Target | Execution |
|---|---|---|
| `NativeFfiEngine` | Android, iOS, Windows, macOS | `whisper.cpp` through Dart FFI, owned and invoked by a Dart Worker Isolate |
| `WasmWebWorkerEngine` | Validated Web/PWA deployment | `whisper.cpp` compiled to WASM, invoked through messages to Web Workers; multithreading requires Section 4's isolation gate |

The shared contract must expose capability/readiness checks, model loading and unloading, transcription start, progress and partial/final result events, cancellation, typed failures, and disposal. Requests use platform-neutral audio/model references and options; results contain transcript segments and timestamps. Native pointers, browser worker handles, and platform-specific storage paths must stay inside adapters. Unsupported capabilities return explicit errors rather than silently selecting a remote service.

Audio standardization and persistence are application services behind platform adapters, separate from the inference bridge. Shared orchestration sends standardized audio to `AbstractEngine`, persists completed results, and releases job resources. Both engines must satisfy shared contract tests for progress, cancellation, errors, and disposal.

### 3.2 Audio Standardization and Background Work

Every file or microphone input must pass through a minimal **Audio-only FFmpeg build**, producing **16,000 Hz, signed 16-bit, mono PCM WAV** (`pcm_s16le`) before inference. Enable only required audio demuxers, decoders, resampling/filtering, and WAV output; omit video processing/encoding, playback, and network protocols. Audio extraction from media containers is allowed only for formats validated with that build. Do not assume an audio-only build supports every video container, or treat legacy FFmpegKit as an approved maintained dependency.

Decode and standardize audio before optional Silero VAD; preserve offsets from the original timeline for subtitle export. Unsupported inputs must produce a clear local error.

On native clients, Dart **Worker Isolates are mandatory** for heavy audio preparation, VAD, model hashing/loading, and FFI inference. The UI isolate handles rendering and lightweight orchestration only. Workers report progress, accept cancellation, and release buffers and native handles on success, error, or cancellation. Use bounded queues and transferable/chunked audio to avoid unbounded memory copies.

On Web/PWA, CPU-heavy preprocessing, SHA-256 work, and inference must execute in Web Workers with a validated audio-only FFmpeg WASM build. Dart Worker Isolates are the native execution mechanism; browser workers are the platform equivalent and must not be represented as native FFI or assumed to have native isolate support.

## 4. Conditional Web/PWA Deployment and Landing Signup

Web engine implementation and deployment are contingent on first validating a hosted WASM environment. The origin serving the actual web application must send:

```http
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

The readiness gate requires a secure context, `crossOriginIsolated === true`, usable `SharedArrayBuffer`, and a passing multithreaded WASM/Web Worker smoke test on each supported browser. WASM, worker, model, and audio preprocessing assets must load under these policies; cross-origin assets require compatible CORS/CORP responses. Validate the deployed server/CDN responses, not just local development settings.

Enable the web launch CTA only after the environment gate, end-to-end local transcription, worker cancellation, local storage/model integrity, and offline-after-setup behavior pass, and a real deployed app URL is configured. Document browser memory/storage limits from measurements. If readiness fails, keep the CTA unavailable with a clear explanation; never fall back to server transcription. Do not add a manifest/service worker to the landing page merely to suggest that the app is installable.

Until WASM is fully validated, the landing page's primary conversion goal is an **optional email interest/signup form** for release updates. Consistent with `AGENTS.md`, collection may become functional only when a self-hosted submission endpoint, explicit consent text, storage/retention and deletion policy, and updated privacy policy exist. Collect only the email address, requested release interest, and necessary consent record; never attach audio, transcripts, analytics, or device fingerprints. Provide accessible validation and success/failure states without third-party mailing-list trackers. Before this infrastructure exists, show an honest signup-unavailable state and release information; do not display a working-looking submit control or claim to store signups. Store CTAs remain informational until real listings exist.

## 5. Quantized Model Profiles

Both implementations must support these two downloadable multilingual Whisper model profiles, subject to measured device/browser capability:

| Profile | Model family and quantization | Approximate download target | Product intent |
|---|---|---|---|
| Fast / Low-Resource | Base-based, quantized multilingual artifact | ~80 MB | Favor speed and low-resource devices |
| Precision / Balanced | Small-based, quantized INT8 or `q5_k` artifact compatible with the selected engine build | ~200 MB | Favor accuracy on conversational Persian and slang |

These are artifact size targets, not exact upstream file sizes or RAM estimates. INT8 and `q5_k` are alternative quantization formats, not interchangeable names; pin and validate the exact compatible artifact for each released profile. Record family, quantization, version, exact byte length, SHA-256, source/license, and engine compatibility in a trusted model manifest. If a candidate misses the size target or compatibility gate, resolve the artifact specification before release rather than mislabeling it. Accuracy and speed claims require Persian conversational/slang evaluation on representative devices.

Download either model **on demand** with visible size, progress, cancellation, and **resume support**. Persist partial-download metadata and validate range responses and artifact identity (version/ETag or equivalent); restart safely if the server cannot resume or the artifact changes. Stream SHA-256 verification over the complete artifact and compare against the trusted manifest before atomic promotion to usable storage. Corrupt or incomplete models must never load. Offer retry, model switching, and deletion; protect active model files. Model downloads may use the network, while audio and transcripts remain local.

## 6. UI, Local Database, and Disk Lifecycle

### 6.1 RTL and Typography

The transcription client must use a **strictly RTL application layout**, including navigation, settings, dialogs, transcript editing, and exports preview. Bundle and register **Vazirmatn** as the native Flutter font family with required weights; serve the same font locally on Web/PWA without remote font requests. English labels may be translated without reversing the client's RTL shell. Use isolated LTR spans for hashes, filenames, numeric specifications, and code where necessary. The bilingual marketing landing page retains its existing FA/RTL and EN/LTR switch; this does not relax the client RTL requirement. Preserve keyboard navigation, focus visibility, text scaling, and accessible labels.

### 6.2 Local Persistence

Use **Isar** for the native local database, behind a repository abstraction. Store transcription jobs/status, transcript segments/timestamps and edits, model manifest/download metadata, and user settings locally. Keep large audio and model binaries in managed files referenced by records rather than database blobs. Web/PWA must implement the same repository contract using **IndexedDB**, with a validated browser file/blob storage adapter; do not assume native Isar/FFI support in a browser. Completed transcripts must remain available offline and deletable by the user. Provide per-job deletion and a clear-all-transcripts action without implicitly deleting user source files or installed models.

### 6.3 TemporaryDirectory Cleanup Policy

Use the platform `TemporaryDirectory` (for example, Flutter's `getTemporaryDirectory()`) for application-owned, per-job decoded WAVs, VAD chunks, and intermediate exports. Never depend on the OS to clean these files. After completion and successful persistence, failure, or cancellation, close worker/file handles and automatically remove job temporary files in finalization. Keep requested final exports and persisted transcripts outside this directory.

Run a startup recovery sweep and a sweep before each new job: reconcile interrupted jobs and remove orphaned job caches and inactive intermediates older than **24 hours**, never files owned by an active job. Retry failed deletions on the next sweep. Expose cache usage and a manual clear-cache action that skips active jobs. Check free space before downloads/conversion and fail with an actionable message if insufficient; use bounded chunk processing to limit temporary growth. Do not traverse outside application-owned cache paths or delete the user's original media.

Installed verified models belong in persistent application storage. Resumable `.part` downloads belong in a separate managed download area and survive job-cache cleanup; remove them on explicit download cancellation/deletion, integrity failure, or after **7 days of inactivity**, with the policy visible to the user. Web/PWA must implement equivalent per-job temporary blob/worker-filesystem cleanup and interrupted-job recovery, with quota checks; a native `TemporaryDirectory` API is not assumed in the browser.

## 7. Acceptance Criteria

1. Application and UI code depend on `AbstractEngine`; native and web builds select their respective adapters without importing unsupported platform APIs.
2. Each adapter passes contract checks for model lifecycle, progress/results, cancellation, typed errors, and resource disposal. Heavy native work runs in Dart Worker Isolates; browser work runs in Web Workers without blocking interaction.
3. Every supported input is standardized through the audio-only FFmpeg build to 16kHz, signed 16-bit mono PCM WAV before VAD/inference; unsupported formats report an error.
4. Both quantized model profiles support on-demand download, interrupted-download resume, artifact-change handling, SHA-256 rejection of corrupted data, switching, and deletion. Publish exact artifact sizes and measured compatibility.
5. A deployed Web/PWA candidate passes the isolation/header and multithreaded-worker gates, local transcription and offline/storage tests before the real web CTA is enabled. Failed readiness leaves it disabled.
6. Landing signup is the pre-web-release interest path and collects email only after its self-hosted endpoint, consent, retention/deletion policy, and privacy-policy prerequisites exist.
7. Client screens maintain RTL and locally bundled Vazirmatn. Native Isar and browser IndexedDB persist transcripts across restarts and support user deletion.
8. Completion, failure, cancellation, restart recovery, stale-cache expiry, and low-disk/quota scenarios demonstrate cleanup without deleting active jobs, installed models, retained partial downloads, completed transcripts, or original media.
