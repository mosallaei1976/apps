import '../features/transcriber/domain/engine/abstract_engine_interface.dart';
import 'engine_factory_native.dart'
    if (dart.library.js_interop) 'engine_factory_web.dart' as platform;

class EngineFactory {
  static AbstractEngineInterface createEngine() => platform.createEngine();
}
