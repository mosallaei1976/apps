abstract interface class CancellationSignal {
  bool get isCancelled;

  Future<void> get whenCancelled;

  void throwIfCancelled();
}
