import 'dart:ffi';
import 'dart:typed_data';

import 'package:client/platform/whisper/whisper_bindings.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

/// Byte offsets within `struct whisper_full_params` on the pinned v1.8.2 x64
/// C ABI, transcribed from the upstream `include/whisper.h` declaration order
/// and Dart's documented automatic struct alignment.
const int _carryInitialPromptOffset = 80;
const int _promptTokensOffset = 88;
const int _promptNTokensOffset = 96;
const int _languageOffset = 104;
const int _grammarPenaltyOffset = 264;
const int _vadModelPathOffset = 272;

/// Native `sizeof(struct whisper_full_params)` on x64 for the v1.8.2 layout.
const int _nativeFullParamsSize = 304;

/// Returns the first byte offset whose bytes match [pattern].
///
/// Fails the test when the pattern is absent or appears more than once, which
/// would make the offset ambiguous.
int _singleOffset(List<int> bytes, List<int> pattern) {
  final matches = <int>[];
  for (var start = 0; start + pattern.length <= bytes.length; start++) {
    var matched = true;
    for (var index = 0; index < pattern.length; index++) {
      if (bytes[start + index] != pattern[index]) {
        matched = false;
        break;
      }
    }
    if (matched) matches.add(start);
  }
  expect(matches, hasLength(1), reason: 'pattern $pattern offsets: $matches');
  return matches.single;
}

List<int> _bytesOf(Pointer<WhisperFullParams> params) {
  final size = sizeOf<WhisperFullParams>();
  return params.cast<Uint8>().asTypedList(size).toList();
}

void main() {
  group('whisper_full_params layout (pinned v1.8.2)', () {
    late Pointer<WhisperFullParams> params;

    setUp(() {
      params = calloc<WhisperFullParams>();
    });

    tearDown(() {
      calloc.free(params);
    });

    test('declares at least the native v1.8.2 struct size', () {
      // The reserved tail must keep the Dart allocation no smaller than the
      // native struct so a by-value call never under-allocates.
      expect(sizeOf<WhisperFullParams>(), greaterThanOrEqualTo(_nativeFullParamsSize));
    });

    test('places language at the native offset', () {
      params.ref.language = Pointer<Utf8>.fromAddress(0x1122334455667788);
      final bytes = _bytesOf(params);
      final pattern = <int>[0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11];
      expect(_singleOffset(bytes, pattern), _languageOffset);
    });

    test('places the v1.8.1 prompt fields before language', () {
      params.ref.carryInitialPrompt = true;
      expect(
        _singleOffset(_bytesOf(params), const [1]),
        _carryInitialPromptOffset,
      );
      params.ref.carryInitialPrompt = false;

      params.ref.promptTokens = Pointer<Int32>.fromAddress(0x0A0B0C0D0E0F1011);
      expect(
        _singleOffset(
          _bytesOf(params),
          const [0x11, 0x10, 0x0F, 0x0E, 0x0D, 0x0C, 0x0B, 0x0A],
        ),
        _promptTokensOffset,
      );
      params.ref.promptTokens = nullptr.cast();

      params.ref.promptNTokens = 0x0BADF00D;
      expect(
        _singleOffset(
          _bytesOf(params),
          const [0x0D, 0xF0, 0xAD, 0x0B],
        ),
        _promptNTokensOffset,
      );
    });

    test('places the decoding tail at the native offsets', () {
      params.ref.grammarPenalty = 123.5;
      final penaltyBytes =
          Float32List.fromList(const [123.5]).buffer.asUint8List().toList();
      expect(
        _singleOffset(_bytesOf(params), penaltyBytes),
        _grammarPenaltyOffset,
      );
      params.ref.grammarPenalty = 0;

      params.ref.vadModelPath = Pointer<Utf8>.fromAddress(0x2111111111111112);
      expect(
        _singleOffset(
          _bytesOf(params),
          const [0x12, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x21],
        ),
        _vadModelPathOffset,
      );
    });
  });

  test('whisper_context_params keeps room for the native struct', () {
    // Native sizeof is 48 bytes on x64; the reservation must not be smaller.
    expect(sizeOf<WhisperContextParams>(), greaterThanOrEqualTo(48));
  });
}
