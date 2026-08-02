import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/domain/models/reading_position_metrics.dart';

void main() {
  group('ReadingPositionMetrics', () {
    test('formats an approximate character position without page counts', () {
      final metrics = ReadingPositionMetrics.characters(
        progress: 0.25,
        total: 1200,
      );

      expect(metrics.current, 300);
      expect(metrics.label, '全文约第 300 / 1200 字 · 25%');
      expect(metrics.label, isNot(contains('页')));
    });

    test('falls back to progress when indexed text is unavailable', () {
      final metrics = ReadingPositionMetrics.characters(
        progress: 0.4,
        total: 0,
      );

      expect(metrics.unit, ReadingPositionUnit.progress);
      expect(metrics.label, '全书 40%');
    });
  });

  group('ReadingTextPositionIndex', () {
    test('maps stable raw offsets to whole-document lines', () {
      final index = ReadingTextPositionIndex.fromText('甲\n乙乙\n丙');

      expect(index.metricsForOffset(0).label, '全文第 1 / 3 行 · 0%');
      expect(index.metricsForOffset(3).current, 2);
      expect(index.metricsForOffset(6).current, 3);
    });

    test('handles empty text without inventing a line', () {
      final metrics = ReadingTextPositionIndex.fromText('').metricsForOffset(0);

      expect(metrics.current, 0);
      expect(metrics.total, 0);
    });
  });
}
