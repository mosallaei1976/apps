import 'dart:async';

import '../features/transcriber/domain/engine/abstract_engine_interface.dart';

final class NativeFfiEngine extends _UnavailableEngine {
  NativeFfiEngine([
    super.reason =
        'Native whisper.cpp inference is not configured in this build.',
  ]);
}

final class WasmWebWorkerEngine extends _UnavailableEngine {
  WasmWebWorkerEngine()
      : super('WASM worker inference has not been implemented or validated.');
}

abstract class _UnavailableEngine implements AbstractEngineInterface {
  _UnavailableEngine(String reason) : _reason = reason;

  final String _reason;
  final StreamController<EngineStatus> _statuses =
      StreamController<EngineStatus>.broadcast();
  final StreamController<ModelLoadProgress> _progress =
      StreamController<ModelLoadProgress>.broadcast();
  EngineStatus _status = EngineStatus.uninitialized;
  Future<void>? _disposal;

  @override
  EngineStatus get status => _status;

  @override
  Stream<EngineStatus> get statusChanges => _statuses.stream;

  @override
  Stream<ModelLoadProgress> get modelLoadProgress => _progress.stream;

  @override
  Future<void> initialize() async {
    _ensureNotDisposed();
    _setStatus(EngineStatus.failed);
    throw EngineFailure(EngineFailureCode.unsupported, _reason);
  }

  @override
  Future<void> loadModel(ModelSpec model) async {
    _ensureNotDisposed();
    throw EngineFailure(EngineFailureCode.notReady, _reason);
  }

  @override
  Future<void> unloadModel() async {
    _ensureNotDisposed();
  }

  @override
  Stream<TranscriptionEvent> transcribe(
    PreparedAudio audio, {
    required String jobId,
    required TranscriptionOptions options,
  }) async* {
    _ensureNotDisposed();
    if (jobId.trim().isEmpty) {
      throw const EngineFailure(
          EngineFailureCode.invalidRequest, 'Empty job ID.');
    }
    throw EngineFailure(EngineFailureCode.notReady, _reason);
  }

  @override
  Future<void> cancel(String jobId) async {}

  @override
  Future<void> dispose() {
    if (_disposal != null) {
      return _disposal!;
    }
    _setStatus(EngineStatus.disposed);
    return _disposal =
        Future.wait([_statuses.close(), _progress.close()]).then<void>((_) {});
  }

  void _setStatus(EngineStatus status) {
    if (_status != status) {
      _status = status;
      _statuses.add(status);
    }
  }

  void _ensureNotDisposed() {
    if (_status == EngineStatus.disposed) {
      throw const EngineFailure(
          EngineFailureCode.disposed, 'Engine is disposed.');
    }
  }
}
