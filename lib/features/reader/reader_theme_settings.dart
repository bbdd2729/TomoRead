import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../domain/models/reader_theme.dart';
import 'reader_theme_controller.dart';
import 'reader_theme_data.dart';

class ReaderThemePicker extends StatelessWidget {
  const ReaderThemePicker({
    super.key,
    required this.selection,
    required this.customThemes,
    required this.onChanged,
    required this.onManageCustomThemes,
  });

  final ReaderThemeSelection selection;
  final List<CustomReaderTheme> customThemes;
  final ValueChanged<ReaderThemeSelection> onChanged;
  final VoidCallback onManageCustomThemes;

  @override
  Widget build(BuildContext context) {
    final appTheme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final preset in ReaderThemePreset.values)
          if (preset != ReaderThemePreset.custom)
            _ReaderThemeChoice(
              label: preset.label,
              colors: ReaderThemeData.resolveColors(
                appTheme,
                ReaderThemeSelection(preset: preset),
                customThemes,
              ),
              selected: selection.preset == preset,
              onPressed: () => onChanged(ReaderThemeSelection(preset: preset)),
            ),
        for (final theme in customThemes)
          _ReaderThemeChoice(
            label: theme.name,
            colors: ReaderThemeData.resolveColors(
              appTheme,
              ReaderThemeSelection(
                preset: ReaderThemePreset.custom,
                customThemeId: theme.id,
              ),
              customThemes,
            ),
            selected:
                selection.preset == ReaderThemePreset.custom &&
                selection.customThemeId == theme.id,
            onPressed: () => onChanged(
              ReaderThemeSelection(
                preset: ReaderThemePreset.custom,
                customThemeId: theme.id,
              ),
            ),
          ),
        ActionChip(
          key: const Key('reader-theme-manage-custom'),
          avatar: const Icon(Icons.add, size: 18),
          label: const Text('自定义'),
          onPressed: onManageCustomThemes,
        ),
      ],
    );
  }
}

class _ReaderThemeChoice extends StatelessWidget {
  const _ReaderThemeChoice({
    required this.label,
    required this.colors,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final ReaderThemeColors colors;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      key: Key('reader-theme-$label'),
      selected: selected,
      onSelected: (_) => onPressed(),
      avatar: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background,
          shape: BoxShape.circle,
          border: Border.all(color: colors.foreground.withValues(alpha: .22)),
        ),
        child: SizedBox(
          width: 18,
          height: 18,
          child: Center(
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: colors.accent,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
      label: Text(label),
      selectedColor: scheme.primaryContainer,
    );
  }
}

class CustomReaderThemesDialog extends ConsumerWidget {
  const CustomReaderThemesDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themes = ref.watch(customReaderThemesProvider);
    Future<void> save(CustomReaderTheme? value) async {
      if (value == null) return;
      await ref.read(customReaderThemesProvider.notifier).save(value);
    }

    return AlertDialog(
      title: const Text('自定义阅读主题'),
      content: SizedBox(
        width: 440,
        child: themes.when(
          loading: () => const SizedBox(
            height: 100,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Text('无法读取自定义主题：$error'),
          data: (items) => items.isEmpty
              ? const Text('还没有自定义主题。可创建背景、正文和强调色三色主题。')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final theme = items[index];
                    Future<void> editTheme() async {
                      final updated = await showDialog<CustomReaderTheme>(
                        context: context,
                        builder: (_) => ReaderThemeEditorDialog(theme: theme),
                      );
                      await save(updated);
                    }

                    Future<void> removeTheme() async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: Text('删除“${theme.name}”？'),
                          content: const Text('使用它的书籍将暂时回退为跟随应用主题。'),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, false),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, true),
                              child: const Text('删除'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await ref
                            .read(customReaderThemesProvider.notifier)
                            .remove(theme.id);
                      }
                    }

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: _ThemePreview(theme: theme),
                      title: Text(theme.name),
                      subtitle: const Text('背景、正文、强调色'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '编辑主题',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: editTheme,
                          ),
                          IconButton(
                            tooltip: '删除主题',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: removeTheme,
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        FilledButton.icon(
          onPressed: () async {
            final theme = await showDialog<CustomReaderTheme>(
              context: context,
              builder: (_) => const ReaderThemeEditorDialog(),
            );
            await save(theme);
          },
          icon: const Icon(Icons.add),
          label: const Text('新建主题'),
        ),
      ],
    );
  }
}

