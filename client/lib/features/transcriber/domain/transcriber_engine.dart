import 'dart:typed_data';
import 'transcription_segment.dart';

abstract class TranscriberEngine {
  EngineState get state;

  Future<void> loadModel(String modelPath);

  Stream<TranscriptionSegment> transcribeStream(Uint8List audioBytes);

  Future<void> dispose();
}
