import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../features/transcriber/domain/engine/engine_failure.dart';
import '../../../features/transcriber/domain/ports/audio_capture.dart';

typedef CaptureDirectoryProvider = Future<Directory> Function();
typedef AudioRecorderFactory = AudioRecorder Function();

/// Windows microphone capture using the existing `record_windows` plugin.
///
/// Audio is written only to application-owned temporary storage:
/// `<temp>/persian_transcriber/captures/<captureId>/capture.wav`.
///
/// The adapter requests 16 kHz mono PCM WAV. Some devices reject that format,
/// so it falls back to 48 kHz stereo and lets the later FFmpeg preparation step
/// perform the canonical conversion. It never trusts the recorder's format
/// claim as a substitute for validating prepared audio.
final class WindowsMicrophoneCapture implements AudioCapture {
  WindowsMicrophoneCapture({
    CaptureDirectoryProvider? temporaryDirectory,
    AudioRecorderFactory? recorderFactory,
    Random? random,
  })  : _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
        _recorderFactory = recorderFactory ?? AudioRecorder.new,
        _random = random ?? Random.secure();

  static const _primaryConfig = RecordConfig(
    encoder: AudioEncoder.wav,
    sampleRate: 16000,
    numChannels: 1,
    autoGain: false,
    echoCancel: false,
    noiseSuppress: false,
  );

  static const _fallbackConfig = RecordConfig(
    encoder: AudioEncoder.wav,
    sampleRate: 48000,
    numChannels: 2,
    autoGain: false,
    echoCancel: false,
    noiseSuppress: false,
  );

  final CaptureDirectoryProvider _temporaryDirectory;
  final AudioRecorderFactory _recorderFactory;
  final Random _random;

  AudioRecorder? _recorder;
  String? _activeId;
  final _finishedIds = <String>{};
  bool _starting = false;
  bool _disposed = false;
  Future<void>? _disposal;

  @override
  Future<String> start() async {
    _ensureNotDisposed();
    if (_activeId != null || _starting) {
      throw const EngineFailure(
        EngineFailureCode.busy,
        'A microphone capture is already active.',
      );
    }

    _starting = true;
    try {
      final recorder = _recorder ??= _recorderFactory();
      final hasPermission = await _checkPermission(recorder);
      if (!hasPermission) {
        throw const EngineFailure(
          EngineFailureCode.permissionDenied,
          'Microphone permission was denied.',
        );
      }
      final supportsWav = await _checkWavSupport(recorder);
      if (!supportsWav) {
        throw const EngineFailure(
          EngineFailureCode.unsupported,
          'This build cannot record WAV audio from the microphone.',
        );
      }

      final captureId = _newCaptureId();
      final directory = await _captureDirectory(captureId);
      final file = File(p.join(directory.path, 'capture.wav'));
      try {
        await directory.create(recursive: true);
        await recorder.start(_primaryConfig, path: file.path);
      } on Object {
        await _cancelRecorderQuietly(recorder);
        try {
          await recorder.start(_fallbackConfig, path: file.path);
        } on Object {
          await _cancelRecorderQuietly(recorder);
          await _deleteQuietly(captureId);
          throw const EngineFailure(
            EngineFailureCode.ioError,
            'Microphone capture could not start.',
          );
        }
      }

      _activeId = captureId;
      return captureId;
    } finally {
      _starting = false;
    }
  }

  @override
  Future<void> stop(String captureId) async {
    _ensureNotDisposed();
    _requireCaptureId(captureId);
    if (_activeId != captureId) {
      // Already stopped, discarded or never active for this instance.
      return;
    }

    final directory = await _captureDirectory(captureId);
    final file = File(p.join(directory.path, 'capture.wav'));
    final recorder = _recorder;
    String? returnedPath;
    try {
      returnedPath = await recorder?.stop();
    } on Object {
      _activeId = null;
      await _deleteQuietly(captureId);
      throw const EngineFailure(
        EngineFailureCode.ioError,
        'Microphone capture could not be finalized.',
      );
    }

    _activeId = null;
    if (returnedPath == null) {
      await _deleteQuietly(captureId);
      throw const EngineFailure(
        EngineFailureCode.invalidAudio,
        'No microphone audio was captured.',
      );
    }

    final stat = await _statOrNull(file);
    if (stat == null ||
        stat.type != FileSystemEntityType.file ||
        stat.size <= 44) {
      await _deleteQuietly(captureId);
      throw const EngineFailure(
        EngineFailureCode.invalidAudio,
        'No microphone audio was captured.',
      );
    }
    _finishedIds.add(captureId);
  }

