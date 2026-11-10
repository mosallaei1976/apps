import '../features/transcriber/application/model_management_bundle.dart';
import 'model_management_runtime_native.dart'
    if (dart.library.js_interop) 'model_management_runtime_web.dart' as platform;

ModelManagementBundle createModelManagementBundle() =>
    platform.createModelManagementBundle();
