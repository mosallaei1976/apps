import '../engine/engine_types.dart';
import 'cancellation_signal.dart';

abstract interface class VerifiedModelAccess {
  Future<ModelSpec> resolveVerified(
    ModelTier tier, {
    required CancellationSignal cancellation,
  });
}
