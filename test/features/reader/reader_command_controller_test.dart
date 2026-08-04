import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tomoread/app/providers.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/reader_command_repository.dart';
import 'package:tomoread/data/services/reader_shortcut_service.dart';
import 'package:tomoread/domain/models/reader_commands.dart';
import 'package:tomoread/features/reader/reader_command_controller.dart';

void main() {
  late AppDatabase database;
  late ReaderCommandRepository repository;
  late ProviderContainer container;

  setUp(() async {
    database = AppDatabase.inMemory();
    repository = ReaderCommandRepository(database);
    container = ProviderContainer(
      overrides: [
        readerCommandRepositoryProvider.overrideWithValue(repository),
        readerShortcutServiceProvider.overrideWithValue(
          const ReaderShortcutService(),
        ),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });
  });

  test('build returns the default command settings when none stored', () async {
    final settings = await container.read(readerCommandSettingsProvider.future);
    expect(
      settings.bindings.length,
      ReaderCommand.values.length * ReaderShortcutPlatform.values.length,
    );
  });

  test('saveSettings persists a valid custom binding', () async {
    final notifier = container.read(readerCommandSettingsProvider.notifier);
    final original = await container.read(readerCommandSettingsProvider.future);
    final modified = original.replaceBinding(
      ReaderShortcutBinding(
        command: ReaderCommand.nextPage,
        platform: ReaderShortcutPlatform.windows,
        chord: const ReaderShortcutChord(key: 'keyN', control: true),
      ),
    );

    await notifier.saveSettings(modified);

    final state = container.read(readerCommandSettingsProvider).requireValue;
    final saved = await repository.load();
    expect(
      state
          .forPlatform(ReaderShortcutPlatform.windows)
          .firstWhere((b) => b.command == ReaderCommand.nextPage)
          .chord
          ?.signature,
      'control+keyn',
    );
    expect(saved.forPlatform(ReaderShortcutPlatform.windows).length, isPositive);
  });

  test('saveSettings rejects duplicate chord conflicts', () async {
    final notifier = container.read(readerCommandSettingsProvider.notifier);
    await container.read(readerCommandSettingsProvider.future);
    final conflicting = ReaderCommandSettings(
      bindings: [
        for (final platform in ReaderShortcutPlatform.values) ...[
          ReaderShortcutBinding(
            command: ReaderCommand.previousPage,
            platform: platform,
            chord: const ReaderShortcutChord(key: 'pageUp'),
          ),
          ReaderShortcutBinding(
            command: ReaderCommand.nextPage,
            platform: platform,
            chord: const ReaderShortcutChord(key: 'pageUp'),
          ),
        ],
      ],
      autoScroll: const AutoScrollPreference(),
    );

    await expectLater(
      notifier.saveSettings(conflicting),
      throwsA(isA<ReaderShortcutException>()),
    );

    expect(
      container.read(readerCommandSettingsProvider).requireValue.bindings,
      isNot(equals(conflicting.bindings)),
    );
  });

  test('restoreDefaults resets the persisted settings', () async {
    final notifier = container.read(readerCommandSettingsProvider.notifier);
    final original = await container.read(readerCommandSettingsProvider.future);
    final modified = original.replaceBinding(
      ReaderShortcutBinding(
        command: ReaderCommand.search,
        platform: ReaderShortcutPlatform.linux,
        chord: const ReaderShortcutChord(key: 'keyF', control: true),
      ),
    );
    await notifier.saveSettings(modified);

    await notifier.restoreDefaults();

    final restored = await repository.load();
    expect(restored.bindings.length, original.bindings.length);
  });
}
