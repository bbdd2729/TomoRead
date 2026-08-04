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

/// Finds a split point near the middle of a chapter while keeping surrogate
/// pairs intact, so chapter editing never splits a multi-code-unit character.
int safeTextChapterSplitOffset(String text) {
  if (text.length < 2) return text.length;
  final middle = text.length ~/ 2;
  final blankAfter = text.indexOf('\n\n', middle);
  if (blankAfter >= 0 && blankAfter + 2 < text.length) return blankAfter + 2;
  final lineAfter = text.indexOf('\n', middle);
  if (lineAfter >= 0 && lineAfter + 1 < text.length) return lineAfter + 1;
  var offset = middle.clamp(1, text.length - 1).toInt();
  final previous = text.codeUnitAt(offset - 1);
  final current = text.codeUnitAt(offset);
  if (previous >= 0xd800 &&
      previous <= 0xdbff &&
      current >= 0xdc00 &&
      current <= 0xdfff) {
    offset++;
  }
  return offset.clamp(1, text.length - 1).toInt();
}
