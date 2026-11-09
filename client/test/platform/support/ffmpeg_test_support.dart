import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// A compiled local executable with a documented SHA-256 digest.
///
/// Using a real executable (rather than a shell script) makes process
/// cancellation tests meaningful on Windows and keeps the production runner's
/// absolute-path/no-shell contract intact.
final class FakeFfmpeg {
  FakeFfmpeg({
    required this.root,
    required this.executable,
    required this.sha256,
  });

  final Directory root;
  final File executable;
  final String sha256;

  Directory get controlDirectory => executable.parent;

  File _control(String name) => File(p.join(controlDirectory.path, name));

  Future<void> clearControls() async {
    for (final name in const <String>[
      'delay_ms.txt',
      'fail.txt',
      'invalid_wav.txt',
      'calls.log',
    ]) {
      final file = _control(name);
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> setDelay(Duration delay) async {
    await _control('delay_ms.txt').writeAsString(
      delay.inMilliseconds.toString(),
      flush: true,
    );
  }

  Future<void> setFailure(int exitCode) async {
    await _control('fail.txt').writeAsString(
      exitCode.toString(),
      flush: true,
    );
  }

  Future<void> setInvalidWav() async {
    await _control('invalid_wav.txt').writeAsString('1', flush: true);
  }

  Future<String> calls() async {
    final file = _control('calls.log');
    if (!await file.exists()) return '';
    return file.readAsString();
  }

  Future<void> dispose() async {
    if (await root.exists()) await root.delete(recursive: true);
  }
}

Future<FakeFfmpeg> compileFakeFfmpeg() async {
  final root = await Directory.systemTemp.createTemp('fake-ffmpeg-');
  final script = File(
    p.join(
      Directory.current.path,
      'test',
      'platform',
      'support',
      'fake_ffmpeg.dart',
    ),
  );
  if (!await script.exists()) {
    throw StateError('Fake FFmpeg source was not found at ${script.path}.');
  }

  final output = p.join(
    root.path,
    Platform.isWindows ? 'fake_ffmpeg.exe' : 'fake_ffmpeg',
  );
  final result = await Process.run(
    _dartExecutable(),
    <String>['compile', 'exe', script.path, '-o', output],
  );
  if (result.exitCode != 0) {
    throw StateError(
      'Could not compile fake FFmpeg:\n${result.stdout}\n${result.stderr}',
    );
  }

  final file = File(output);
  final digest = sha256.convert(await file.readAsBytes()).toString();
  return FakeFfmpeg(root: root, executable: file, sha256: digest);
}

String _dartExecutable() {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null && flutterRoot.isNotEmpty) {
    final candidate = p.join(
      flutterRoot,
      'bin',
      'cache',
      'dart-sdk',
      'bin',
      Platform.isWindows ? 'dart.exe' : 'dart',
    );
    if (File(candidate).existsSync()) return candidate;
  }
  return Platform.isWindows ? 'dart.exe' : 'dart';
}
