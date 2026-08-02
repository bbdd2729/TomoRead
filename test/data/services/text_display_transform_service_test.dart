import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/services/text_display_transform_service.dart';
import 'package:tomoread/domain/models/display_projection.dart';

void main() {
  const service = TextDisplayTransformService();
  final now = DateTime(2026);

  TextDisplayRule rule({
    required String id,
    required String find,
    required String replace,
    String? bookId,
    int priority = 0,
  }) => TextDisplayRule(
    id: id,
    bookId: bookId,
    name: id,
    findText: find,
    replaceText: replace,
    enabled: true,
    priority: priority,
    createdAt: now,
    updatedAt: now,
  );

  test('applies book scope, priority, and longest literal match', () async {
    final projection = await service.project(
      bookId: 'book-a',
      rawText: 'alpha beta',
      settings: const TextProjectionSettings(),
      rules: [
        rule(id: 'short', find: 'alpha', replace: 'global'),
        rule(
          id: 'long',
          bookId: 'book-a',
          find: 'alpha beta',
          replace: 'local',
          priority: 10,
        ),
      ],
    );

    expect(projection.displayText, 'local');
    final mapped = projection.displayToRaw(0, 5);
    expect(mapped.start, 0);
    expect(mapped.end, 10);
    expect(mapped.isExact, isFalse);
  });

  test('keeps exact mapping for width and equal-length replacements', () async {
    final projection = await service.project(
      bookId: 'book-a',
      rawText: 'ABC123',
      settings: const TextProjectionSettings(
        widthMode: CharacterWidthMode.toFullWidth,
      ),
      rules: [rule(id: 'digits', find: '１２３', replace: '４５６')],
    );

    expect(projection.displayText, 'ＡＢＣ４５６');
    expect(projection.displayToRaw(0, 6).isExact, isTrue);
    expect(projection.displayToRaw(3, 6).start, 3);
  });
}
