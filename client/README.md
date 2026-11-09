

# Persian Transcriber

A privacy-focused, offline-first Persian speech-to-text application built with Flutter. Designed with a **mobile-first** approach for Android and iOS, with cross-platform desktop (Windows/macOS) architecture and local on-device machine learning inference.

---

## 🔒 Security Doctrine & Core Principles

- **100% On-Device Processing**: Complete data sovereignty. Audio never leaves the user's device.
- **Zero Telemetry**: No third-party trackers, no remote analytics, and zero external network calls during transcription.
- **Offline-First**: Fully functional without internet connectivity after the initial model download.
- **Strict RTL Design System**: Built with a bidirectional layout engine using native Vazirmatn typography.

---

## 📱 Mobile-First Architecture

The application is structured under clean architecture principles to deliver low-latency audio processing on mobile devices:

Mobile UI (RTL / Flutter) ──> Application Coordinator ──> Domain Ports <── Platform Isolates & FFI


- **Audio Ingestion**: Clean microphone capture and file import, normalized via a constrained, audio-only FFmpeg pipeline to canonical **WAV PCM mono 16 kHz 16-bit** format.
- **VAD Preprocessing**: Silero Voice Activity Detection (VAD) to strip silence and minimize inference overhead.
- **Engine Bridge**: Domain abstraction (`AbstractEngineInterface`) delegating heavy compute to isolated background workers (Dart Worker Isolates on mobile/desktop; Web Workers on web).
- **Inference Runtime**: Direct native FFI integration with optimized `whisper.cpp` kernels.
- **Export Pipelines**: Direct export to **TXT**, **SRT**, and **VTT** subtitle formats.

---

## 🧠 Quantized Model Profiles

The app provides two dedicated, verified model tiers tailored for mobile constraints:

| Profile | Target Size | Primary Use Case |
| :--- | :--- | :--- |
| **Fast / Low-Resource** | ~80 MB | Lightweight, base-quantized model for low-memory mobile devices and rapid dictation. |
| **Precision / Balanced** | ~200 MB | Small-based quantized model (INT8 / `q5_k`) fine-tuned for conversational Persian and complex terminology. |

*Model management incorporates streaming SHA-256 integrity verification, resumable background chunk downloads, and atomic filesystem promotion.*

---

## 🛠 Project Structure
├── apps/

│ ├── client/ # Core Flutter cross-platform mobile/desktop application

│ │ ├── lib/

│ │ │ ├── application/ # Job coordination, leasing, and session lifecycle

│ │ │ ├── domain/ # Canonical engine contracts, ports, and DTOs

│ │ │ ├── platform/ # Platform-specific adapters, FFI, and audio runners

│ │ │ └── presentation/ # Flutter UI, state management, and RTL widgets

│ │ └── test/ # Unit, widget, and architecture contract test suite

│ └── landing/ # Lightweight, zero-tracking web showcase & docs



---

## 🚀 Roadmap

1. [x] Architectural domain boundaries, state coordination, and session lifecycles.
2. [x] Trusted model manifest system with cryptographic SHA-256 verification and atomic storage.
3. [x] Native audio capture pipeline (Windows foundation; mobile recording integration).
4. [ ] Isolated audio-only FFmpeg normalization worker.
5. [ ] Native `whisper.cpp` FFI engine integration for Android, iOS, and desktop targets.
6. [ ] Local persistence layer (Isar) and export formatters (SRT/VTT).

---

## 👤 Author & License

- **Architect & Developer**: Seyed Mohammad Mosallaei
- **License**: [Apache 2.0](LICENSE)

*Built for absolute user privacy and local machine intelligence.*

