import 'dart:async';
import 'dart:io';

import '../../features/transcriber/domain/engine/abstract_engine_interface.dart';
import '../audio/wav_format.dart';
import 'whisper_inference_runner.dart';
import 'whisper_paths.dart';
import 'whisper_toolchain.dart';

/// Native whisper.cpp inference behind the canonical engine port.
///
/// The engine only accepts time-limited, validated 16 kHz mono PCM WAV files
/// produced by the managed preparation adapter. Native inference runs in the
/// injected worker isolate runner; this class owns domain lifecycle, segment
/// validation, cancellation and typed failure translation.
final class WhisperFfiEngine implements AbstractEngineInterface {
  WhisperFfiEngine({
    required WhisperToolchainConfig toolchainConfig,
    required WhisperInferenceRunner runner,
    required WhisperPathResolver paths,
  })  : _config = toolchainConfig,
        _runner = runner,
        _paths = paths;

  final WhisperToolchainConfig _config;
  final WhisperInferenceRunner _runner;
  final WhisperPathResolver _paths;

  final StreamController<EngineStatus> _statuses =
      StreamController<EngineStatus>.broadcast();
  final StreamController<ModelLoadProgress> _progress =
      StreamController<ModelLoadProgress>.broadcast();

  EngineStatus _status = EngineStatus.uninitialized;
  ModelSpec? _loadedModel;
  bool _disposed = false;
  Future<void>? _disposal;

  String? _activeJobId;
  StreamController<TranscriptionEvent>? _activeOutput;
  StreamSubscription<WhisperInferenceEvent>? _activeSubscription;
  Completer<void>? _jobDone;
  Future<void>? _cancelFuture;
  bool _cancelRequested = false;
  bool _jobFinished = true;
  double? _lastProgress;

  @override
  EngineStatus get status => _status;

  @override
  Stream<EngineStatus> get statusChanges => _statuses.stream;

  @override
  Stream<ModelLoadProgress> get modelLoadProgress => _progress.stream;

  @override
  Future<void> initialize() async {
    _ensureNotDisposed();
    if (_status == EngineStatus.initialized || _status == EngineStatus.ready) {
      return;
    }
    _ensureIdle();
    try {
      final libraryPath = await _paths.libraryPath(_config);
      await _runner.initialize(
        libraryPath: libraryPath,
        expectedSha256: _config.expectedSha256,
      );
      _ensureNotDisposed();
      _setStatus(EngineStatus.initialized);
    } on EngineFailure {
      if (!_disposed) _setStatus(EngineStatus.failed);
      rethrow;
    } on Object {
      if (!_disposed) _setStatus(EngineStatus.failed);
      throw const EngineFailure(
        EngineFailureCode.initializationFailed,
        'The whisper.cpp runtime could not be initialized.',
      );
    }
  }

  @override
  Future<void> loadModel(ModelSpec model) async {
    _ensureNotDisposed();
    _ensureIdle();
    if (_status != EngineStatus.initialized && _status != EngineStatus.ready) {
      throw const EngineFailure(
        EngineFailureCode.notReady,
        'Initialize the whisper.cpp runtime before loading a model.',
      );
    }

    _setStatus(EngineStatus.loadingModel);
    _addProgress(ModelLoadProgress(modelId: model.id, fraction: 0));
    try {
      final modelPath = await _paths.modelPath(model);
      await _runner.loadModel(modelPath: modelPath);
      _ensureNotDisposed();
      _loadedModel = model;
      _addProgress(ModelLoadProgress(modelId: model.id, fraction: 1));
      _setStatus(EngineStatus.ready);
    } on EngineFailure {
      _loadedModel = null;
      if (!_disposed) _setStatus(EngineStatus.initialized);
      rethrow;
    } on Object {
      _loadedModel = null;
      if (!_disposed) _setStatus(EngineStatus.initialized);
      throw const EngineFailure(
        EngineFailureCode.modelLoadFailed,
        'whisper.cpp could not load the verified model artifact.',
      );
    }
  }

  @override
  Future<void> unloadModel() async {
    _ensureNotDisposed();
    _ensureIdle();
    if (_status == EngineStatus.uninitialized) return;
    await _runner.unloadModel();
    _loadedModel = null;
    if (_status == EngineStatus.ready) _setStatus(EngineStatus.initialized);
  }

