import 'dart:io';
import 'dart:typed_data';

import '../audio/wav_format.dart';

/// Reads the validated PCM payload and converts signed 16-bit little-endian
/// samples to the normalized float32 shape expected by whisper.cpp.
///
/// This runs inside the inference worker; callers must first validate the file
/// with [WavFormat] so only the canonical 16 kHz mono PCM shape is read.
abstract final class WhisperPcm {
  static Float32List read(File file, WavFormat format) {
    final RandomAccessFile handle;
    try {
      handle = file.openSync(mode: FileMode.read);
    } on FileSystemException {
      rethrow;
    }
    try {
      handle.setPositionSync(format.dataOffset);
      final bytes = handle.readSync(format.dataLength);
      if (bytes.length != format.dataLength) {
        throw const FormatException('Unexpected end of WAV audio data.');
      }
      final data = ByteData.sublistView(bytes);
      final samples = Float32List(format.frameCount);
      for (var index = 0; index < samples.length; index++) {
        samples[index] =
            data.getInt16(index * format.blockAlign, Endian.little) / 32768.0;
      }
      return samples;
    } finally {
      handle.closeSync();
    }
  }
}
