enum EngineFailureCode {
  notReady,
  busy,
  modelUnavailable,
  initializationFailed,
  modelLoadFailed,
  ioError,
  processingTimeout,
  cancelled,
  invalidAudio,
  invalidRequest,
  permissionDenied,
  unsupported,
  inferenceFailed,
  disposed,
  unknown,
}

final class EngineFailure implements Exception {
  const EngineFailure(this.code, this.message);

  final EngineFailureCode code;
  final String message;

  @override
  String toString() => 'EngineFailure(${code.name}): $message';
}