  @override
  Stream<TranscriptionEvent> transcribe(
    PreparedAudio audio, {
    required String jobId,
    required TranscriptionOptions options,
  }) {
    late StreamController<TranscriptionEvent> output;
    output = StreamController<TranscriptionEvent>(
      onListen: () {
        try {
          _ensureNotDisposed();
          if (jobId.trim().isEmpty) {
            throw const EngineFailure(
              EngineFailureCode.invalidRequest,
              'Empty job ID.',
            );
          }
          if (_activeJobId != null) {
            throw const EngineFailure(
              EngineFailureCode.busy,
              'A transcription is already active.',
            );
          }
          if (_status != EngineStatus.ready || _loadedModel == null) {
            throw const EngineFailure(
              EngineFailureCode.notReady,
              'Load a verified model before transcribing.',
            );
          }
          _admit(output, audio, jobId, options);
        } on EngineFailure catch (failure) {
          output.addError(failure);
          unawaited(output.close());
        }
      },
      onCancel: () {
        if (!_jobFinished && identical(_activeOutput, output)) {
          return _requestCancel();
        }
      },
    );
    return output.stream;
  }

  @override
  Future<void> cancel(String jobId) {
    if (_jobFinished || _activeJobId == null || _activeJobId != jobId) {
      return Future<void>.value();
    }
    return _requestCancel();
  }

