import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/appearance.dart';
import '../../domain/models/font_choice.dart';
import '../../domain/models/reading_font.dart';
import '../../domain/models/reading_settings.dart';
import '../../domain/models/text_coloring.dart';
import '../../shared/widgets/page_header.dart';
import '../reader/text_coloring_controller.dart';
import '../reader/text_coloring_widgets.dart';
import 'font_catalog_controller.dart';

enum _SettingsSection { appearance, reading }

class SettingsPage extends HookConsumerWidget {
  const SettingsPage({
    super.key,
    required this.appearance,
    required this.readingSettings,
    required this.onAppearanceChanged,
    required this.onReadingSettingsChanged,
  });

  final AppAppearance appearance;
  final ReadingSettings readingSettings;
  final ValueChanged<AppAppearance> onAppearanceChanged;
  final ValueChanged<ReadingSettings> onReadingSettingsChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = useState(_SettingsSection.appearance);
    final textColoringState = ref.watch(textColoringSettingsProvider);
    final fontCatalogState = ref.watch(fontCatalogControllerProvider);
    final availableFonts = _availableReadingFonts(
      readingSettings.font,
      fontCatalogState.value,
    );
    final textColoring =
        textColoringState.value ?? TextColoringSettings.defaults();
    final sectionContent = switch (section.value) {
      _SettingsSection.appearance => _AppearanceSettings(
        appearance: appearance,
        onChanged: onAppearanceChanged,
      ),
      _SettingsSection.reading => _ReadingDefaultsSettings(
        settings: readingSettings,
        onChanged: onReadingSettingsChanged,
        fonts: availableFonts,
        fontsLoading: fontCatalogState.isLoading,
        onImportFont: () async {
          final accepted = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('导入阅读字体'),
              content: const Text(
                '字体文件会复制到应用数据目录。请确认你有权使用该字体；'
                'TomoRead 不会替你取得或验证字体许可证。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('选择文件'),
                ),
              ],
            ),
          );
          if (accepted != true || !context.mounted) return;
          try {
            final font = await ref
                .read(fontCatalogControllerProvider.notifier)
                .importFromPicker();
            if (font != null && context.mounted) {
              onReadingSettingsChanged(readingSettings.copyWith(font: font.ref));
            }
          } on Object catch (error) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('字体导入失败：$error')),
              );
            }
          }
        },
        onDeleteFont: readingSettings.font.importedFontId == null
            ? null
            : () async {
                final accepted = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('删除已导入字体？'),
                    content: const Text(
                      '所有引用该字体的全局及单本书设置会先替换为系统默认字体。',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('替换并删除'),
                      ),
                    ],
                  ),
                );
                if (accepted != true) return;
                try {
                  await ref
                      .read(fontCatalogControllerProvider.notifier)
                      .delete(
                        readingSettings.font.importedFontId!,
                        replacement: ReadingFontRef.system,
                      );
                  onReadingSettingsChanged(
                    readingSettings.copyWith(font: ReadingFontRef.system),
                  );
                } on Object catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('字体删除失败：$error')),
                    );
                  }
                }
              },
        textColoring: textColoring,
        textColoringLoading: textColoringState.isLoading,
        onTextColoringChanged: (value) => ref
            .read(textColoringSettingsProvider.notifier)
            .saveSettings(value),
      ),
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 840;
        if (compact) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
            children: [
              const PageHeader(title: '设置', subtitle: '调整应用外观和默认阅读偏好。'),
              const SizedBox(height: 24),
              SegmentedButton<_SettingsSection>(
                segments: const [
                  ButtonSegment(
                    value: _SettingsSection.appearance,
                    icon: Icon(Icons.palette_outlined),
                    label: Text('外观'),
                  ),
                  ButtonSegment(
                    value: _SettingsSection.reading,
                    icon: Icon(Icons.menu_book_outlined),
                    label: Text('阅读'),
                  ),
                ],
                selected: {section.value},
                onSelectionChanged: (selection) =>
                    section.value = selection.first,
              ),
              const SizedBox(height: 28),
              sectionContent,
            ],
          );
        }

        return Row(
          children: [
            SizedBox(
              width: 248,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                child: _SettingsNavigation(
                  selected: section.value,
                  onSelected: (value) => section.value = value,
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(40, 36, 40, 56),
                children: [
                  PageHeader(
                    title: _sectionTitle(section.value),
                    subtitle: _sectionSubtitle(section.value),
                  ),
                  const SizedBox(height: 28),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: sectionContent,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SettingsNavigation extends StatelessWidget {
  const _SettingsNavigation({required this.selected, required this.onSelected});

  final _SettingsSection selected;
  final ValueChanged<_SettingsSection> onSelected;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Text('设置', style: Theme.of(context).textTheme.titleLarge),
      ),
      _NavigationItem(
        icon: Icons.palette_outlined,
        label: '应用外观',
        selected: selected == _SettingsSection.appearance,
        onTap: () => onSelected(_SettingsSection.appearance),
      ),
      _NavigationItem(
        icon: Icons.menu_book_outlined,
        label: '默认阅读',
        selected: selected == _SettingsSection.reading,
        onTap: () => onSelected(_SettingsSection.reading),
      ),
    ],
  );
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: selected ? colorScheme.primary : Colors.transparent,
            width: 3,
          ),
        ),
      ),
      child: Material(
        color: selected ? colorScheme.surfaceContainerLow : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: ListTile(
          selected: false,
          leading: Icon(icon, color: selected ? colorScheme.primary : null),
          title: Text(
            label,
            style: selected
                ? TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  )
                : null,
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _AppearanceSettings extends StatelessWidget {
  const _AppearanceSettings({
    required this.appearance,
    required this.onChanged,
  });

  final AppAppearance appearance;
  final ValueChanged<AppAppearance> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _SettingsHeading('应用字体'),
      DropdownButtonFormField<FontChoice>(
        initialValue: appearance.uiFont,
        decoration: const InputDecoration(border: OutlineInputBorder()),
        items: [
          for (final font in FontChoice.values)
            DropdownMenuItem(value: font, child: Text(font.label)),
        ],
        onChanged: (font) {
          if (font != null) onChanged(appearance.copyWith(uiFont: font));
        },
      ),
      const SizedBox(height: 32),
      const _SettingsHeading('显示模式'),
      SegmentedButton<ThemeMode>(
        segments: const [
          ButtonSegment(
            value: ThemeMode.system,
            icon: Icon(Icons.brightness_auto),
            label: Text('跟随系统'),
          ),
          ButtonSegment(
            value: ThemeMode.light,
            icon: Icon(Icons.light_mode_outlined),
            label: Text('浅色'),
          ),
          ButtonSegment(
            value: ThemeMode.dark,
            icon: Icon(Icons.dark_mode_outlined),
            label: Text('深色'),
          ),
        ],
        selected: {appearance.mode},
        onSelectionChanged: (selection) =>
            onChanged(appearance.copyWith(mode: selection.first)),
      ),
      const SizedBox(height: 32),
      const _SettingsHeading('主题色'),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final seed in ThemeSeed.values)
            Tooltip(
              message: seed.label,
              child: IconButton(
                key: Key('theme-${seed.name}'),
                isSelected: appearance.seed == seed,
                onPressed: () => onChanged(appearance.copyWith(seed: seed)),
                icon: CircleAvatar(
                  radius: 16,
                  backgroundColor: seed.color,
                  child: appearance.seed == seed
                      ? const Icon(Icons.check, color: Colors.white)
                      : null,
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 32),
      const _SettingsHeading('界面文字缩放'),
      Row(
        children: [
          const Text('A', style: TextStyle(fontSize: 14)),
          Expanded(
            child: Slider(
              value: appearance.textScale,
              min: .85,
              max: 1.25,
              divisions: 4,
              label: '${(appearance.textScale * 100).round()}%',
              onChanged: (value) =>
                  onChanged(appearance.copyWith(textScale: value)),
            ),
          ),
          const Text('A', style: TextStyle(fontSize: 22)),
        ],
      ),
    ],
  );
}

class _ReadingDefaultsSettings extends StatelessWidget {
  const _ReadingDefaultsSettings({
    required this.settings,
    required this.onChanged,
    required this.fonts,
    required this.fontsLoading,
    required this.onImportFont,
    required this.onDeleteFont,
    required this.textColoring,
    required this.textColoringLoading,
    required this.onTextColoringChanged,
  });

  final ReadingSettings settings;
  final ValueChanged<ReadingSettings> onChanged;
  final List<ReadingFontRef> fonts;
  final bool fontsLoading;
  final Future<void> Function() onImportFont;
  final Future<void> Function()? onDeleteFont;
  final TextColoringSettings textColoring;
  final bool textColoringLoading;
  final ValueChanged<TextColoringSettings> onTextColoringChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _SettingsHeading('默认书本字体'),
      DropdownButtonFormField<ReadingFontRef>(
        initialValue: settings.font,
        decoration: const InputDecoration(border: OutlineInputBorder()),
        items: [
          for (final font in fonts)
            DropdownMenuItem(value: font, child: Text(font.label)),
        ],
        onChanged: (font) {
          if (font != null) onChanged(settings.copyWith(font: font));
        },
      ),
      const SizedBox(height: 32),
      _SettingsHeading('默认书本字号 ${settings.fontSize.round()}'),
      Slider(
        value: settings.fontSize,
        min: 14,
        max: 28,
        divisions: 14,
        label: settings.fontSize.round().toString(),
        onChanged: (value) => onChanged(settings.copyWith(fontSize: value)),
      ),
      const SizedBox(height: 24),
      _SettingsHeading('默认书本行高 ${settings.lineHeight.toStringAsFixed(1)}'),
      Slider(
        value: settings.lineHeight,
        min: 1.4,
        max: 2.2,
        divisions: 8,
        label: settings.lineHeight.toStringAsFixed(1),
        onChanged: (value) => onChanged(settings.copyWith(lineHeight: value)),
      ),
      const SizedBox(height: 32),
      const _SettingsHeading('阅读布局'),
      SegmentedButton<ReaderLayoutMode>(
        segments: [
          for (final mode in ReaderLayoutMode.values)
            ButtonSegment(
              value: mode,
              icon: Icon(
                mode == ReaderLayoutMode.scroll
                    ? Icons.swap_vert
                    : Icons.auto_stories_outlined,
              ),
              label: Text(mode.label),
            ),
        ],
        selected: {settings.layoutMode},
        onSelectionChanged: (selection) =>
            onChanged(settings.copyWith(layoutMode: selection.first)),
      ),
      const SizedBox(height: 24),
      const _SettingsHeading('分页动画'),
      SegmentedButton<ReaderPageTransition>(
        segments: [
          for (final transition in ReaderPageTransition.values)
            ButtonSegment(
              value: transition,
              icon: Icon(switch (transition) {
                ReaderPageTransition.slide => Icons.swipe,
                ReaderPageTransition.cover => Icons.layers_outlined,
                ReaderPageTransition.fade => Icons.opacity,
                ReaderPageTransition.none => Icons.do_not_disturb_alt_outlined,
              }),
              label: Text(transition.label),
            ),
        ],
        selected: {settings.pageTransition},
        onSelectionChanged: (selection) =>
            onChanged(settings.copyWith(pageTransition: selection.first)),
      ),
      const SizedBox(height: 16),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: settings.doubleColumn,
        onChanged: (value) => onChanged(settings.copyWith(doubleColumn: value)),
        title: const Text('宽屏双栏'),
        subtitle: const Text('分页阅读在宽屏显示双栏，窄屏自动使用单栏。'),
      ),
      const SizedBox(height: 8),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: settings.tapToTurnPages,
        onChanged: (value) =>
            onChanged(settings.copyWith(tapToTurnPages: value)),
        title: const Text('点击区域翻页（实验性）'),
        subtitle: const Text('点击正文左右区域时按一个视口前进或后退。'),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          TextButton.icon(
            onPressed: fontsLoading ? null : onImportFont,
            icon: const Icon(Icons.font_download_outlined),
            label: const Text('导入字体'),
          ),
          if (onDeleteFont != null)
            TextButton.icon(
              onPressed: onDeleteFont,
              icon: const Icon(Icons.delete_outline),
              label: const Text('删除当前字体'),
            ),
          if (fontsLoading) ...[
            const SizedBox(width: 12),
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ],
      ),
      const SizedBox(height: 32),
      const Divider(),
      const SizedBox(height: 24),
      const _SettingsHeading('文本前景色'),
      TextColoringSettingsPanel(
        settings: textColoring,
        loading: textColoringLoading,
        onChanged: onTextColoringChanged,
      ),
    ],
  );
}

class _SettingsHeading extends StatelessWidget {
  const _SettingsHeading(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );
}

String _sectionTitle(_SettingsSection section) => switch (section) {
  _SettingsSection.appearance => '应用外观',
  _SettingsSection.reading => '默认阅读',
};

List<ReadingFontRef> _availableReadingFonts(
  ReadingFontRef selected,
  FontCatalogState? catalog,
) {
  final fonts = <ReadingFontRef>[
    ReadingFontRef.system,
    ReadingFontRef.serif,
    ReadingFontRef.sansSerif,
    ReadingFontRef.monospace,
    ...?catalog?.systemFonts.map(
      (font) => ReadingFontRef.systemFamily(font.family),
    ),
    ...?catalog?.importedFonts.map((font) => font.ref),
  ];
  if (!fonts.contains(selected)) fonts.add(selected);
  return fonts.toSet().toList();
}

String _sectionSubtitle(_SettingsSection section) => switch (section) {
  _SettingsSection.appearance => '调整主题、颜色、字体和界面缩放。',
  _SettingsSection.reading => '为新打开的 EPUB 书籍设置默认排版。',
};
