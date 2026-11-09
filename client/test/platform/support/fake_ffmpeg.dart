import 'dart:async';
import 'dart:io';

import 'wav_fixture.dart';

/// Local fake for FFmpeg toolchain and worker tests.
///
/// The executable directory controls behavior through small files:
/// - `delay_ms.txt`: delay before doing anything
/// - `fail.txt`: write a long diagnostic to stderr and exit with this code
/// - `invalid_wav.txt`: write non-WAV bytes instead of valid prepared audio
/// - `calls.log`: append every invocation's arguments
Future<void> main(List<String> args) async {
  final executable = File(Platform.resolvedExecutable);
  final directory = executable.parent;
  final separator = Platform.pathSeparator;

  await File('${directory.path}${separator}calls.log').writeAsString(
    '${args.join(' ')}\n',
    mode: FileMode.append,
    flush: true,
  );

  final delayFile = File('${directory.path}${separator}delay_ms.txt');
  if (await delayFile.exists()) {
    final milliseconds = int.tryParse(await delayFile.readAsString()) ?? 0;
    await Future<void>.delayed(Duration(milliseconds: milliseconds));
  }

  final failFile = File('${directory.path}${separator}fail.txt');
  if (await failFile.exists()) {
    final code = int.tryParse(await failFile.readAsString()) ?? 1;
    stderr.writeln(
      'fake ffmpeg failure: ${'x' * 6000}',
    );
    exit(code);
  }

  final isSelfTest = args.contains('lavfi') && args.last == '-';
  if (isSelfTest) exit(0);

  if (args.isEmpty) {
    stderr.writeln('fake ffmpeg: no output path');
    exit(2);
  }

  final outputPath = args.last;
  final output = File(outputPath);
  await output.parent.create(recursive: true);

  final invalidFile = File('${directory.path}${separator}invalid_wav.txt');
  if (await invalidFile.exists()) {
    await output.writeAsBytes(<int>[0x00, 0x01, 0x02, 0x03], flush: true);
    exit(0);
  }

  await output.writeAsBytes(wavBytes(), flush: true);
  exit(0);
}
