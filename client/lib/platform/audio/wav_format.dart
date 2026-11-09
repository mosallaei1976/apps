import 'dart:io';
import 'dart:typed_data';

/// Strict parser for the only WAV shape accepted by the transcription engine:
/// RIFF/WAVE, PCM format 1, mono, 16 kHz, signed 16-bit, non-empty data.
///
/// This is intentionally narrower than a general media parser. FFmpeg, not this
/// class, is responsible for decoding arbitrary user input.
final class WavFormat {
  const WavFormat._({
    required this.dataOffset,
    required this.dataLength,
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
  });

  static const int requiredFormatTag = 1;
  static const int requiredSampleRate = 16000;
  static const int requiredChannels = 1;
  static const int requiredBitsPerSample = 16;
  static const int requiredBlockAlign = 2;
  static const int requiredByteRate = 32000;

  /// Zero-based byte offset of the first PCM sample in the file.
  final int dataOffset;

  /// Number of PCM data bytes. Always positive and a whole number of frames.
  final int dataLength;

  final int sampleRate;
  final int channels;
  final int bitsPerSample;

  int get byteRate => requiredByteRate;
  int get blockAlign => requiredBlockAlign;

  /// Number of complete sample frames.
  int get frameCount => dataLength ~/ requiredBlockAlign;

  /// Duration derived from the data length, never from a container estimate.
  Duration get duration => Duration(
        microseconds:
            (dataLength * Duration.microsecondsPerSecond) ~/ requiredByteRate,
      );

  /// Parses the header of an in-memory WAV file.
  static WavFormat parse(Uint8List bytes) {
    return _parseWav(bytes.length, (offset, length) {
      if (offset < 0 || length < 0 || offset + length > bytes.length) {
        throw const FormatException('WAV chunk extends beyond the file.');
      }
      return Uint8List.sublistView(bytes, offset, offset + length);
    });
  }

  /// Reads only the RIFF header and chunk headers from [file].
  ///
  /// The audio payload is not loaded into memory. Call this from the audio
  /// preparation worker so a long recording does not block the UI isolate.
  static WavFormat read(File file) {
    final int fileLength;
    final RandomAccessFile handle;
    try {
      fileLength = file.lengthSync();
      handle = file.openSync(mode: FileMode.read);
    } on FileSystemException {
      rethrow;
    }
    try {
      return _parseWav(fileLength, (offset, length) {
        if (offset < 0 ||
            length < 0 ||
            offset + length > fileLength ||
            offset + length < offset) {
          throw const FormatException('WAV chunk extends beyond the file.');
        }
        handle.setPositionSync(offset);
        final bytes = handle.readSync(length);
        if (bytes.length != length) {
          throw const FormatException('Unexpected end of WAV file.');
        }
        return bytes;
      });
    } finally {
      handle.closeSync();
    }
  }

