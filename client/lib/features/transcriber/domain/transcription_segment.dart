enum EngineState {
  uninitialized,
  loadingModel,
  ready,
  transcribing,
  error,
}

class TranscriptionSegment {
  final Duration start;
  final Duration end;
  final String text;
  final double confidence;

  const TranscriptionSegment({
    required this.start,
    required this.end,
    required this.text,
    this.confidence = 1.0,
  });

  @override
  String toString() => '[${start.inSeconds}s -> ${end.inSeconds}s]: $text';
}
