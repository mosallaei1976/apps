import 'dart:typed_data';

/// Builds deterministic RIFF/WAVE fixtures for parser and adapter tests.
Uint8List wavBytes({
  int formatTag = 1,
  int channels = 1,
  int sampleRate = 16000,
  int bitsPerSample = 16,
  int byteRate = 32000,
  int blockAlign = 2,
  int dataLength = 3200,
  bool includeFormat = true,
  bool includeData = true,
  bool duplicateFormat = false,
  bool duplicateData = false,
  bool dataBeforeFormat = false,
  List<int> extraChunks = const [],
  int trailingBytes = 0,
  int riffSizeDelta = 0,
  int? forceRiffSize,
  int? forceDataChunkSize,
  int truncateBytes = 0,
}) {
  final formatData = BytesBuilder();
  _u16(formatData, formatTag);
  _u16(formatData, channels);
  _u32(formatData, sampleRate);
  _u32(formatData, byteRate);
  _u16(formatData, blockAlign);
  _u16(formatData, bitsPerSample);

  final formatBytes = formatData.takeBytes();
  final body = BytesBuilder();
  if (dataBeforeFormat && includeData) {
    _chunk(
      body,
      'data',
      List<int>.filled(dataLength, 0),
      sizeOverride: forceDataChunkSize,
    );
  }
  if (includeFormat) _chunk(body, 'fmt ', formatBytes);
  if (duplicateFormat) _chunk(body, 'fmt ', formatBytes);
  body.add(extraChunks);
  if (includeData && !dataBeforeFormat) {
    _chunk(
      body,
      'data',
      List<int>.filled(dataLength, 0),
      sizeOverride: forceDataChunkSize,
    );
  }
  if (duplicateData) {
    _chunk(body, 'data', List<int>.filled(2, 0));
  }

  final bodyBytes = body.takeBytes();
  final riffSize =
      forceRiffSize ?? 4 + bodyBytes.length + trailingBytes + riffSizeDelta;

  final output = BytesBuilder();
  output.add('RIFF'.codeUnits);
  _u32(output, riffSize);
  output.add('WAVE'.codeUnits);
  output.add(bodyBytes);
  if (trailingBytes > 0) {
    output.add(List<int>.filled(trailingBytes, 0));
  }

  final bytes = output.takeBytes();
  if (truncateBytes <= 0) return bytes;
  if (truncateBytes >= bytes.length) return Uint8List(0);
  return Uint8List.sublistView(bytes, 0, bytes.length - truncateBytes);
}

/// One padded RIFF chunk, useful for inserting unknown chunks into fixtures.
List<int> wavChunk(String id, List<int> data) {
  final output = BytesBuilder();
  _chunk(output, id, data);
  return output.takeBytes();
}

void _chunk(
  BytesBuilder output,
  String id,
  List<int> data, {
  int? sizeOverride,
}) {
  output.add(id.codeUnits);
  _u32(output, sizeOverride ?? data.length);
  output.add(data);
  if (data.length.isOdd) output.addByte(0);
}

void _u16(BytesBuilder output, int value) {
  output.add(<int>[value & 0xff, (value >> 8) & 0xff]);
}

void _u32(BytesBuilder output, int value) {
  output.add(<int>[
    value & 0xff,
    (value >> 8) & 0xff,
    (value >> 16) & 0xff,
    (value >> 24) & 0xff,
  ]);
}
