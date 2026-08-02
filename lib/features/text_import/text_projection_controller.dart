import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repositories/text_projection_repository.dart';
import '../../domain/models/display_projection.dart';

class TextProjectionConfig {
  const TextProjectionConfig({required this.settings, required this.rules});

  final TextProjectionSettings settings;
  final List<TextDisplayRule> rules;
}

final textProjectionConfigProvider = FutureProvider.autoDispose
    .family<TextProjectionConfig, String>((ref, bookId) async {
      ref.watch(textProjectionRevisionProvider);
      final repository = ref.watch(textProjectionRepositoryProvider);
      final results = await Future.wait<Object>([
        repository.loadSettings(bookId),
        repository.listRules(bookId),
      ]);
      return TextProjectionConfig(
        settings: results[0] as TextProjectionSettings,
        rules: results[1] as List<TextDisplayRule>,
      );
    });

final textProjectionControllerProvider = Provider<TextProjectionController>(
  (ref) => TextProjectionController(
    repository: ref.watch(textProjectionRepositoryProvider),
    onChanged: () => ref.read(textProjectionRevisionProvider.notifier).bump(),
  ),
);

class TextProjectionController {
  const TextProjectionController({
    required this.repository,
    required this.onChanged,
  });

  final TextProjectionRepository repository;
  final void Function() onChanged;

  Future<void> saveSettings(
    TextProjectionSettings settings, {
    String? bookId,
  }) async {
    await repository.saveSettings(settings, bookId: bookId);
    onChanged();
  }

  Future<void> clearBookSettings(String bookId) async {
    await repository.clearBookSettings(bookId);
    onChanged();
  }

  Future<void> saveRule({
    String? id,
    String? bookId,
    required String name,
    required String findText,
    required String replaceText,
    bool enabled = true,
    int priority = 0,
  }) async {
    await repository.saveRule(
      id: id,
      bookId: bookId,
      name: name,
      findText: findText,
      replaceText: replaceText,
      enabled: enabled,
      priority: priority,
    );
    onChanged();
  }

  Future<void> deleteRule(String id) async {
    await repository.deleteRule(id);
    onChanged();
  }
}
