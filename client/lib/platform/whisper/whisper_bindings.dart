import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Opaque whisper.cpp context and decoding state.
final class WhisperContext extends Opaque {}

/// Minimal typed bindings for the whisper.cpp C API.
///
/// The struct layouts below are transcribed from the upstream
/// `include/whisper.h` and pinned to the whisper.cpp **v1.8.2** x64 C ABI
/// (the same `whisper_full_params` layout is still present on current
/// `master`). Every field the engine mutates is declared in native order, so
/// Dart's automatic struct alignment reproduces the compiled C offsets without
/// hand-written padding.
///
/// This pin is required: whisper.cpp inserts fields in the middle of
/// `whisper_full_params` across releases (v1.8.1 added `carry_initial_prompt`,
/// `prompt_tokens` and `prompt_n_tokens` immediately before `language`), which
/// shifts every later field. With a mismatched build, `language` would land at
/// the wrong offset and whisper.cpp would silently fall back to its default
/// `"en"`. [assertCompatibleLayout] rejects such a library at runtime.
///
/// There is no PATH search and no unverified file is loaded; the operator
/// supplies an absolute path and exact digest through [WhisperToolchainConfig].
final class WhisperBindings {
  WhisperBindings._({
    required this.contextDefaultParams,
    required this.initFromFileWithParams,
    required this.free,
    required this.fullDefaultParams,
    required this.full,
    required this.fullNSegments,
    required this.fullGetSegmentText,
    required this.fullGetSegmentT0,
    required this.fullGetSegmentT1,
  });

  static const int samplingGreedy = 0;

  /// Defaults written by `whisper_full_default_params(WHISPER_SAMPLING_GREEDY)`.
  ///
  /// These are stable across the releases sharing this struct layout and are
  /// used by [assertCompatibleLayout] to reject a library whose fields sit at
  /// different offsets.
  static const int _defaultNMaxTextCtx = 16384;
  static const double _defaultTholdPt = 0.01;
  static const double _defaultTholdPtsum = 0.01;
  static const double _defaultNoSpeechThold = 0.6;
  static const double _defaultGrammarPenalty = 100.0;

  final WhisperContextParams Function() contextDefaultParams;
  final Pointer<WhisperContext> Function(
    Pointer<Utf8>,
    WhisperContextParams,
  ) initFromFileWithParams;
  final void Function(Pointer<WhisperContext>) free;
  final WhisperFullParams Function(int) fullDefaultParams;
  final int Function(
    Pointer<WhisperContext>,
    WhisperFullParams,
    Pointer<Float>,
    int,
  ) full;
  final int Function(Pointer<WhisperContext>) fullNSegments;
  final Pointer<Utf8> Function(Pointer<WhisperContext>, int) fullGetSegmentText;
  final int Function(Pointer<WhisperContext>, int) fullGetSegmentT0;
  final int Function(Pointer<WhisperContext>, int) fullGetSegmentT1;

  /// Opens [libraryPath] and resolves the required symbols.
  ///
  /// Throws [ArgumentError] when the library or a required symbol is missing.
  factory WhisperBindings.load(String libraryPath) {
    final library = DynamicLibrary.open(libraryPath);
    return WhisperBindings._(
      contextDefaultParams: library.lookupFunction<
          WhisperContextParams Function(),
          WhisperContextParams Function()>('whisper_context_default_params'),
      initFromFileWithParams: library.lookupFunction<
          Pointer<WhisperContext> Function(
              Pointer<Utf8>, WhisperContextParams),
          Pointer<WhisperContext> Function(
              Pointer<Utf8>, WhisperContextParams)>(
          'whisper_init_from_file_with_params'),
      free: library.lookupFunction<Void Function(Pointer<WhisperContext>),
          void Function(Pointer<WhisperContext>)>('whisper_free'),
      fullDefaultParams: library.lookupFunction<
          WhisperFullParams Function(Int32),
          WhisperFullParams Function(int)>('whisper_full_default_params'),
      full: library.lookupFunction<
          Int32 Function(Pointer<WhisperContext>, WhisperFullParams,
              Pointer<Float>, Int32),
          int Function(Pointer<WhisperContext>, WhisperFullParams,
              Pointer<Float>, int)>('whisper_full'),
      fullNSegments: library.lookupFunction<
          Int32 Function(Pointer<WhisperContext>),
          int Function(Pointer<WhisperContext>)>('whisper_full_n_segments'),
      fullGetSegmentText: library.lookupFunction<
          Pointer<Utf8> Function(Pointer<WhisperContext>, Int32),
          Pointer<Utf8> Function(
              Pointer<WhisperContext>, int)>('whisper_full_get_segment_text'),
      fullGetSegmentT0: library.lookupFunction<
          Int64 Function(Pointer<WhisperContext>, Int32),
          int Function(Pointer<WhisperContext>, int)>(
          'whisper_full_get_segment_t0'),
      fullGetSegmentT1: library.lookupFunction<
          Int64 Function(Pointer<WhisperContext>, Int32),
          int Function(Pointer<WhisperContext>, int)>(
          'whisper_full_get_segment_t1'),
    );
  }

