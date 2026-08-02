import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/services/reader_shortcut_service.dart';
import 'package:tomoread/domain/models/reader_commands.dart';

void main() {
  const service = ReaderShortcutService();

  test('default desktop bindings are complete and conflict free', () {
    final settings = ReaderCommandSettings.defaults();

    expect(service.validate(settings).isValid, isTrue);
    for (final platform in ReaderShortcutPlatform.values) {
      expect(
        settings.forPlatform(platform).map((binding) => binding.command),
        containsAll(ReaderCommand.values),
      );
    }
  });

  test('rejects two active commands using the same chord', () {
    final defaults = ReaderCommandSettings.defaults();
    final previous = defaults
        .forPlatform(ReaderShortcutPlatform.windows)
        .firstWhere(
          (binding) => binding.command == ReaderCommand.previousPage,
        );
    final next = defaults
        .forPlatform(ReaderShortcutPlatform.windows)
        .firstWhere((binding) => binding.command == ReaderCommand.nextPage);
    final changed = defaults.replaceBinding(
      next.copyWith(chord: previous.chord),
    );

    final validation = service.validate(changed);

    expect(validation.isValid, isFalse);
    expect(validation.issues.single.conflictingCommand, previous.command);
  });

  test('rejects unmodified letter keys and operating system shortcuts', () {
    final defaults = ReaderCommandSettings.defaults();
    final search = defaults
        .forPlatform(ReaderShortcutPlatform.windows)
        .firstWhere((binding) => binding.command == ReaderCommand.search);
    final plainLetter = defaults.replaceBinding(
      search.copyWith(chord: const ReaderShortcutChord(key: 'keyF')),
    );
    final reserved = defaults.replaceBinding(
      search.copyWith(
        chord: const ReaderShortcutChord(key: 'keyL', meta: true),
      ),
    );

    expect(service.validate(plainLetter).isValid, isFalse);
    expect(service.validate(reserved).isValid, isFalse);
  });

  test('stored settings merge missing commands with current defaults', () {
    final decoded = ReaderCommandSettings.fromJson({
      'bindings': [
        const ReaderShortcutBinding(
          command: ReaderCommand.search,
          platform: ReaderShortcutPlatform.windows,
          chord: ReaderShortcutChord(key: 'keyG', control: true),
        ).toJson(),
      ],
      'autoScroll': {'unit': 'screensPerMinute', 'speed': 0.8},
    });

    expect(
      decoded
          .forPlatform(ReaderShortcutPlatform.windows)
          .firstWhere((binding) => binding.command == ReaderCommand.search)
          .chord
          ?.key,
      'keyG',
    );
    expect(decoded.bindings, hasLength(ReaderCommand.values.length * 2));
    expect(decoded.autoScroll.unit, AutoScrollUnit.screensPerMinute);
    expect(decoded.autoScroll.speed, 0.8);
  });
}
