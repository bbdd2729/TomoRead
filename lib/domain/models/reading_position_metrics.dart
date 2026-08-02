enum ReadingPositionUnit { line, character, progress }

class ReadingPositionMetrics {
  const ReadingPositionMetrics({
    required this.progress,
    required this.unit,
    required this.current,
    required this.total,
    required this.isApproximate,
    this.version = 1,
  });

  factory ReadingPositionMetrics.lines({
    required int current,
    required int total,
    required double progress,
    bool isApproximate = false,
  }) => ReadingPositionMetrics(
    progress: _normalizeProgress(progress),
    unit: ReadingPositionUnit.line,
    current: _normalizeCurrent(current, total),
    total: total < 0 ? 0 : total,
    isApproximate: isApproximate,
  );

  factory ReadingPositionMetrics.characters({
    required double progress,
    required int total,
    bool isApproximate = true,
  }) {
    final normalizedProgress = _normalizeProgress(progress);
    final normalizedTotal = total < 0 ? 0 : total;
    return ReadingPositionMetrics(
      progress: normalizedProgress,
      unit: normalizedTotal == 0
          ? ReadingPositionUnit.progress
          : ReadingPositionUnit.character,
      current: normalizedTotal == 0
          ? 0
          : (normalizedProgress * normalizedTotal)
                .round()
                .clamp(1, normalizedTotal)
                .toInt(),
      total: normalizedTotal,
      isApproximate: isApproximate,
    );
  }

  factory ReadingPositionMetrics.progressOnly(double progress) =>
      ReadingPositionMetrics(
        progress: _normalizeProgress(progress),
        unit: ReadingPositionUnit.progress,
        current: 0,
        total: 0,
        isApproximate: true,
      );

  final double progress;
  final ReadingPositionUnit unit;
  final int current;
  final int total;
  final bool isApproximate;
  final int version;

  String get label {
    final percent = (progress * 100).round();
    return switch (unit) {
      ReadingPositionUnit.line =>
        '全文${isApproximate ? '约' : ''}第 $current / $total 行 · $percent%',
      ReadingPositionUnit.character =>
        '全文${isApproximate ? '约' : ''}第 $current / $total 字 · $percent%',
      ReadingPositionUnit.progress => '全书 $percent%',
    };
  }

  static double _normalizeProgress(double value) =>
      value.isFinite ? value.clamp(0, 1).toDouble() : 0;

  static int _normalizeCurrent(int current, int total) {
    if (total <= 0) return 0;
    return current.clamp(1, total).toInt();
  }
}

class ReadingTextPositionIndex {
  ReadingTextPositionIndex._({
    required this.textLength,
    required this._lineStarts,
  });

  factory ReadingTextPositionIndex.fromText(String text) {
    final starts = <int>[0];
    for (var index = 0; index < text.length; index++) {
      if (text.codeUnitAt(index) == 0x0a && index + 1 < text.length) {
        starts.add(index + 1);
      }
    }
    return ReadingTextPositionIndex._(
      textLength: text.length,
      lineStarts: starts,
    );
  }

  final int textLength;
  final List<int> _lineStarts;

  int get lineCount => textLength == 0 ? 0 : _lineStarts.length;

  ReadingPositionMetrics metricsForOffset(int rawOffset) {
    if (textLength == 0) {
      return ReadingPositionMetrics.lines(
        current: 0,
        total: 0,
        progress: 0,
      );
    }
    final offset = rawOffset.clamp(0, textLength).toInt();
    var low = 0;
    var high = _lineStarts.length;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      if (_lineStarts[middle] <= offset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return ReadingPositionMetrics.lines(
      current: low.clamp(1, lineCount).toInt(),
      total: lineCount,
      progress: offset / textLength,
    );
  }
}
