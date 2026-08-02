import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../domain/models/display_projection.dart';
import 'text_projection_controller.dart';

class TextProjectionDialog extends HookConsumerWidget {
  const TextProjectionDialog({super.key, required this.bookId});

  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configState = ref.watch(textProjectionConfigProvider(bookId));
    final settings = useState(const TextProjectionSettings());
    final saveForBook = useState(true);
    useEffect(() {
      final value = configState.value;
      if (value != null) settings.value = value.settings;
      return null;
    }, [configState.value]);

    Future<void> addRule() async {
      final draft = await showDialog<_RuleDraft>(
        context: context,
        builder: (context) => _RuleEditorDialog(bookId: bookId),
      );
      if (draft == null || !context.mounted) return;
      await ref.read(textProjectionControllerProvider).saveRule(
        bookId: draft.forBook ? bookId : null,
        name: draft.name,
        findText: draft.findText,
        replaceText: draft.replaceText,
        priority: draft.priority,
      );
    }

    Future<void> save() async {
      await ref.read(textProjectionControllerProvider).saveSettings(
        settings.value,
        bookId: saveForBook.value ? bookId : null,
      );
      if (context.mounted) Navigator.pop(context);
    }

    return AlertDialog(
      title: const Text('文本显示投影'),
      scrollable: true,
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '只改变 TXT/Markdown 的显示内容，不会改写原文件、章节偏移或既有定位。'
              '无法可靠映射的区段会禁用精确标注。',
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<ChineseConversionMode>(
              key: ValueKey(settings.value.chineseConversion),
              initialValue: settings.value.chineseConversion,
              decoration: const InputDecoration(
                labelText: '简繁转换',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final mode in ChineseConversionMode.values)
                  DropdownMenuItem(value: mode, child: Text(mode.label)),
              ],
              onChanged: (value) {
                if (value != null) {
                  settings.value = settings.value.copyWith(
                    chineseConversion: value,
                  );
                }
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<CharacterWidthMode>(
              key: ValueKey(settings.value.widthMode),
              initialValue: settings.value.widthMode,
              decoration: const InputDecoration(
                labelText: '全角/半角',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final mode in CharacterWidthMode.values)
                  DropdownMenuItem(value: mode, child: Text(mode.label)),
              ],
              onChanged: (value) {
                if (value != null) {
                  settings.value = settings.value.copyWith(widthMode: value);
                }
              },
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: settings.value.convertLetters,
              title: const Text('转换英文字母宽度'),
              onChanged: (value) => settings.value = settings.value.copyWith(
                convertLetters: value ?? true,
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: settings.value.convertNumbers,
              title: const Text('转换数字宽度'),
              onChanged: (value) => settings.value = settings.value.copyWith(
                convertNumbers: value ?? true,
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: saveForBook.value,
              title: Text(saveForBook.value ? '保存为本书设置' : '保存为全局默认'),
              subtitle: const Text('全局默认只影响未设置独立投影的文本书籍。'),
              onChanged: (value) => saveForBook.value = value,
            ),
            const Divider(height: 32),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '字面量替换规则',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: configState.isLoading ? null : addRule,
                  icon: const Icon(Icons.add),
                  label: const Text('添加'),
                ),
              ],
            ),
            configState.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Text('规则加载失败：$error'),
              data: (config) => config.rules.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('暂无规则。仅支持字面量替换，不执行用户正则。'),
                    )
                  : Column(
                      children: [
                        for (final rule in config.rules)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Switch(
                              value: rule.enabled,
                              onChanged: (enabled) => ref
                                  .read(textProjectionControllerProvider)
                                  .saveRule(
                                    id: rule.id,
                                    bookId: rule.bookId,
                                    name: rule.name,
                                    findText: rule.findText,
                                    replaceText: rule.replaceText,
                                    enabled: enabled,
                                    priority: rule.priority,
                                  ),
                            ),
                            title: Text(rule.name),
                            subtitle: Text(
                              '${rule.bookId == null ? '全局' : '本书'} · '
                              '优先级 ${rule.priority} · '
                              '“${rule.findText}” → “${rule.replaceText}”',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              tooltip: '删除规则',
                              onPressed: () => ref
                                  .read(textProjectionControllerProvider)
                                  .deleteRule(rule.id),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: configState.isLoading ? null : save, child: const Text('保存')),
      ],
    );
  }
}

class _RuleDraft {
  const _RuleDraft({
    required this.name,
    required this.findText,
    required this.replaceText,
    required this.priority,
    required this.forBook,
  });

  final String name;
  final String findText;
  final String replaceText;
  final int priority;
  final bool forBook;
}

class _RuleEditorDialog extends HookWidget {
  const _RuleEditorDialog({required this.bookId});

  final String bookId;

  @override
  Widget build(BuildContext context) {
    final name = useTextEditingController();
    final find = useTextEditingController();
    final replace = useTextEditingController();
    final priority = useTextEditingController(text: '0');
    final forBook = useState(true);
    final error = useState<String?>(null);
    return AlertDialog(
      title: const Text('添加字面量替换'),
      scrollable: true,
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              maxLength: 120,
              decoration: const InputDecoration(labelText: '规则名称'),
            ),
            TextField(
              controller: find,
              maxLength: 200,
              decoration: const InputDecoration(labelText: '查找文本'),
            ),
            TextField(
              controller: replace,
              maxLength: 200,
              decoration: const InputDecoration(labelText: '替换为（可留空）'),
            ),
            TextField(
              controller: priority,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '优先级（-1000 至 1000）'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: forBook.value,
              title: Text(forBook.value ? '仅用于本书' : '用于所有文本书籍'),
              onChanged: (value) => forBook.value = value,
            ),
            if (error.value != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  error.value!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final parsedPriority = int.tryParse(priority.text.trim());
            if (name.text.trim().isEmpty ||
                find.text.isEmpty ||
                parsedPriority == null ||
                parsedPriority < -1000 ||
                parsedPriority > 1000) {
              error.value = '请填写名称、查找文本和有效优先级。';
              return;
            }
            Navigator.pop(
              context,
              _RuleDraft(
                name: name.text.trim(),
                findText: find.text,
                replaceText: replace.text,
                priority: parsedPriority,
                forBook: forBook.value,
              ),
            );
          },
          child: const Text('添加'),
        ),
      ],
    );
  }
}
