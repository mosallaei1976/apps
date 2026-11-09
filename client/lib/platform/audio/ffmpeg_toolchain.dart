import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../features/transcriber/domain/engine/engine_failure.dart';
import '../../features/transcriber/domain/ports/cancellation_signal.dart';
import 'audio_process_runner.dart';
import 'wav_format.dart';

/// Explicit, locally configured FFmpeg binary.
///
/// There is deliberately no discovery through PATH, an app-store bundle, the
/// network or a package manager. The caller supplies an absolute path and the
/// exact SHA-256 digest of the binary it trusts.
final class FfmpegToolchainConfig {
  FfmpegToolchainConfig({
    required String executablePath,
    required String expectedSha256,
    this.maxStderrBytes = 8192,
    this.selfTestTimeout = const Duration(seconds: 30),
    this.conversionTimeout = const Duration(minutes: 15),
  })  : executablePath = _validateExecutablePath(executablePath),
        expectedSha256 = _validateSha256(expectedSha256) {
    if (maxStderrBytes <= 0) {
      throw ArgumentError.value(
        maxStderrBytes,
        'maxStderrBytes',
        'Must be positive',
      );
    }
    if (selfTestTimeout <= Duration.zero) {
      throw ArgumentError.value(
        selfTestTimeout,
        'selfTestTimeout',
        'Must be positive',
      );
    }
    if (conversionTimeout <= Duration.zero) {
      throw ArgumentError.value(
        conversionTimeout,
        'conversionTimeout',
        'Must be positive',
      );
    }
  }

  static const executablePathEnvironmentVariable =
      'PERSIAN_TRANSCRIBER_FFMPEG_PATH';
  static const sha256EnvironmentVariable = 'PERSIAN_TRANSCRIBER_FFMPEG_SHA256';

  final String executablePath;
  final String expectedSha256;
  final int maxStderrBytes;
  final Duration selfTestTimeout;
  final Duration conversionTimeout;

  /// Reads the explicit local toolchain configuration.
  ///
  /// Returns null only when both variables are absent. A half-configured or
  /// malformed environment fails with [FormatException] so the composition root
  /// can fall back to an honest unavailable adapter instead of guessing.
  static FfmpegToolchainConfig? fromEnvironment([
    Map<String, String>? environment,
  ]) {
    final values = environment ?? Platform.environment;
    final rawPath = values[executablePathEnvironmentVariable]?.trim();
    final rawHash = values[sha256EnvironmentVariable]?.trim();
    final hasPath = rawPath != null && rawPath.isNotEmpty;
    final hasHash = rawHash != null && rawHash.isNotEmpty;
    if (!hasPath && !hasHash) return null;
    if (!hasPath || !hasHash) {
      throw const FormatException(
        'Both FFmpeg path and SHA-256 environment variables are required.',
      );
    }
    return FfmpegToolchainConfig(
      executablePath: rawPath,
      expectedSha256: rawHash,
    );
  }

  static String _validateExecutablePath(String value) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, 'executablePath', 'Must not be empty');
    }
    if (!p.isAbsolute(value)) {
      throw ArgumentError.value(
        value,
        'executablePath',
        'Must be an absolute path; PATH search is not allowed',
      );
    }
    if (!p.isAbsolute(p.normalize(value))) {
      throw ArgumentError.value(
        value,
        'executablePath',
        'Must remain an absolute path after normalization',
      );
    }
    return value;
  }

  static String _validateSha256(String value) {
    final normalized = value.trim().toLowerCase();
    if (!_sha256Pattern.hasMatch(normalized)) {
      throw ArgumentError.value(
        value,
        'expectedSha256',
        'Must be exactly 64 hexadecimal characters',
      );
    }
    return normalized;
  }
}

