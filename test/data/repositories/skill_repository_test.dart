import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/skill_repository.dart';

void main() {
  late AppDatabase database;
  late SkillRepository repository;

  setUp(() {
    database = AppDatabase.inMemory();
    repository = SkillRepository(database);
  });

  tearDown(() => database.close());

  test('seeds, toggles, and persists built-in skills', () async {
    final skills = await repository.listSkills();
    expect(skills, hasLength(3));
    expect(skills.every((skill) => skill.builtIn), isTrue);

    await repository.setEnabled(skills.first.id, false);
    final reloaded = await repository.listSkills();
    expect(reloaded.first.enabled, isFalse);
  });

  test('creates and deletes a custom skill', () async {
    final skill = await repository.save(
      name: '对照阅读',
      description: '比较两个观点',
      promptTemplate: '比较输入中的两个观点。',
    );
    expect(skill.builtIn, isFalse);
    expect(await repository.listSkills(), hasLength(4));

    await repository.deleteCustom(skill.id);
    expect(await repository.listSkills(), hasLength(3));
  });
}