  static WavFormat _parseWav(
    int fileLength,
    Uint8List Function(int offset, int length) read,
  ) {
    if (fileLength < 12) {
      throw const FormatException('File is too short to be a WAV container.');
    }

    final header = _read(read, 0, 12);
    if (!_equalsAscii(header, 0, 'RIFF')) {
      throw const FormatException('Missing RIFF signature.');
    }
    if (!_equalsAscii(header, 8, 'WAVE')) {
      throw const FormatException('RIFF container is not a WAVE file.');
    }

    final riffSize = _uint32(header, 4);
    if (riffSize < 4) {
      throw const FormatException('Invalid RIFF size.');
    }
    final riffEnd = riffSize + 8;
    if (riffEnd > fileLength) {
      throw const FormatException('RIFF size exceeds the file length.');
    }
    if (riffEnd < fileLength) {
      throw const FormatException('Unexpected trailing bytes after RIFF data.');
    }
    if (riffEnd.isOdd) {
      throw const FormatException(
          'RIFF size does not end on a chunk boundary.');
    }

    var format = false;
    int? dataOffset;
    int? dataLength;
    var offset = 12;
    while (offset < riffEnd) {
      if (riffEnd - offset < 8) {
        throw const FormatException('Truncated WAV chunk header.');
      }
      final chunkHeader = _read(read, offset, 8);
      final chunkSize = _uint32(chunkHeader, 4);
      final chunkDataOffset = offset + 8;
      final chunkEnd = chunkDataOffset + chunkSize;
      if (chunkEnd > riffEnd) {
        throw const FormatException('WAV chunk exceeds the RIFF boundary.');
      }

      if (_equalsAscii(chunkHeader, 0, 'fmt ')) {
        if (format) {
          throw const FormatException('Duplicate WAV format chunk.');
        }
        if (chunkSize < 16) {
          throw const FormatException('WAV format chunk is too short.');
        }
        final fmt = _read(read, chunkDataOffset, 16);
        _validateFormat(fmt);
        format = true;
      } else if (_equalsAscii(chunkHeader, 0, 'data')) {
        if (!format) {
          throw const FormatException(
              'WAV data chunk appears before the format.');
        }
        if (dataOffset != null) {
          throw const FormatException('Duplicate WAV data chunk.');
        }
        dataOffset = chunkDataOffset;
        dataLength = chunkSize;
      }

      var next = chunkEnd;
      if (chunkSize.isOdd) next += 1;
      if (next > riffEnd) {
        throw const FormatException('WAV chunk is missing its padding byte.');
      }
      offset = next;
    }

    if (offset != riffEnd) {
      throw const FormatException('Malformed WAV chunk layout.');
    }
    if (!format) {
      throw const FormatException('Missing WAV format chunk.');
    }
    if (dataOffset == null || dataLength == null) {
      throw const FormatException('Missing WAV data chunk.');
    }
    if (dataLength <= 0) {
      throw const FormatException('WAV contains no audio samples.');
    }
    if (dataLength % requiredBlockAlign != 0) {
      throw const FormatException('WAV data is not a whole 16-bit mono frame.');
    }
    if (dataOffset + dataLength > fileLength) {
      throw const FormatException('WAV data extends beyond the file length.');
    }

    return WavFormat._(
      dataOffset: dataOffset,
      dataLength: dataLength,
      sampleRate: requiredSampleRate,
      channels: requiredChannels,
      bitsPerSample: requiredBitsPerSample,
    );
  }

  static void _validateFormat(Uint8List fmt) {
    final tag = _uint16(fmt, 0);
    final channels = _uint16(fmt, 2);
    final sampleRate = _uint32(fmt, 4);
    final byteRate = _uint32(fmt, 8);
    final blockAlign = _uint16(fmt, 12);
    final bitsPerSample = _uint16(fmt, 14);

    if (tag != requiredFormatTag) {
      throw const FormatException('WAV format must be uncompressed PCM.');
    }
    if (channels != requiredChannels) {
      throw const FormatException('WAV must have exactly one channel.');
    }
    if (sampleRate != requiredSampleRate) {
      throw const FormatException('WAV sample rate must be 16000 Hz.');
    }
    if (bitsPerSample != requiredBitsPerSample) {
      throw const FormatException('WAV samples must be 16-bit.');
    }
    if (blockAlign != requiredBlockAlign) {
      throw const FormatException('WAV block alignment must be 2 bytes.');
    }
    if (byteRate != requiredByteRate) {
      throw const FormatException('WAV byte rate must be 32000 bytes/second.');
    }
  }

  static Uint8List _read(
    Uint8List Function(int offset, int length) read,
    int offset,
    int length,
  ) {
    try {
      return read(offset, length);
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('WAV header could not be read.');
    }
  }

  static bool _equalsAscii(Uint8List bytes, int offset, String value) {
    if (offset + value.length > bytes.length) return false;
    for (var index = 0; index < value.length; index++) {
      if (bytes[offset + index] != value.codeUnitAt(index)) return false;
    }
    return true;
  }

  static int _uint16(Uint8List bytes, int offset) {
    return bytes[offset] | (bytes[offset + 1] << 8);
  }

  static int _uint32(Uint8List bytes, int offset) {
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }
}