  @override
  Future<void> cancel(String captureId) async {
    _requireCaptureId(captureId);
    if (_activeId == captureId) {
      _activeId = null;
      await _cancelRecorderQuietly(_recorder);
    }
    _finishedIds.remove(captureId);
    await _deleteCapture(captureId);
  }

  @override
  Future<void> discard(String captureId) async {
    _requireCaptureId(captureId);
    if (_activeId == captureId) {
      _activeId = null;
      await _cancelRecorderQuietly(_recorder);
    }
    _finishedIds.remove(captureId);
    await _deleteCapture(captureId);
  }

  @override
  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;

    final active = _activeId;
    _activeId = null;
    if (active != null) {
      await _cancelRecorderQuietly(_recorder);
      await _deleteQuietly(active);
    }
    for (final captureId in _finishedIds.toList()) {
      await _deleteQuietly(captureId);
    }
    _finishedIds.clear();
    try {
      await _recorder?.dispose();
    } on Object {
      // The recorder is already being torn down; managed files are deleted
      // above and a later sweep can retry anything the OS still holds.
    }
  }

  Future<bool> _checkPermission(AudioRecorder recorder) async {
    try {
      return await recorder.hasPermission();
    } on Object {
      throw const EngineFailure(
        EngineFailureCode.ioError,
        'Microphone permission could not be checked.',
      );
    }
  }

  Future<bool> _checkWavSupport(AudioRecorder recorder) async {
    try {
      return await recorder.isEncoderSupported(AudioEncoder.wav);
    } on Object {
      throw const EngineFailure(
        EngineFailureCode.ioError,
        'Microphone capabilities could not be checked.',
      );
    }
  }

  Future<void> _cancelRecorderQuietly(AudioRecorder? recorder) async {
    if (recorder == null) return;
    try {
      await recorder.cancel();
    } on Object {
      // Best effort: the managed capture directory is deleted separately.
    }
  }

  Future<Directory> _captureDirectory(String captureId) async {
    final temporary = await _temporaryDirectory();
    return Directory(p.join(
      temporary.path,
      'persian_transcriber',
      'captures',
      _requireCaptureId(captureId),
    ));
  }

  Future<void> _deleteCapture(String captureId) async {
    final directory = await _captureDirectory(captureId);
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } on FileSystemException {
      throw const EngineFailure(
        EngineFailureCode.ioError,
        'Temporary microphone audio could not be removed.',
      );
    }
  }

  Future<FileStat?> _statOrNull(File file) async {
    try {
      return await FileStat.stat(file.path);
    } on FileSystemException {
      return null;
    }
  }

  Future<void> _deleteQuietly(String captureId) async {
    try {
      await _deleteCapture(captureId);
    } on EngineFailure {
      // Leave the directory for the next cleanup attempt/sweep.
    }
  }

  String _newCaptureId() {
    final time = DateTime.now().toUtc().microsecondsSinceEpoch;
    final random = _random.nextInt(0x7fffffff).toRadixString(16);
    return 'capture-$time-$random';
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw const EngineFailure(
        EngineFailureCode.disposed,
        'Microphone capture is disposed.',
      );
    }
  }

  String _requireCaptureId(String value) {
    if (!_captureIdPattern.hasMatch(value)) {
      throw const EngineFailure(
        EngineFailureCode.invalidRequest,
        'Invalid microphone capture identifier.',
      );
    }
    return value;
  }
}

final _captureIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');
