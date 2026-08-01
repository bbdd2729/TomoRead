import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../domain/models/chat_models.dart';
import '../../shared/widgets/page_header.dart';
import '../chat/chat_controller.dart';
import 'skills_controller.dart';

class SkillsPage extends ConsumerWidget {
  const SkillsPage({super.key, this.onOpenChat});

  final VoidCallback? onOpenChat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skills = ref.watch(skillsControllerProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth < 600 ? 20.0 : 32.0;
        return ListView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            28,
            horizontalPadding,
            48,
          ),
          children: [
            PageHeader(
              title: '技能',
              subtitle: '管理 Agent 在阅读对话中可以调用的分析方法。',
              actionLabel: '新建技能',
              actionIcon: Icons.add,
              onAction: () => _editSkill(context, ref),
            ),
            const SizedBox(height: 24),
            skills.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: FilledButton.icon(
                  onPressed: () => ref.invalidate(skillsControllerProvider),
                  icon: const Icon(Icons.refresh),
                  label: Text('重新加载：$error'),
                ),
              ),
              data: (items) => GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 360,
                  mainAxisExtent: 214,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                ),
                itemBuilder: (context, index) => _SkillCard(
                  skill: items[index],
                  onEnabledChanged: (enabled) => ref
                      .read(skillsControllerProvider.notifier)
                      .setEnabled(items[index], enabled),
                  onRun: () => _runSkill(ref, items[index]),
                  onEdit: () => _editSkill(context, ref, items[index]),
                  onDelete: items[index].builtIn
                      ? null
                      : () => _deleteSkill(context, ref, items[index]),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _runSkill(WidgetRef ref, AiSkillDefinition skill) {
    if (!skill.enabled) return;
    ref
        .read(pendingChatDraftProvider.notifier)
        .set(
          PendingChatDraft(
            skillId: skill.id,
            prompt: '请使用“${skill.name}”技能处理下面的问题：',
          ),
        );
    onOpenChat?.call();
  }
}

class _SkillCard extends StatelessWidget {
  const _SkillCard({
    required this.skill,
    required this.onEnabledChanged,
    required this.onRun,
    required this.onEdit,
    this.onDelete,
  });

  final AiSkillDefinition skill;
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback onRun;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 38,
                  height: 38,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.secondaryContainer,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(
                      _skillIcon(skill.iconKey),
                      color: colors.onSecondaryContainer,
                    ),
                  ),
                ),
                const Spacer(),
                Switch(value: skill.enabled, onChanged: onEnabledChanged),
                PopupMenuButton<String>(
                  tooltip: '技能操作',
                  onSelected: (value) => switch (value) {
                    'edit' => onEdit(),
                    'delete' => onDelete?.call(),
                    _ => null,
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'edit', child: Text('编辑')),
                    if (onDelete != null)
                      const PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(skill.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 5),
            Expanded(
              child: Text(
                skill.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: skill.enabled ? onRun : null,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('在对话中运行'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _editSkill(
  BuildContext context,
  WidgetRef ref, [
  AiSkillDefinition? skill,
]) async {
  final name = TextEditingController(text: skill?.name);
  final description = TextEditingController(text: skill?.description);
  final prompt = TextEditingController(text: skill?.promptTemplate);
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(skill == null ? '新建技能' : '编辑技能'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: '名称'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: description,
                maxLines: 2,
                decoration: const InputDecoration(labelText: '说明'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: prompt,
                minLines: 6,
                maxLines: 12,
                decoration: const InputDecoration(labelText: '技能提示词'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('保存'),
        ),
      ],
    ),
  );
  if (saved == true) {
    try {
      await ref
          .read(skillsControllerProvider.notifier)
          .save(
            id: skill?.id,
            name: name.text,
            description: description.text,
            promptTemplate: prompt.text,
          );
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('无法保存技能：$error')));
      }
    }
  }
  name.dispose();
  description.dispose();
  prompt.dispose();
}

Future<void> _deleteSkill(
  BuildContext context,
  WidgetRef ref,
  AiSkillDefinition skill,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('删除自定义技能？'),
      content: Text('“${skill.name}”将不再提供给 Agent。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await ref.read(skillsControllerProvider.notifier).delete(skill);
  }
}

IconData _skillIcon(String key) => switch (key) {
  'summarize' => Icons.summarize_outlined,
  'lightbulb' => Icons.lightbulb_outline,
  'account_tree' => Icons.account_tree_outlined,
  _ => Icons.auto_awesome_outlined,
};
