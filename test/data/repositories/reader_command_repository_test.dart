import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/reader_command_repository.dart';
import 'package:tomoread/domain/models/reader_commands.dart';

void main() {
  late AppDatabase database;
  late ReaderCommandRepository repository;

  setUp(() {
    database = AppDatabase.inMemory();
    repository = ReaderCommandRepository(database);
  });

  tearDown(() => database.close());

  test('persists shortcut bindings and auto-scroll speed', () async {
    final defaults = ReaderCommandSettings.defaults();
    final search = defaults
        .forPlatform(ReaderShortcutPlatform.windows)
        .firstWhere((binding) => binding.command == ReaderCommand.search);
    final changed = defaults
        .replaceBinding(
          search.copyWith(
            chord: const ReaderShortcutChord(
              key: 'keyG',
              control: true,
            ),
          ),
        )
        .copyWith(
          autoScroll: const AutoScrollPreference(
            unit: AutoScrollUnit.screensPerMinute,
            speed: 0.7,
          ),
        );

    await repository.save(changed);
    final loaded = await repository.load();

    expect(
      loaded
          .forPlatform(ReaderShortcutPlatform.windows)
          .firstWhere((binding) => binding.command == ReaderCommand.search)
          .chord
          ?.key,
      'keyG',
    );
    expect(loaded.autoScroll.unit, AutoScrollUnit.screensPerMinute);
    expect(loaded.autoScroll.speed, 0.7);
  });
}
