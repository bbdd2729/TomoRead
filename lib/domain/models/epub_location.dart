class EpubLocation {
  const EpubLocation({
    required this.chapterIndex,
    required this.scrollRatio,
    this.anchor,
  });

  final int chapterIndex;
  final double scrollRatio;
  final String? anchor;

  String toLocator() {
    final encodedAnchor = anchor == null ? '' : Uri.encodeComponent(anchor!);
    return 'epub:v2|$chapterIndex|${scrollRatio.clamp(0, 1).toStringAsFixed(5)}|$encodedAnchor';
  }

  static bool matchesLocator(
    String locator,
    EpubLocation location, {
    required int fallbackChapterIndex,
  }) {
    final candidate = fromLocator(
      locator,
      fallbackChapterIndex: fallbackChapterIndex,
    );
    if (candidate.chapterIndex != location.chapterIndex) return false;
    if (candidate.anchor != null && location.anchor != null) {
      return candidate.anchor == location.anchor;
    }
    return (candidate.scrollRatio - location.scrollRatio).abs() <= 0.00001;
  }

  static EpubLocation fromLocator(
    String? locator, {
    required int fallbackChapterIndex,
  }) {
    if (locator != null && locator.startsWith('epub:v2|')) {
      final parts = locator.substring('epub:v2|'.length).split('|');
      final chapterIndex = int.tryParse(parts.first) ?? fallbackChapterIndex;
      final scrollRatio = parts.length > 1
          ? (double.tryParse(parts[1]) ?? 0).clamp(0, 1).toDouble()
          : 0.0;
      final anchor = parts.length > 2 && parts[2].isNotEmpty
          ? Uri.decodeComponent(parts[2])
          : null;
      return EpubLocation(
        chapterIndex: chapterIndex,
        scrollRatio: scrollRatio,
        anchor: anchor,
      );
    }

    if (locator != null && locator.startsWith('epub:')) {
      final parts = locator.substring(5).split('|');
      final chapterIndex = int.tryParse(parts.first) ?? fallbackChapterIndex;
      final scrollRatio = parts.length > 1
          ? (double.tryParse(parts[1]) ?? 0).clamp(0, 1).toDouble()
          : 0.0;
      final anchor = parts.length > 2 && parts[2].isNotEmpty
          ? Uri.decodeComponent(parts[2])
          : null;
      return EpubLocation(
        chapterIndex: chapterIndex,
        scrollRatio: scrollRatio,
        anchor: anchor,
      );
    }

    final legacyChapterBookmark = RegExp(
      r'^chapter-(\d+):start$',
    ).firstMatch(locator ?? '');
    if (legacyChapterBookmark != null) {
      return EpubLocation(
        chapterIndex: int.parse(legacyChapterBookmark.group(1)!),
        scrollRatio: 0,
      );
    }

    final parts = locator?.split(':');
    if (parts != null && parts.length == 2) {
      return EpubLocation(
        chapterIndex: int.tryParse(parts.first) ?? fallbackChapterIndex,
        scrollRatio: (double.tryParse(parts.last) ?? 0).clamp(0, 1).toDouble(),
      );
    }

    return EpubLocation(chapterIndex: fallbackChapterIndex, scrollRatio: 0);
  }
}
