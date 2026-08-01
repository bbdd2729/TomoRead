import 'package:sqflite_common/sqlite_api.dart';

import '../../domain/models/chat_models.dart';
import '../database/app_database.dart';

class SkillRepository {
  SkillRepository(this._database);

  final AppDatabase _database;

  Future<List<AiSkillDefinition>> listSkills() async {
    final database = await _database.database;
    await _ensureBuiltIns(database);
    final rows = await database.query(
      'ai_skills',
      orderBy: 'is_built_in DESC, created_at ASC, name ASC',
    );
    return rows.map(_fromRow).toList();
  }

  Future<List<AiSkillDefinition>> listEnabled() async {
    final skills = await listSkills();
    return skills.where((skill) => skill.enabled).toList();
  }

  Future<AiSkillDefinition> save({
    String? id,
    required String name,
    required String description,
    required String promptTemplate,
    String iconKey = 'auto_awesome',
  }) async {
    final normalizedName = name.trim();
    final normalizedPrompt = promptTemplate.trim();
    if (normalizedName.isEmpty || normalizedPrompt.isEmpty) {
      throw const FormatException('技能名称和提示词不能为空。');
    }
    final database = await _database.database;
    final now = DateTime.now();
    AiSkillDefinition? existing;
    if (id != null) {
      final rows = await database.query(
        'ai_skills',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isNotEmpty) existing = _fromRow(rows.single);
    }
    final skill = AiSkillDefinition(
      id: id ?? 'custom-skill-${now.microsecondsSinceEpoch}',
      name: normalizedName,
      description: description.trim(),
      iconKey: existing?.iconKey ?? iconKey,
      enabled: existing?.enabled ?? true,
      builtIn: existing?.builtIn ?? false,
      version: existing?.version ?? 1,
      promptTemplate: normalizedPrompt,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    await database.insert(
      'ai_skills',
      _toRow(skill),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return skill;
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final database = await _database.database;
    await database.update(
      'ai_skills',
      {
        'is_enabled': enabled ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteCustom(String id) async {
    final database = await _database.database;
    await database.delete(
      'ai_skills',
      where: 'id = ? AND is_built_in = 0',
      whereArgs: [id],
    );
  }

  Future<void> _ensureBuiltIns(DatabaseExecutor database) async {
    for (final skill in builtInAiSkills) {
      await database.insert(
        'ai_skills',
        _toRow(skill),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Map<String, Object?> _toRow(AiSkillDefinition skill) => {
    'id': skill.id,
    'name': skill.name,
    'description': skill.description,
    'icon_key': skill.iconKey,
    'is_enabled': skill.enabled ? 1 : 0,
    'is_built_in': skill.builtIn ? 1 : 0,
    'version': skill.version,
    'prompt_template': skill.promptTemplate,
    'created_at': skill.createdAt.millisecondsSinceEpoch,
    'updated_at': skill.updatedAt.millisecondsSinceEpoch,
  };

  AiSkillDefinition _fromRow(Map<String, Object?> row) => AiSkillDefinition(
    id: row['id']! as String,
    name: row['name']! as String,
    description: row['description']! as String,
    iconKey: row['icon_key']! as String,
    enabled: (row['is_enabled']! as int) == 1,
    builtIn: (row['is_built_in']! as int) == 1,
    version: row['version']! as int,
    promptTemplate: row['prompt_template']! as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at']! as int),
  );
}

final builtInAiSkills = <AiSkillDefinition>[
  AiSkillDefinition(
    id: 'chapter-summary',
    name: '章节总结',
    description: '提炼章节主旨、关键论点和仍待回答的问题。',
    iconKey: 'summarize',
    enabled: true,
    builtIn: true,
    version: 1,
    promptTemplate:
        '请基于可用的章节或选区原文，先提炼一句话主旨，再列出关键论点、证据和三个值得继续思考的问题。不得补写原文没有的信息。',
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
  ),
  AiSkillDefinition(
    id: 'concept-explainer',
    name: '概念解释',
    description: '结合上下文解释术语、概念和它们之间的关系。',
    iconKey: 'lightbulb',
    enabled: true,
    builtIn: true,
    version: 1,
    promptTemplate:
        '请结合当前书籍上下文解释目标概念：先给出简明定义，再说明它在原文中的作用、与相近概念的区别，并给出一个不脱离原意的例子。',
    createdAt: DateTime.fromMillisecondsSinceEpoch(1),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(1),
  ),
  AiSkillDefinition(
    id: 'structure-analysis',
    name: '结构梳理',
    description: '整理章节层级、论证路径和内容之间的联系。',
    iconKey: 'account_tree',
    enabled: true,
    builtIn: true,
    version: 1,
    promptTemplate:
        '请分析可用内容的结构：按层级列出主题与子主题，说明各部分的承接关系，并指出论证中的前提、结论和转折。信息不足时明确标注。',
    createdAt: DateTime.fromMillisecondsSinceEpoch(2),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(2),
  ),
];