  /// Rejects a loaded library whose `whisper_full_params` layout differs.
  ///
  /// Reads the documented default greedy parameters from the freshly bound
  /// library and checks that the values land at the offsets these bindings
  /// expect. A mismatched build (for example v1.8.0, where the v1.8.1 prompt
  /// fields are absent) reads the wrong bytes and fails here instead of
  /// mistranscribing.
  ///
  /// Only values inside this process' own allocation are read; no pointer is
  /// dereferenced, so a mismatched library cannot crash the check.
  void assertCompatibleLayout() {
    final params = fullDefaultParams(samplingGreedy);
    // `whisper_full_default_params` sets `language` to the static string "en".
    // That field sits immediately after the v1.8.1 prompt fields, so a
    // non-null pointer here plus the numeric defaults together pin the offset.
    final compatible = params.language != nullptr &&
        params.nMaxTextCtx == _defaultNMaxTextCtx &&
        _near(params.tholdPt, _defaultTholdPt) &&
        _near(params.tholdPtsum, _defaultTholdPtsum) &&
        params.temperature == 0.0 &&
        params.maxInitialTs == 1.0 &&
        params.lengthPenalty == -1.0 &&
        _near(params.noSpeechThold, _defaultNoSpeechThold) &&
        params.greedyBestOf == -1 &&
        params.beamSize == -1 &&
        params.patience == -1.0 &&
        _near(params.grammarPenalty, _defaultGrammarPenalty);
    if (!compatible) {
      throw StateError(
        'The whisper.cpp library does not match the pinned v1.8.2 '
        'whisper_full_params layout.',
      );
    }
  }

  static bool _near(double value, double expected) =>
      (value - expected).abs() < 0.0001;
}

/// `whisper_context_params` as produced by `whisper_context_default_params()`.
///
/// The engine only round-trips this value: the library returns it and it is
/// handed back to `whisper_init_from_file_with_params` unchanged. The trailing
/// reservation keeps the Dart allocation larger than the native struct (48
/// bytes on x64) so a future appended field cannot make the callee read past
/// this buffer.
final class WhisperContextParams extends Struct {
  @Bool()
  external bool useGpu;

  @Bool()
  external bool flashAttn;

  @Int32()
  external int gpuDevice;

  @Bool()
  external bool dtwTokenTimestamps;

  @Int32()
  external int dtwAheadsPreset;

  @Int32()
  external int dtwNTop;

  @Size()
  external int dtwAheadsNHeads;

  external Pointer<Void> dtwAheadsHeads;

  @Size()
  external int dtwMemSize;

  @Array(208)
  external Array<Uint8> reservedTail;
}

/// `whisper_full_params` in native (v1.8.2) declaration order.
///
/// Dart inserts the correct alignment padding automatically, so fields are
/// listed without hand-written padding and their offsets match the compiled C
/// struct (304 bytes on x64). The engine only mutates `strategy`, `language`,
/// `no_context` and the print flags; every callback stays as the null pointer
/// written by `whisper_full_default_params`. The trailing reservation preserves
/// headroom for fields appended by newer releases.
final class WhisperFullParams extends Struct {
  @Int32()
  external int strategy;

  @Int32()
  external int nThreads;

  @Int32()
  external int nMaxTextCtx;

  @Int32()
  external int offsetMs;

  @Int32()
  external int durationMs;

  @Bool()
  external bool translate;

  @Bool()
  external bool noContext;

  @Bool()
  external bool noTimestamps;

  @Bool()
  external bool singleSegment;

  @Bool()
  external bool printSpecial;

  @Bool()
  external bool printProgress;

  @Bool()
  external bool printRealtime;

  @Bool()
  external bool printTimestamps;

  @Bool()
  external bool tokenTimestamps;

  @Float()
  external double tholdPt;

  @Float()
  external double tholdPtsum;

  @Int32()
  external int maxLen;

  @Bool()
  external bool splitOnWord;

  @Int32()
  external int maxTokens;

  @Bool()
  external bool debugMode;

  @Int32()
  external int audioCtx;

  @Bool()
  external bool tdrzEnable;

  external Pointer<Utf8> suppressRegex;

  external Pointer<Utf8> initialPrompt;

  /// Added in v1.8.1; present in the pinned v1.8.2 layout.
  @Bool()
  external bool carryInitialPrompt;

  external Pointer<Int32> promptTokens;

  @Int32()
  external int promptNTokens;

  external Pointer<Utf8> language;

  @Bool()
  external bool detectLanguage;

  @Bool()
  external bool suppressBlank;

  @Bool()
  external bool suppressNst;

  @Float()
  external double temperature;

  @Float()
  external double maxInitialTs;

  @Float()
  external double lengthPenalty;

  @Float()
  external double temperatureInc;

  @Float()
  external double entropyThold;

  @Float()
  external double logprobThold;

  @Float()
  external double noSpeechThold;

  @Int32()
  external int greedyBestOf;

  @Int32()
  external int beamSize;

  @Float()
  external double patience;

  external Pointer<Void> newSegmentCallback;

  external Pointer<Void> newSegmentCallbackUserData;

  external Pointer<Void> progressCallback;

  external Pointer<Void> progressCallbackUserData;

  external Pointer<Void> encoderBeginCallback;

  external Pointer<Void> encoderBeginCallbackUserData;

  external Pointer<Void> abortCallback;

  external Pointer<Void> abortCallbackUserData;

  external Pointer<Void> logitsFilterCallback;

  external Pointer<Void> logitsFilterCallbackUserData;

  external Pointer<Void> grammarRules;

  @Size()
  external int nGrammarRules;

  @Size()
  external int iStartRule;

  @Float()
  external double grammarPenalty;

  @Bool()
  external bool vad;

  external Pointer<Utf8> vadModelPath;

  @Float()
  external double vadThreshold;

  @Int32()
  external int vadMinSpeechDurationMs;

  @Int32()
  external int vadMinSilenceDurationMs;

  @Float()
  external double vadMaxSpeechDurationS;

  @Int32()
  external int vadSpeechPadMs;

  @Float()
  external double vadSamplesOverlap;

  @Array(208)
  external Array<Uint8> reservedTail;
}
