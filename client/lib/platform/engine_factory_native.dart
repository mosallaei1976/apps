import '../features/transcriber/domain/engine/abstract_engine_interface.dart';
import 'stub_engines.dart';

AbstractEngineInterface createEngine() => NativeFfiEngine();
