import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Opaque whisper.cpp context and decoding state.
final class WhisperContext extends Opaque {}

/// Minimal typed bindings for the whisper.cpp C API.
///
/// The struct layouts below target the whisper.cpp v1.7.x x64 C ABI. The
/// `whisper_full_params` struct has grown over time, so only the stable prefix
/// through `suppress_nst` is named and a generous trailing region is reserved
/// for newer fields. A binary built from a different ABI must be rejected by
/// the operator; the engine never searches PATH or loads an unverified file.
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
}

/// whisper_context_params is only produced by the library and passed back
/// unchanged. The trailing region keeps the Dart allocation larger than any
/// current release while preserving 8-byte alignment.
final class WhisperContextParams extends Struct {
  @Uint64()
  external int alignment;

  @Array(504)
  external Array<Uint8> reserved;
}

/// The stable prefix of `whisper_full_params` through `suppress_nst`.
///
/// Fields after `patience` are intentionally unnamed: `whisper_full_default_params`
/// fills the complete native struct, and the trailing reservation preserves
/// those bytes when the value is passed back to `whisper_full`.
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

  @Uint8()
  external int translate;

  @Uint8()
  external int noContext;

  @Uint8()
  external int noTimestamps;

  @Uint8()
  external int singleSegment;

  @Uint8()
  external int printSpecial;

  @Uint8()
  external int printProgress;

  @Uint8()
  external int printRealtime;

  @Uint8()
  external int printTimestamps;

  @Uint8()
  external int tokenTimestamps;

  @Array(3)
  external Array<Uint8> padding1;

  @Float()
  external double tholdPt;

  @Float()
  external double tholdPtsum;

  @Int32()
  external int maxLen;

  @Uint8()
  external int splitOnWord;

  @Array(3)
  external Array<Uint8> padding2;

  @Int32()
  external int maxTokens;

  @Uint8()
  external int debugMode;

  @Array(3)
  external Array<Uint8> padding3;

  @Int32()
  external int audioCtx;

  @Uint8()
  external int tdrzEnable;

  @Array(3)
  external Array<Uint8> padding4;

  external Pointer<Utf8> suppressRegex;

  external Pointer<Utf8> initialPrompt;

  external Pointer<Utf8> language;

  @Uint8()
  external int detectLanguage;

  @Uint8()
  external int suppressBlank;

  @Uint8()
  external int suppressNst;

  @Array(1)
  external Array<Uint8> padding5;

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

  @Array(1148)
  external Array<Uint8> nativeTail;
}