  @override
  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (!_jobFinished && _activeJobId != null) {
      try {
        await _requestCancel();
      } on Object {
        _finishJob();
      }
    }
    try {
      await _runner.dispose();
    } on Object {
      // The engine is still disposed; native cleanup is best effort.
    }
    _setStatus(EngineStatus.disposed);
    await Future.wait([
      _statuses.close(),
      _progress.close(),
    ]);
  }

  void _admit(
    StreamController<TranscriptionEvent> output,
    PreparedAudio audio,
    String jobId,
    TranscriptionOptions options,
  ) {
    _activeJobId = jobId;
    _activeOutput = output;
    _jobDone = Completer<void>();
    _cancelFuture = null;
    _cancelRequested = false;
    _jobFinished = false;
    _lastProgress = null;
    _setStatus(EngineStatus.transcribing);
    unawaited(_startJob(audio, jobId, options));
  }

  Future<void> _startJob(
    PreparedAudio audio,
    String jobId,
    TranscriptionOptions options,
  ) async {
    try {
      final audioPath = await _paths.preparedAudioPath(audio);
      final WavFormat format;
      try {
        format = WavFormat.read(File(audioPath));
      } on FormatException catch (error) {
        throw EngineFailure(
          EngineFailureCode.invalidAudio,
          'Prepared audio failed validation: ${error.message}',
        );
      } on FileSystemException {
        throw const EngineFailure(
          EngineFailureCode.invalidAudio,
          'Prepared audio could not be read.',
        );
      }
      if (format.duration != audio.duration) {
        throw const EngineFailure(
          EngineFailureCode.invalidAudio,
          'Prepared audio duration does not match the prepared descriptor.',
        );
      }
      if (_jobFinished) return;
      if (_cancelRequested) {
        _finishCancelled();
        return;
      }

      final stream = _runner.transcribe(WhisperInferenceRequest(
        requestId: jobId,
        audioPath: audioPath,
        audioDuration: format.duration,
        languageCode: options.languageCode,
        emitPartials: options.emitPartials,
      ));
      _activeSubscription = stream.listen(
        (event) => _onRunnerEvent(event, audio, jobId),
        onError: _failJob,
        onDone: () {
          if (!_jobFinished) {
            _failJob(const EngineFailure(
              EngineFailureCode.inferenceFailed,
              'whisper.cpp closed without a terminal event.',
            ));
          }
        },
        cancelOnError: false,
      );
      if (_cancelRequested) {
        unawaited(_runner.cancel(jobId));
      }
    } on EngineFailure catch (failure) {
      _failJob(failure);
    } on Object {
      _failJob(const EngineFailure(
        EngineFailureCode.inferenceFailed,
        'whisper.cpp inference could not start.',
      ));
    }
  }

  void _onRunnerEvent(
    WhisperInferenceEvent event,
    PreparedAudio audio,
    String jobId,
  ) {
    if (_jobFinished) return;
    switch (event) {
      case WhisperInferenceProgress(:final fraction):
        final normalized = fraction.clamp(0.0, 1.0).toDouble();
        if (_lastProgress != null && normalized <= _lastProgress!) return;
        _lastProgress = normalized;
        _activeOutput?.add(
          TranscriptionProgress(jobId: jobId, fraction: normalized),
        );
      case WhisperInferenceSegments(:final segments):
        for (final segment in segments) {
          if (segment.start.isNegative ||
              segment.end < segment.start ||
              segment.end > audio.duration) {
            _failJob(const EngineFailure(
              EngineFailureCode.inferenceFailed,
              'whisper.cpp returned a segment outside the prepared audio.',
            ));
            return;
          }
          try {
            _activeOutput?.add(TranscriptSegment(
              jobId: jobId,
              segmentId: segment.segmentId,
              text: segment.text,
              start: segment.start,
              end: segment.end,
              isFinal: true,
            ));
          } on ArgumentError {
            _failJob(const EngineFailure(
              EngineFailureCode.inferenceFailed,
              'whisper.cpp returned an invalid transcript segment.',
            ));
            return;
          }
        }
      case WhisperInferenceCompleted():
        _completeJob(jobId);
      case WhisperInferenceCancelled():
        _finishCancelled();
    }
  }

  void _completeJob(String jobId) {
    if (_jobFinished) return;
    if (_lastProgress == null || _lastProgress! < 1) {
      _activeOutput?.add(
        TranscriptionProgress(jobId: jobId, fraction: 1),
      );
    }
    _activeOutput?.add(TranscriptionCompleted(jobId));
    _finishJob();
  }

  void _finishCancelled() {
    if (_jobFinished) return;
    final jobId = _activeJobId;
    if (jobId != null) {
      _activeOutput?.add(TranscriptionCancelled(jobId));
    }
    _finishJob();
  }

  void _failJob(Object error) {
    if (_jobFinished) return;
    final failure = error is EngineFailure
        ? error
        : const EngineFailure(
            EngineFailureCode.inferenceFailed,
            'whisper.cpp inference failed.',
          );
    _activeOutput?.addError(failure);
    _finishJob();
  }

  Future<void> _requestCancel() {
    if (_jobFinished || _activeJobId == null) {
      return Future<void>.value();
    }
    final existing = _cancelFuture;
    if (existing != null) return existing;

    _cancelRequested = true;
    _setStatus(EngineStatus.cancelling);
    final jobId = _activeJobId!;
    return _cancelFuture = () async {
      try {
        await _runner.cancel(jobId);
      } on Object catch (error) {
        _failJob(error is EngineFailure
            ? error
            : const EngineFailure(
                EngineFailureCode.inferenceFailed,
                'whisper.cpp cancellation failed.',
              ));
      }
      final done = _jobDone;
      if (done != null) await done.future;
    }();
  }

  void _finishJob() {
    if (_jobFinished) return;
    _jobFinished = true;
    _activeJobId = null;
    _cancelRequested = false;
    _cancelFuture = null;

    final subscription = _activeSubscription;
    _activeSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());

    final output = _activeOutput;
    _activeOutput = null;
    if (output != null) unawaited(output.close());

    final done = _jobDone;
    _jobDone = null;
    if (done != null && !done.isCompleted) done.complete();

    if (!_disposed) _setStatus(EngineStatus.ready);
  }

  void _ensureNotDisposed() {
    if (_disposed || _status == EngineStatus.disposed) {
      throw const EngineFailure(
        EngineFailureCode.disposed,
        'The whisper.cpp engine is disposed.',
      );
    }
  }

  void _ensureIdle() {
    if (_status == EngineStatus.loadingModel ||
        _status == EngineStatus.transcribing ||
        _status == EngineStatus.cancelling) {
      throw const EngineFailure(
        EngineFailureCode.busy,
        'The whisper.cpp engine is busy.',
      );
    }
  }

  void _addProgress(ModelLoadProgress progress) {
    if (!_progress.isClosed) _progress.add(progress);
  }

  void _setStatus(EngineStatus status) {
    if (_status == status) return;
    _status = status;
    if (!_statuses.isClosed) _statuses.add(status);
  }
}
