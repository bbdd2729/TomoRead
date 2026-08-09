import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tomoread/app/providers.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/settings_repository.dart';
import 'package:tomoread/domain/models/library_workspace_state.dart';

void main() {
  test('restores workspace state in a new provider container', () async {
    final database = AppDatabase.inMemory();
    final repository = SettingsRepository(database);
    final first = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(() async {
      first.dispose();
      await database.close();
    });

    await first.read(libraryWorkspaceStateProvider.future);
    await first
        .read(libraryWorkspaceStateProvider.notifier)
        .save(
          const LibraryWorkspaceState(
            formatFilter: LibraryFormatFilter.text,
            category: 'Markdown',
          ),
        );

    final second = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(second.dispose);

    expect(
      await second.read(libraryWorkspaceStateProvider.future),
      const LibraryWorkspaceState(
        formatFilter: LibraryFormatFilter.text,
        category: 'Markdown',
      ),
    );
  });
}
