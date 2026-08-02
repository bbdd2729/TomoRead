import 'dart:isolate';
import 'dart:math';

import '../../domain/models/visual_artifact.dart';

class WordCloudLayoutEntry {
  const WordCloudLayoutEntry({
    required this.term,
    required this.frequency,
    required this.x,
    required this.y,
    required this.fontSize,
    required this.colorIndex,
  });

  final String term;
  final int frequency;
  final double x;
  final double y;
  final double fontSize;
  final int colorIndex;
}

class WordCloudLayoutService {
  const WordCloudLayoutService();

  Future<List<WordCloudLayoutEntry>> layout(
    WordCloudPayload payload, {
    required double width,
    required double height,
  }) async {
    final request = <String, Object>{
      'terms': [
        for (final term in payload.terms)
          <String, Object>{
            'term': term.term,
            'frequency': term.frequency,
          },
      ],
      'seed': payload.layoutSeed,
      'width': width,
      'height': height,
    };
    final rows = await Isolate.run(() => computeWordCloudLayoutRows(request));
    return rows
        .map(
          (row) => WordCloudLayoutEntry(
            term: row['term']! as String,
            frequency: row['frequency']! as int,
            x: (row['x']! as num).toDouble(),
            y: (row['y']! as num).toDouble(),
            fontSize: (row['fontSize']! as num).toDouble(),
            colorIndex: row['colorIndex']! as int,
          ),
        )
        .toList();
  }
}

List<Map<String, Object>> computeWordCloudLayoutRows(
  Map<String, Object> request,
) {
  final terms = (request['terms']! as List)
      .whereType<Map>()
      .map(
        (row) => (
          term: row['term']! as String,
          frequency: row['frequency']! as int,
        ),
      )
      .toList();
  if (terms.isEmpty) return const [];
  final width = (request['width']! as num).toDouble();
  final height = (request['height']! as num).toDouble();
  final random = Random(request['seed']! as int);
  final maximum = terms.first.frequency.clamp(1, 1 << 30);
  final occupied = <Rectangle<double>>[];
  final result = <Map<String, Object>>[];
  for (var index = 0; index < terms.length; index++) {
    final item = terms[index];
    final fontSize = 16 + 50 * sqrt(item.frequency / maximum);
    final estimatedWidth = max(
      fontSize,
      item.term.runes.fold<double>(
        0,
        (value, rune) => value + fontSize * (rune > 0x7f ? 1 : .62),
      ),
    );
    final estimatedHeight = fontSize * 1.18;
    final phase = random.nextDouble() * pi * 2;
    Rectangle<double>? target;
    for (var attempt = 0; attempt < 850; attempt++) {
      final angle = phase + attempt * .42;
      final radius = 3.7 * sqrt(attempt);
      final centerX = width / 2 + cos(angle) * radius * 1.65;
      final centerY = height / 2 + sin(angle) * radius;
      final candidate = Rectangle<double>(
        centerX - estimatedWidth / 2,
        centerY - estimatedHeight / 2,
        estimatedWidth,
        estimatedHeight,
      );
      if (candidate.left < 0 ||
          candidate.top < 0 ||
          candidate.right > width ||
          candidate.bottom > height) {
        continue;
      }
      final padded = Rectangle<double>(
        candidate.left - 4,
        candidate.top - 4,
        candidate.width + 8,
        candidate.height + 8,
      );
      if (occupied.any(
        (rectangle) =>
            rectangle.left < padded.right &&
            rectangle.right > padded.left &&
            rectangle.top < padded.bottom &&
            rectangle.bottom > padded.top,
      )) {
        continue;
      }
      target = candidate;
      break;
    }
    if (target == null) continue;
    occupied.add(target);
    result.add(<String, Object>{
      'term': item.term,
      'frequency': item.frequency,
      'x': target.left,
      'y': target.top,
      'fontSize': fontSize,
      'colorIndex': index,
    });
  }
  return result;
}
