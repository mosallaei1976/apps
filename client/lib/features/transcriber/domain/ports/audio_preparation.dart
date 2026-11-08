import '../engine/engine_types.dart';
import 'cancellation_signal.dart';

abstract interface class AudioPreparation {
  Future<List<PreparedAudio>> prepare({
    required String sourceId,
    required String jobId,
    required CancellationSignal cancellation,
  });

  Future<void> cleanup(String jobId);
}
