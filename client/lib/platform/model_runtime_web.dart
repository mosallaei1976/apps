import '../features/transcriber/domain/ports/verified_model_access.dart';
import 'stub_services.dart';

/// Browser model storage and verification are not implemented or validated.
VerifiedModelAccess createVerifiedModelAccess() =>
    const UnavailableVerifiedModelAccess();
