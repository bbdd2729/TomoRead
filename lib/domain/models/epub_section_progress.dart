class EpubSectionLocation {
  const EpubSectionLocation({
    required this.chapterIndex,
    required this.chapterRatio,
  });

  final int chapterIndex;
  final double chapterRatio;
}

/// Maps a location within an EPUB spine item to a location in the book.
///
/// EPUB pages are reflowed whenever the viewport or reading settings change,
/// so a stable whole-book page count does not exist. Source sizes provide a
/// content-weighted locator without forcing every chapter to be paginated.
class EpubSectionProgress {
  const EpubSectionProgress._({required this._sizes, required this._totalSize});

  factory EpubSectionProgress.fromSizes(List<int> sizes) {
    final normalized = sizes
        .map((size) => size > 0 ? size.toDouble() : 0.0)
        .toList(growable: false);
    final totalSize = normalized.fold<double>(0, (sum, size) => sum + size);
    if (totalSize > 0) {
      return EpubSectionProgress._(sizes: normalized, totalSize: totalSize);
    }
    return EpubSectionProgress.even(sizes.length);
  }

  factory EpubSectionProgress.even(int chapterCount) => EpubSectionProgress._(
    sizes: List<double>.filled(chapterCount, 1),
    totalSize: chapterCount.toDouble(),
  );

  final List<double> _sizes;
  final double _totalSize;

  int get chapterCount => _sizes.length;

  double overallProgress(int chapterIndex, double chapterRatio) {
    if (_sizes.isEmpty || _totalSize <= 0) return 0;
    final index = chapterIndex.clamp(0, _sizes.length - 1).toInt();
    final before = _sizes
        .take(index)
        .fold<double>(0, (sum, size) => sum + size);
    return ((before + _sizes[index] * chapterRatio.clamp(0, 1)) / _totalSize)
        .clamp(0, 1)
        .toDouble();
  }

  EpubSectionLocation locationForProgress(double progress) {
    if (_sizes.isEmpty || _totalSize <= 0) {
      return const EpubSectionLocation(chapterIndex: 0, chapterRatio: 0);
    }
    final target = progress.clamp(0, 1).toDouble();
    if (target >= 1) {
      final lastIndex = _sizes.lastIndexWhere((size) => size > 0);
      return EpubSectionLocation(
        chapterIndex: lastIndex < 0 ? _sizes.length - 1 : lastIndex,
        chapterRatio: 1,
      );
    }

    var consumed = 0.0;
    for (var index = 0; index < _sizes.length; index++) {
      final size = _sizes[index];
      if (size <= 0) continue;
      final end = consumed + size / _totalSize;
      if (target < end) {
        return EpubSectionLocation(
          chapterIndex: index,
          chapterRatio: ((target - consumed) / (size / _totalSize))
              .clamp(0, 1)
              .toDouble(),
        );
      }
      consumed = end;
    }

    return EpubSectionLocation(
      chapterIndex: _sizes.length - 1,
      chapterRatio: 1,
    );
  }
}
