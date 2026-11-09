import '../features/transcriber/domain/ports/verified_model_access.dart';
import 'model_runtime_native.dart'
    if (dart.library.js_interop) 'model_runtime_web.dart' as platform;

VerifiedModelAccess createVerifiedModelAccess() =>
    platform.createVerifiedModelAccess();