class _ThemePreview extends StatelessWidget {
  const _ThemePreview({required this.theme});

  final CustomReaderTheme theme;

  @override
  Widget build(BuildContext context) {
    final background = Color(theme.backgroundArgb);
    final foreground = Color(theme.foregroundArgb);
    return Container(
      width: 42,
      height: 52,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: foreground.withValues(alpha: .18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 5, width: 25, color: foreground),
          const SizedBox(height: 6),
          Container(height: 5, width: 19, color: Color(theme.accentArgb)),
        ],
      ),
    );
  }
}

class ReaderThemeEditorDialog extends HookWidget {
  const ReaderThemeEditorDialog({super.key, this.theme});

  final CustomReaderTheme? theme;

  @override
  Widget build(BuildContext context) {
    final name = useTextEditingController(text: theme?.name ?? '自定义阅读主题');
    final background = useTextEditingController(
      text: _hex(theme?.backgroundArgb ?? 0xFFFAF3E6),
    );
    final foreground = useTextEditingController(
      text: _hex(theme?.foregroundArgb ?? 0xFF32302A),
    );
    final accent = useTextEditingController(
      text: _hex(theme?.accentArgb ?? 0xFF76512D),
    );
    final error = useState<String?>(null);
    final previewBackground =
        _parseArgb(background.text) ?? const Color(0xFFFAF3E6);
    final previewForeground =
        _parseArgb(foreground.text) ?? const Color(0xFF32302A);
    final previewAccent = _parseArgb(accent.text) ?? const Color(0xFF76512D);

    InputDecoration decoration(String label, String hint) =>
        InputDecoration(labelText: label, hintText: hint, prefixText: '#');

    return AlertDialog(
      title: Text(theme == null ? '新建阅读主题' : '编辑阅读主题'),
      scrollable: true,
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CustomThemeLargePreview(
              background: previewBackground,
              foreground: previewForeground,
              accent: previewAccent,
            ),
            const SizedBox(height: 18),
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: '名称'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: background,
              maxLength: 8,
              decoration: decoration('背景色', 'FAF3E6 或 FFFAF3E6'),
            ),
            TextField(
              controller: foreground,
              maxLength: 8,
              decoration: decoration('正文色', '32302A 或 FF32302A'),
            ),
            TextField(
              controller: accent,
              maxLength: 8,
              decoration: decoration('强调色', '76512D 或 FF76512D'),
            ),
            if (error.value != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
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
            final parsedBackground = _parseArgb(background.text);
            final parsedForeground = _parseArgb(foreground.text);
            final parsedAccent = _parseArgb(accent.text);
            if (name.text.trim().isEmpty ||
                parsedBackground == null ||
                parsedForeground == null ||
                parsedAccent == null) {
              error.value = '请输入名称，以及 6 或 8 位十六进制颜色。';
              return;
            }
            Navigator.pop(
              context,
              CustomReaderTheme(
                id:
                    theme?.id ??
                    'reader-theme-${DateTime.now().microsecondsSinceEpoch}',
                name: name.text.trim(),
                backgroundArgb: parsedBackground.toARGB32(),
                foregroundArgb: parsedForeground.toARGB32(),
                accentArgb: parsedAccent.toARGB32(),
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _CustomThemeLargePreview extends StatelessWidget {
  const _CustomThemeLargePreview({
    required this.background,
    required this.foreground,
    required this.accent,
  });

  final Color background;
  final Color foreground;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    height: 112,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: foreground.withValues(alpha: .16)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('阅读预览', style: TextStyle(color: foreground, fontSize: 16)),
        const SizedBox(height: 12),
        Text('自定义背景、正文与强调色。', style: TextStyle(color: foreground)),
        const Spacer(),
        Container(height: 4, width: 96, color: accent),
      ],
    ),
  );
}

String _hex(int value) => value
    .toUnsigned(32)
    .toRadixString(16)
    .padLeft(8, '0')
    .substring(2)
    .toUpperCase();

Color? _parseArgb(String source) {
  final normalized = source.trim().replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$').hasMatch(normalized)) {
    return null;
  }
  final value = normalized.length == 6 ? 'FF$normalized' : normalized;
  return Color(int.parse(value, radix: 16));
}