/// The exact, local-only FFmpeg command lines used by this application.
///
/// Conversion selects the first audio stream, strips metadata and subtitle/data
/// streams, resamples to 16 kHz mono signed 16-bit PCM and writes a WAV file.
/// The input protocol whitelist is restricted to `file`, so a local capture can
/// never make FFmpeg open an HTTP, RTMP or other network protocol.
abstract final class FfmpegCommands {
  static const List<String> selfTest = <String>[
    '-hide_banner',
    '-nostdin',
    '-loglevel',
    'error',
    '-f',
    'lavfi',
    '-i',
    'anullsrc=r=16000:cl=mono',
    '-t',
    '0.1',
    '-map',
    '0:a:0',
    '-ac',
    '1',
    '-ar',
    '16000',
    '-sample_fmt',
    's16',
    '-c:a',
    'pcm_s16le',
    '-f',
    'null',
    '-',
  ];

  static List<String> conversion({
    required String sourcePath,
    required String outputPath,
  }) {
    return <String>[
      '-hide_banner',
      '-nostdin',
      '-loglevel',
      'error',
      '-y',
      '-protocol_whitelist',
      'file',
      '-i',
      sourcePath,
      '-map',
      '0:a:0',
      '-vn',
      '-sn',
      '-dn',
      '-map_metadata',
      '-1',
      '-ac',
      '1',
      '-ar',
      '16000',
      '-sample_fmt',
      's16',
      '-c:a',
      'pcm_s16le',
      '-f',
      'wav',
      outputPath,
    ];
  }
}

/// Verified, capability-tested access to one local FFmpeg binary.
///
/// Readiness is cached after the first successful SHA-256 check and capability
/// self-test. FFmpeg is the only decoder; this class never reads user media
/// itself and never exposes paths to the domain.
final class FfmpegToolchain {
  FfmpegToolchain({
    required this.config,
    AudioProcessRunner? runner,
  }) : _runner = runner ?? const SystemAudioProcessRunner();

  final FfmpegToolchainConfig config;
  final AudioProcessRunner _runner;

  bool _ready = false;
  Future<void>? _readiness;

