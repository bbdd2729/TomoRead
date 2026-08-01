import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models/chat_models.dart';

final skillsControllerProvider =
    AsyncNotifierProvider<SkillsController, List<AiSkillDefinition>>(
      SkillsController.new,
    );

class SkillsController extends AsyncNotifier<List<AiSkillDefinition>> {
  @override
  Future<List<AiSkillDefinition>> build() =>
      ref.watch(skillRepositoryProvider).listSkills();

  Future<void> setEnabled(AiSkillDefinition skill, bool enabled) async {
    final previous = state.value ?? const <AiSkillDefinition>[];
    state = AsyncData(
      previous
          .map(
            (item) =>
                item.id == skill.id ? item.copyWith(enabled: enabled) : item,
          )
          .toList(),
    );
    try {
      await ref.read(skillRepositoryProvider).setEnabled(skill.id, enabled);
    } on Object {
      state = AsyncData(previous);
      rethrow;
    }
  }

  Future<void> save({
    String? id,
    required String name,
    required String description,
    required String promptTemplate,
  }) async {
    await ref
        .read(skillRepositoryProvider)
        .save(
          id: id,
          name: name,
          description: description,
          promptTemplate: promptTemplate,
        );
    state = AsyncData(await ref.read(skillRepositoryProvider).listSkills());
  }

  Future<void> delete(AiSkillDefinition skill) async {
    if (skill.builtIn) return;
    await ref.read(skillRepositoryProvider).deleteCustom(skill.id);
    state = AsyncData(await ref.read(skillRepositoryProvider).listSkills());
  }
}
