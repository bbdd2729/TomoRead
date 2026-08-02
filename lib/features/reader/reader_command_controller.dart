import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../data/services/reader_shortcut_service.dart';
import '../../domain/models/reader_commands.dart';

final readerCommandSettingsProvider =
    AsyncNotifierProvider<ReaderCommandSettingsNotifier, ReaderCommandSettings>(
      ReaderCommandSettingsNotifier.new,
    );

class ReaderCommandSettingsNotifier
    extends AsyncNotifier<ReaderCommandSettings> {
  @override
  Future<ReaderCommandSettings> build() =>
      ref.watch(readerCommandRepositoryProvider).load();

  Future<void> saveSettings(ReaderCommandSettings settings) async {
    final validation = ref.read(readerShortcutServiceProvider).validate(settings);
    if (!validation.isValid) {
      throw ReaderShortcutException(validation.issues.first.message);
    }
    final previous = state;
    state = AsyncData(settings);
    try {
      await ref.read(readerCommandRepositoryProvider).save(settings);
    } on Object {
      state = previous;
      rethrow;
    }
  }

  Future<void> restoreDefaults() =>
      saveSettings(ReaderCommandSettings.defaults());
}
