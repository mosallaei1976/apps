# Offline artifact pipeline

These scripts pin and verify the native whisper.cpp library and the GGML model
artifacts. They are operator tools: the application never runs them, never
downloads on launch, and tests never touch the network.

## Model artifacts

`model_pins.json` is the source of truth for the Fast and Balanced profiles.
`fetch_models.ps1` downloads each pinned URL, checks the exact byte length and
streaming SHA-256, and (with `-WriteManifest`) regenerates
`assets/models/manifest.json`.

```powershell
# Verify cached files and rewrite the manifest deterministically
.\fetch_models.ps1 -WriteManifest

# Download missing files first, then verify and rewrite
.\fetch_models.ps1 -Download -WriteManifest
```

The pinned artifacts are whisper.cpp GGML `.bin` files, not GGUF. They are
standard multilingual OpenAI Whisper weights converted by whisper.cpp and
published under MIT in `ggerganov/whisper.cpp`. They are not Persian-trained
custom models.

## Android native library

`build_whisper_android.ps1` builds `libwhisper.so` from whisper.cpp `v1.8.2`
for `arm64-v8a` and `armeabi-v7a`. It requires:

- an installed Android NDK (`ANDROID_NDK_HOME` or `-NdkRoot`);
- CMake and Ninja on `PATH`;
- Git.

```powershell
.\build_whisper_android.ps1 -NdkRoot C:\Android\ndk\27.0.12077973
.\verify_whisper_android.ps1 -NdkRoot C:\Android\ndk\27.0.12077973
```

The build fails closed if the pinned commit, ABI layout probe, ELF machine or
required symbols do not match. Outputs go to
`android/app/src/main/jniLibs/<abi>/libwhisper.so` with
`whisper-artifacts.json` recording exact sizes and digests.

## What is intentionally not here

- No prebuilt library download: whisper.cpp does not publish official Android
  shared libraries.
- No PATH-based runtime discovery and no server fallback.
- No model or library download on application launch or during tests.
