/// A text-reader position update waiting for the debounced persistence callback.
class PendingTextReaderProgress {
  const PendingTextReaderProgress({
    required this.chapterIndex,
    required this.progress,
    required this.locator,
  });

  final int chapterIndex;
  final double progress;
  final String locator;
}
