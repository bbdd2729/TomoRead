import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tomoread/app/providers.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/skill_repository.dart';
import 'package:tomoread/features/skills/skills_controller.dart';

void main() {
  late AppDatabase database;
  late SkillRepository repository;
  late ProviderContainer container;

  setUp(() async {
    database = AppDatabase.inMemory();
    repository = SkillRepository(database);
    container = ProviderContainer(
      overrides: [skillRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });
  });

  test('build seeds and loads built-in skills', () async {
    final skills = await container.read(skillsControllerProvider.future);
    expect(skills, hasLength(3));
    expect(skills.every((skill) => skill.builtIn), isTrue);
  });

  test('setEnabled updates state and persists the toggle', () async {
    final notifier = container.read(skillsControllerProvider.notifier);
    final skills = await container.read(skillsControllerProvider.future);
    final target = skills.firstWhere((s) => s.id == 'chapter-summary');

    await notifier.setEnabled(target, false);

    final state = container.read(skillsControllerProvider).requireValue;
    expect(state.firstWhere((s) => s.id == 'chapter-summary').enabled, isFalse);
    final persisted = await repository.listSkills();
    expect(persisted.firstWhere((s) => s.id == 'chapter-summary').enabled, isFalse);
  });

  test('setEnabled rolls the state back when the repository fails', () async {
    final failing = FailingSkillRepository(database);
    final failingContainer = ProviderContainer(
      overrides: [skillRepositoryProvider.overrideWithValue(failing)],
    );
    addTearDown(failingContainer.dispose);
    final notifier = failingContainer.read(skillsControllerProvider.notifier);
    final before = await failingContainer.read(skillsControllerProvider.future);
    final target = before.firstWhere((s) => s.id == 'chapter-summary');

    await expectLater(
      notifier.setEnabled(target, false),
      throwsA(isA<StateError>()),
    );

    final after = failingContainer.read(skillsControllerProvider).requireValue;
    expect(
      after.firstWhere((s) => s.id == 'chapter-summary').enabled,
      isTrue,
    );
  });

  test('save appends a custom skill and reloads the list', () async {
    final notifier = container.read(skillsControllerProvider.notifier);
    await container.read(skillsControllerProvider.future);

    await notifier.save(
      name: '对照阅读',
      description: '比较两个观点',
      promptTemplate: '比较输入中的两个观点。',
    );

    final skills = container.read(skillsControllerProvider).requireValue;
    expect(skills, hasLength(4));
    expect(skills.last.name, '对照阅读');
    expect(skills.last.builtIn, isFalse);
  });

  test('delete ignores built-in skills but removes custom ones', () async {
    final notifier = container.read(skillsControllerProvider.notifier);
    await container.read(skillsControllerProvider.future);
    final builtIn = (await repository.listSkills()).first;

    await notifier.delete(builtIn);
    expect(await repository.listSkills(), hasLength(3));

    final custom = await repository.save(
      name: '自定义技能',
      description: '临时',
      promptTemplate: '临时提示词。',
    );
    await notifier.delete(custom);
    expect(await repository.listSkills(), hasLength(3));
  });
}

class FailingSkillRepository extends SkillRepository {
  FailingSkillRepository(super.database);

  @override
  Future<void> setEnabled(String id, bool enabled) async {
    throw StateError('persist failed');
  }
}
