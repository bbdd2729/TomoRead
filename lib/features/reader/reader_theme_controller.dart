import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models/reader_theme.dart';

final customReaderThemesProvider =
    AsyncNotifierProvider<CustomReaderThemesNotifier, List<CustomReaderTheme>>(
      CustomReaderThemesNotifier.new,
    );

class CustomReaderThemesNotifier
    extends AsyncNotifier<List<CustomReaderTheme>> {
  @override
  Future<List<CustomReaderTheme>> build() =>
      ref.watch(settingsRepositoryProvider).loadCustomReaderThemes();

  Future<void> save(CustomReaderTheme theme) async {
    final current = state.value ?? const <CustomReaderTheme>[];
    final next = [
      for (final existing in current)
        if (existing.id != theme.id) existing,
      theme,
    ];
    state = AsyncData(next);
    await ref.read(settingsRepositoryProvider).saveCustomReaderThemes(next);
  }

  Future<void> remove(String id) async {
    final current = state.value ?? const <CustomReaderTheme>[];
    final next = current.where((theme) => theme.id != id).toList();
    state = AsyncData(next);
    await ref.read(settingsRepositoryProvider).saveCustomReaderThemes(next);
  }
}
