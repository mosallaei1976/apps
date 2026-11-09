import 'dart:io';
import 'dart:typed_data';

import 'package:client/platform/audio/wav_format.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/wav_fixture.dart';

void main() {
  group('WavFormat.parse', () {
    test('accepts canonical 16 kHz mono 16-bit PCM and derives duration', () {
      final format = WavFormat.parse(wavBytes(dataLength: 32000));

      expect(format.sampleRate, 16000);
      expect(format.channels, 1);
      expect(format.bitsPerSample, 16);
      expect(format.blockAlign, 2);
      expect(format.byteRate, 32000);
      expect(format.frameCount, 16000);
      expect(format.duration, const Duration(seconds: 1));
      expect(format.dataOffset, 44);
      expect(format.dataLength, 32000);
    });

    test('a single frame still has a positive duration', () {
      final format = WavFormat.parse(wavBytes(dataLength: 2));

      expect(format.frameCount, 1);
      expect(format.duration, greaterThan(Duration.zero));
      expect(format.duration.inMicroseconds, 62);
    });

    test('skips unknown chunks, including odd-sized padding', () {
      final format = WavFormat.parse(
        wavBytes(
          extraChunks: wavChunk('LIST', <int>[1, 2, 3]),
          dataLength: 320,
        ),
      );

      expect(format.dataOffset, 56);
      expect(format.duration, const Duration(milliseconds: 10));
    });

    test('rejects a missing RIFF signature', () {
      final bytes = Uint8List.fromList(
        wavBytes()..[0] = 'X'.codeUnitAt(0),
      );
      expect(() => WavFormat.parse(bytes), throwsFormatException);
    });

    test('rejects a non-WAVE RIFF container', () {
      expect(
        () => WavFormat.parse(wavBytes()..setRange(8, 12, 'AVI '.codeUnits)),
        throwsFormatException,
      );
    });

    test('rejects compressed or float formats', () {
      expect(
        () => WavFormat.parse(wavBytes(formatTag: 3)),
        throwsFormatException,
      );
      expect(
        () => WavFormat.parse(wavBytes(formatTag: 0xfffe)),
        throwsFormatException,
      );
    });

    test('rejects stereo', () {
      expect(
        () => WavFormat.parse(wavBytes(channels: 2, blockAlign: 4)),
        throwsFormatException,
      );
    });

    test('rejects a sample rate other than 16 kHz', () {
      expect(
        () => WavFormat.parse(wavBytes(sampleRate: 48000)),
        throwsFormatException,
      );
    });

    test('rejects bit depths other than 16', () {
      for (final bits in <int>[8, 24, 32]) {
        expect(
          () => WavFormat.parse(
            wavBytes(bitsPerSample: bits, blockAlign: bits ~/ 8),
          ),
          throwsFormatException,
          reason: '$bits-bit PCM must be rejected',
        );
      }
    });

    test('rejects inconsistent byte rate and block alignment', () {
      expect(
        () => WavFormat.parse(wavBytes(byteRate: 44100)),
        throwsFormatException,
      );
      expect(
        () => WavFormat.parse(wavBytes(blockAlign: 4)),
        throwsFormatException,
      );
    });

    test('rejects empty audio', () {
      expect(
        () => WavFormat.parse(wavBytes(dataLength: 0)),
        throwsFormatException,
      );
    });

    test('rejects a partial 16-bit sample frame', () {
      expect(
        () => WavFormat.parse(wavBytes(dataLength: 3)),
        throwsFormatException,
      );
    });

    test('rejects duplicate format and data chunks', () {
      expect(
        () => WavFormat.parse(wavBytes(duplicateFormat: true)),
        throwsFormatException,
      );
      expect(
        () => WavFormat.parse(wavBytes(duplicateData: true)),
        throwsFormatException,
      );
    });

    test('rejects data before the format chunk', () {
      expect(
        () => WavFormat.parse(wavBytes(dataBeforeFormat: true)),
        throwsFormatException,
      );
    });

    test('rejects missing format or data chunks', () {
      expect(
        () => WavFormat.parse(wavBytes(includeFormat: false)),
        throwsFormatException,
      );
      expect(
        () => WavFormat.parse(wavBytes(includeData: false)),
        throwsFormatException,
      );
    });

    test('rejects a chunk whose declared size crosses the RIFF boundary', () {
      expect(
        () => WavFormat.parse(wavBytes(forceDataChunkSize: 999999)),
        throwsFormatException,
      );
    });

    test('rejects a RIFF size beyond the file length', () {
      expect(
        () => WavFormat.parse(wavBytes(truncateBytes: 12)),
        throwsFormatException,
      );
    });

    test('rejects undeclared trailing bytes', () {
      expect(
        () => WavFormat.parse(wavBytes(trailingBytes: 4)),
        throwsFormatException,
      );
    });

    test('rejects files too short to contain a header', () {
      expect(
        () => WavFormat.parse(Uint8List.fromList(<int>[1, 2, 3])),
        throwsFormatException,
      );
    });
  });

  group('WavFormat.read', () {
    late Directory temporary;

    setUp(() async {
      temporary = await Directory.systemTemp.createTemp('wav-format-');
    });

    tearDown(() async {
      if (await temporary.exists()) await temporary.delete(recursive: true);
    });

    test('reads the header without loading the audio payload', () async {
      final file = File('${temporary.path}${Platform.pathSeparator}valid.wav');
      await file.writeAsBytes(wavBytes(dataLength: 3200));

      final format = WavFormat.read(file);

      expect(format.duration, const Duration(milliseconds: 100));
      expect(format.dataOffset, 44);
      expect(format.dataLength, 3200);
    });

    test('reports truncated files', () async {
      final file = File('${temporary.path}${Platform.pathSeparator}bad.wav');
      await file.writeAsBytes(wavBytes(truncateBytes: 8));

      expect(() => WavFormat.read(file), throwsFormatException);
    });

    test('propagates a missing file as a filesystem error', () async {
      final file =
          File('${temporary.path}${Platform.pathSeparator}missing.wav');

      expect(() => WavFormat.read(file), throwsA(isA<FileSystemException>()));
    });
  });
}
