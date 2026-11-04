import 'package:flutter/foundation.dart';
import '../features/transcriber/domain/transcription_segment.dart';
import '../features/transcriber/domain/transcriber_engine.dart';

class MockWebTranscriberEngine implements TranscriberEngine {
  @override
  EngineState state = EngineState.ready;

  @override
  Future<void> loadModel(String modelPath) async {
    state = EngineState.ready;
  }

  @override
  Stream<TranscriptionSegment> transcribeStream(Uint8List audioBytes) async* {
    yield const TranscriptionSegment(
      start: Duration.zero,
      end: Duration(seconds: 2),
      text: "حالت اجرای وب (WASM) آماده است.",
    );
  }

  @override
  Future<void> dispose() async {
    state = EngineState.uninitialized;
  }
}

class NativeTranscriberEngine implements TranscriberEngine {
  @override
  EngineState state = EngineState.uninitialized;

  @override
  Future<void> loadModel(String modelPath) async {
    state = EngineState.ready;
  }

  @override
  Stream<TranscriptionSegment> transcribeStream(Uint8List audioBytes) async* {
    yield const TranscriptionSegment(
      start: Duration.zero,
      end: Duration(seconds: 2),
      text: "موتور پردازش محلی آماده است.",
    );
  }

  @override
  Future<void> dispose() async {
    state = EngineState.uninitialized;
  }
}

class EngineFactory {
  static TranscriberEngine createEngine() {
    if (kIsWeb) {
      return MockWebTranscriberEngine();
    } else {
      return NativeTranscriberEngine();
    }
  }
}

