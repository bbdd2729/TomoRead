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
/// so a stable whole-book page count does not exist. When available, parsed
/// chapter character counts provide the stable weighting and make the reader's
/// whole-book character position meaningful.
class EpubSectionProgress {
  const EpubSectionProgress._({
    required this._weights,
    required this._totalWeight,
    required this._characterCounts,
  });

  /// Legacy source-size weighting retained for old callers and fallbacks.
  factory EpubSectionProgress.fromSizes(List<int> sizes) {
    final result = EpubSectionProgress._fromWeights(
      sizes.map((size) => size > 0 ? size.toDouble() : 0.0).toList(),
    );
    return result._totalWeight > 0
        ? result
        : EpubSectionProgress.even(sizes.length);
  }

  factory EpubSectionProgress.fromCharacterCounts(List<int> characterCounts) {
    final normalized = characterCounts
        .map((count) => count < 0 ? 0 : count)
        .toList(growable: false);
    final result = EpubSectionProgress._fromWeights(
      normalized.map((count) => count.toDouble()).toList(growable: false),
      characterCounts: normalized,
    );
    return result._totalWeight > 0
        ? result
        : EpubSectionProgress.even(normalized.length);
  }

  factory EpubSectionProgress.even(int chapterCount) => EpubSectionProgress._(
    weights: List<double>.filled(chapterCount, 1),
    totalWeight: chapterCount.toDouble(),
    characterCounts: null,
  );

  factory EpubSectionProgress._fromWeights(
    List<double> weights, {
    List<int>? characterCounts,
  }) {
    final normalized = weights
        .map((weight) => weight > 0 ? weight : 0.0)
        .toList(growable: false);
    final totalWeight = normalized.fold<double>(
      0,
      (sum, weight) => sum + weight,
    );
    return EpubSectionProgress._(
      weights: normalized,
      totalWeight: totalWeight,
      characterCounts: characterCounts,
    );
  }

  final List<double> _weights;
  final double _totalWeight;
  final List<int>? _characterCounts;

  int get chapterCount => _weights.length;

  int get totalCharacters =>
      _characterCounts?.fold<int>(0, (sum, count) => sum + count) ?? 0;

  bool get hasCharacterCounts => _characterCounts != null;

  int? characterCountForChapter(int chapterIndex) {
    final counts = _characterCounts;
    if (counts == null || counts.isEmpty) return null;
    return counts[chapterIndex.clamp(0, counts.length - 1).toInt()];
  }

  int? characterPosition(
    int chapterIndex,
    double chapterRatio, {
    int? chapterCharacterOffset,
  }) {
    final counts = _characterCounts;
    if (counts == null || counts.isEmpty || totalCharacters <= 0) return null;
    final index = chapterIndex.clamp(0, counts.length - 1).toInt();
    final before = counts.take(index).fold<int>(0, (sum, count) => sum + count);
    final count = counts[index];
    final offset =
        (chapterCharacterOffset ?? (count * chapterRatio.clamp(0, 1)).round())
            .clamp(0, count)
            .toInt();
    return (before + offset).clamp(0, totalCharacters).toInt();
  }

  double overallProgress(
    int chapterIndex,
    double chapterRatio, {
    int? chapterCharacterOffset,
  }) {
    final characterPosition = this.characterPosition(
      chapterIndex,
      chapterRatio,
      chapterCharacterOffset: chapterCharacterOffset,
    );
    if (characterPosition != null && totalCharacters > 0) {
      return (characterPosition / totalCharacters).clamp(0, 1).toDouble();
    }
    if (_weights.isEmpty || _totalWeight <= 0) return 0;
    final index = chapterIndex.clamp(0, _weights.length - 1).toInt();
    final before = _weights
        .take(index)
        .fold<double>(0, (sum, size) => sum + size);
    return ((before + _weights[index] * chapterRatio.clamp(0, 1)) /
            _totalWeight)
        .clamp(0, 1)
        .toDouble();
  }

  EpubSectionLocation locationForProgress(double progress) {
    if (_weights.isEmpty || _totalWeight <= 0) {
      return const EpubSectionLocation(chapterIndex: 0, chapterRatio: 0);
    }
    final target = progress.clamp(0, 1).toDouble();
    if (target >= 1) {
      final lastIndex = _weights.lastIndexWhere((size) => size > 0);
      return EpubSectionLocation(
        chapterIndex: lastIndex < 0 ? _weights.length - 1 : lastIndex,
        chapterRatio: 1,
      );
    }

    var consumed = 0.0;
    for (var index = 0; index < _weights.length; index++) {
      final size = _weights[index];
      if (size <= 0) continue;
      final end = consumed + size / _totalWeight;
      if (target < end) {
        return EpubSectionLocation(
          chapterIndex: index,
          chapterRatio: ((target - consumed) / (size / _totalWeight))
              .clamp(0, 1)
              .toDouble(),
        );
      }
      consumed = end;
    }

    return EpubSectionLocation(
      chapterIndex: _weights.length - 1,
      chapterRatio: 1,
    );
  }
}