  Future<void> ensureReady({required CancellationSignal cancellation}) {
    if (_ready) return Future<void>.value();
    final pending = _readiness ??= _verifyAndSelfTest(cancellation);
    return pending.then<void>((_) {
      _ready = true;
    }).catchError((Object error, StackTrace stackTrace) {
      _readiness = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
  }

  /// Converts [sourcePath] to a canonical 16 kHz mono PCM WAV at [outputPath].
  ///
  /// The caller owns the output path and must place it inside the managed job
  /// directory. A partial or invalid output is removed before the failure is
  /// reported.
  Future<WavFormat> convertToPcmWav({
    required String sourcePath,
    required String outputPath,
    required CancellationSignal cancellation,
  }) async {
    if (!p.isAbsolute(sourcePath) || !p.isAbsolute(outputPath)) {
      throw const EngineFailure(
        EngineFailureCode.invalidRequest,
        'Audio paths must be absolute local paths.',
      );
    }
    if (p.equals(p.normalize(sourcePath), p.normalize(outputPath))) {
      throw const EngineFailure(
        EngineFailureCode.invalidRequest,
        'The prepared output must not replace the source audio.',
      );
    }

    await ensureReady(cancellation: cancellation);
    cancellation.throwIfCancelled();
    _deleteFileQuietly(outputPath);

    try {
      final result = await _runner.run(
        AudioProcessRequest(
          executablePath: config.executablePath,
          arguments: FfmpegCommands.conversion(
            sourcePath: sourcePath,
            outputPath: outputPath,
          ),
          maxStderrBytes: config.maxStderrBytes,
          timeout: config.conversionTimeout,
        ),
        cancellation: cancellation,
      );
      if (result.cancelled || cancellation.isCancelled) {
        throw const EngineFailure(
          EngineFailureCode.cancelled,
          'Audio preparation was cancelled.',
        );
      }
      if (result.timedOut) {
        throw const EngineFailure(
          EngineFailureCode.processingTimeout,
          'FFmpeg audio preparation timed out.',
        );
      }
      if (!result.succeeded) {
        throw EngineFailure(
          EngineFailureCode.invalidAudio,
          'FFmpeg could not prepare the captured audio'
          '${_stderrSuffix(result.stderr)}',
        );
      }

      final format = WavFormat.read(File(outputPath));
      if (format.duration <= Duration.zero) {
        throw const FormatException('Prepared audio has no positive duration.');
      }
      return format;
    } catch (error) {
      _deleteFileQuietly(outputPath);
      if (error is FormatException) {
        throw EngineFailure(
          EngineFailureCode.invalidAudio,
          'FFmpeg produced invalid PCM WAV audio: ${error.message}',
        );
      }
      if (error is FileSystemException) {
        throw const EngineFailure(
          EngineFailureCode.invalidAudio,
          'FFmpeg did not produce a readable prepared WAV file.',
        );
      }
      rethrow;
    }
  }

  Future<void> _verifyAndSelfTest(CancellationSignal cancellation) async {
    cancellation.throwIfCancelled();
    final executable = File(config.executablePath);
    final type = FileSystemEntity.typeSync(config.executablePath);
    if (type != FileSystemEntityType.file) {
      throw const EngineFailure(
        EngineFailureCode.unsupported,
        'The configured FFmpeg binary does not exist or is not a file.',
      );
    }
    final length = await executable.length();
    if (length <= 0) {
      throw const EngineFailure(
        EngineFailureCode.unsupported,
        'The configured FFmpeg binary is empty.',
      );
    }

    final digest = await _sha256(executable, cancellation);
    cancellation.throwIfCancelled();
    if (digest != config.expectedSha256) {
      throw const EngineFailure(
        EngineFailureCode.unsupported,
        'The configured FFmpeg binary failed SHA-256 verification.',
      );
    }

    final result = await _runner.run(
      AudioProcessRequest(
        executablePath: config.executablePath,
        arguments: FfmpegCommands.selfTest,
        maxStderrBytes: config.maxStderrBytes,
        timeout: config.selfTestTimeout,
      ),
      cancellation: cancellation,
    );
    if (result.cancelled || cancellation.isCancelled) {
      throw const EngineFailure(
        EngineFailureCode.cancelled,
        'FFmpeg capability self-test was cancelled.',
      );
    }
    if (result.timedOut) {
      throw const EngineFailure(
        EngineFailureCode.unsupported,
        'FFmpeg capability self-test timed out.',
      );
    }
    if (!result.succeeded) {
      throw EngineFailure(
        EngineFailureCode.unsupported,
        'FFmpeg lacks the required 16 kHz mono PCM WAV capability'
        '${_stderrSuffix(result.stderr)}',
      );
    }
  }

  Future<String> _sha256(File file, CancellationSignal cancellation) async {
    final sink = _DigestSink();
    final input = sha256.startChunkedConversion(sink);
    try {
      await for (final chunk in file.openRead()) {
        cancellation.throwIfCancelled();
        input.add(chunk);
      }
      input.close();
    } on Object {
      try {
        input.close();
      } on Object {
        // The original error is more useful.
      }
      rethrow;
    }
    cancellation.throwIfCancelled();
    final digest = sink.value;
    if (digest == null) {
      throw const EngineFailure(
        EngineFailureCode.unsupported,
        'The configured FFmpeg binary could not be hashed.',
      );
    }
    return digest.toString().toLowerCase();
  }

  static void _deleteFileQuietly(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // A later cleanup pass owns the managed job directory.
    }
  }

  static String _stderrSuffix(String stderr) {
    final trimmed = stderr.trim();
    if (trimmed.isEmpty) return '.';
    final tail = trimmed.length <= 400
        ? trimmed
        : trimmed.substring(trimmed.length - 400);
    return ': $tail';
  }
}

final class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}

final _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');
