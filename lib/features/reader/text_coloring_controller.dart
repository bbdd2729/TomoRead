import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repositories/text_coloring_repository.dart';
import '../../domain/models/text_coloring.dart';

final textColoringRevisionProvider = NotifierProvider<_RevisionNotifier, int>(
  _RevisionNotifier.new,
);

class _RevisionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state += 1;
}

final textColoringSettingsProvider =
    AsyncNotifierProvider<TextColoringSettingsNotifier, TextColoringSettings>(
      TextColoringSettingsNotifier.new,
    );

class TextColoringSettingsNotifier
    extends AsyncNotifier<TextColoringSettings> {
  @override
  Future<TextColoringSettings> build() =>
      ref.watch(textColoringRepositoryProvider).loadSettings();

  Future<void> saveSettings(TextColoringSettings settings) async {
    final previous = state;
    state = AsyncData(settings);
    try {
      await ref.read(textColoringRepositoryProvider).saveSettings(settings);
      ref.read(textColoringRevisionProvider.notifier).bump();
    } on Object {
      state = previous;
      rethrow;
    }
  }

  Future<void> restoreDefaults() => saveSettings(TextColoringSettings.defaults());
}

final bookTextColoringOverrideProvider = FutureProvider.autoDispose
    .family<bool?, String>(
      (ref, bookId) {
        ref.watch(textColoringRevisionProvider);
        return ref.watch(textColoringRepositoryProvider).loadBookOverride(
          bookId,
        );
      },
    );

typedef TextColorTermsRequest = ({String? bookId, bool includeGlobal});

final textColorTermsProvider = FutureProvider.autoDispose
    .family<List<TextColorTerm>, TextColorTermsRequest>((ref, request) {
      ref.watch(textColoringRevisionProvider);
      return ref
          .watch(textColoringRepositoryProvider)
          .listTerms(
            bookId: request.bookId,
            includeGlobal: request.includeGlobal,
          );
    });

final resolvedTextColoringProvider = FutureProvider.autoDispose
    .family<ResolvedTextColoring, String>((ref, bookId) async {
      ref.watch(textColoringRevisionProvider);
      final repository = ref.watch(textColoringRepositoryProvider);
      final settings = await ref.watch(textColoringSettingsProvider.future);
      final override = await repository.loadBookOverride(bookId);
      final terms = await repository.listTerms(
        bookId: bookId,
        includeGlobal: true,
      );
      return ResolvedTextColoring(
        settings: settings,
        enabled: override ?? settings.enabled,
        terms: terms,
      );
    });

final textColoringControllerProvider = Provider<TextColoringController>((ref) {
  return TextColoringController(
    repository: ref.watch(textColoringRepositoryProvider),
    onChanged: () => ref.read(textColoringRevisionProvider.notifier).bump(),
  );
});

class TextColoringController {
  const TextColoringController({
    required this.repository,
    required this.onChanged,
  });

  final TextColoringRepository repository;
  final void Function() onChanged;

  Future<void> saveBookOverride(String bookId, bool? enabled) async {
    await repository.saveBookOverride(bookId, enabled);
    onChanged();
  }

  Future<TextColorTerm> assignTerm({
    required String term,
    required TextColorTermTone tone,
    String? bookId,
  }) async {
    final result = await repository.assignTerm(
      term: term,
      tone: tone,
      bookId: bookId,
    );
    onChanged();
    return result;
  }

  Future<void> removeTerm(String id) async {
    await repository.removeTerm(id);
    onChanged();
  }
}
