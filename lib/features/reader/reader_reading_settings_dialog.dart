import 'package:flutter/material.dart';

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../domain/models/reading_annotation.dart';
import '../../domain/models/reading_font.dart';
import '../../domain/models/reading_settings.dart';
import '../../domain/models/text_coloring.dart';
import '../settings/font_catalog_controller.dart';
import 'text_coloring_widgets.dart';

class BookSettingsResult {
  const BookSettingsResult({
    required this.bookOverride,
    required this.textColoringOverride,
  });

  final BookReadingOverride? bookOverride;
  final bool? textColoringOverride;
}

class ReaderUnderlineColorDialog extends StatelessWidget {
  const ReaderUnderlineColorDialog();

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('选择划线颜色'),
    content: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: AnnotationColor.values
          .map(
            (color) => ActionChip(
              avatar: CircleAvatar(backgroundColor: _annotationSwatch(color)),
              label: Text(color.label),
              onPressed: () => Navigator.pop(context, color),
            ),
          )
          .toList(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
    ],
  );

  Color _annotationSwatch(AnnotationColor color) => switch (color) {
    AnnotationColor.yellow => Colors.amber,
    AnnotationColor.green => Colors.green,
    AnnotationColor.blue => Colors.lightBlue,
    AnnotationColor.pink => Colors.pink,
  };
}

enum _BookTextColoringMode { followGlobal, enabled, disabled }

class BookReadingSettingsDialog extends HookConsumerWidget {
  const BookReadingSettingsDialog({
    required this.bookId,
    required this.defaults,
    required this.readingOverride,
    required this.textColoringSettings,
    required this.textColoringOverride,
  });

  final String bookId;
  final ReadingSettings defaults;
  final BookReadingOverride? readingOverride;
  final TextColoringSettings textColoringSettings;
  final bool? textColoringOverride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final useOverride = useState(readingOverride != null);
    final settings = useState(readingOverride?.settings ?? defaults);
    final catalog = ref.watch(fontCatalogControllerProvider).value;
    final fonts = <ReadingFontRef>{
      ReadingFontRef.system,
      ReadingFontRef.serif,
      ReadingFontRef.sansSerif,
      ReadingFontRef.monospace,
      ...?catalog?.systemFonts.map(
        (font) => ReadingFontRef.systemFamily(font.family),
      ),
      ...?catalog?.importedFonts.map((font) => font.ref),
      settings.value.font,
    }.toList();
    final textColoringMode = useState(switch (textColoringOverride) {
      true => _BookTextColoringMode.enabled,
      false => _BookTextColoringMode.disabled,
      null => _BookTextColoringMode.followGlobal,
    });
    return AlertDialog(
      title: const Text('本书阅读设置'),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: useOverride.value,
              onChanged: (value) => useOverride.value = value,
              title: const Text('使用本书独立设置'),
              subtitle: const Text('关闭后，本书将跟随全局阅读设置。'),
            ),
            if (useOverride.value) ...[
              DropdownButtonFormField<ReadingFontRef>(
                initialValue: settings.value.font,
                decoration: const InputDecoration(labelText: '书本字体'),
                items: fonts
                    .map(
                      (font) => DropdownMenuItem(
                        value: font,
                        child: Text(font.label),
                      ),
                    )
                    .toList(),
                onChanged: (font) {
                  if (font != null) {
                    settings.value = settings.value.copyWith(font: font);
                  }
                },
              ),
              const SizedBox(height: 16),
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
                selected: {settings.value.layoutMode},
                onSelectionChanged: (selection) {
                  settings.value = settings.value.copyWith(
                    layoutMode: selection.first,
                  );
                },
              ),
              const SizedBox(height: 16),
              SegmentedButton<ReaderPageTransition>(
                segments: [
                  for (final transition in ReaderPageTransition.values)
                    ButtonSegment(
                      value: transition,
                      icon: Icon(switch (transition) {
                        ReaderPageTransition.slide => Icons.swipe,
                        ReaderPageTransition.cover => Icons.layers_outlined,
                        ReaderPageTransition.fade => Icons.opacity,
                        ReaderPageTransition.none =>
                          Icons.do_not_disturb_alt_outlined,
                      }),
                      label: Text(transition.label),
                    ),
                ],
                selected: {settings.value.pageTransition},
                onSelectionChanged: (selection) {
                  settings.value = settings.value.copyWith(
                    pageTransition: selection.first,
                  );
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const SizedBox(width: 64, child: Text('字号')),
                  Expanded(
                    child: Slider(
                      value: settings.value.fontSize,
                      min: 14,
                      max: 28,
                      divisions: 14,
                      label: settings.value.fontSize.round().toString(),
                      onChanged: (value) => settings.value = settings.value
                          .copyWith(fontSize: value),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  const SizedBox(width: 64, child: Text('行高')),
                  Expanded(
                    child: Slider(
                      value: settings.value.lineHeight,
                      min: 1.4,
                      max: 2.2,
                      divisions: 8,
                      label: settings.value.lineHeight.toStringAsFixed(1),
                      onChanged: (value) => settings.value = settings.value
                          .copyWith(lineHeight: value),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  const SizedBox(width: 64, child: Text('页边距')),
                  Expanded(
                    child: Slider(
                      key: const Key('book-reading-margin'),
                      value: settings.value.pageMargin,
                      min: 16,
                      max: 64,
                      divisions: 12,
                      label: settings.value.pageMargin.round().toString(),
                      onChanged: (value) => settings.value = settings.value
                          .copyWith(pageMargin: value),
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                key: const Key('book-reading-double-column'),
                contentPadding: EdgeInsets.zero,
                value: settings.value.doubleColumn,
                onChanged: (value) => settings.value = settings.value.copyWith(
                  doubleColumn: value,
                ),
                title: const Text('宽屏双栏'),
                subtitle: const Text('分页阅读在宽屏显示双栏，窄屏自动使用单栏。'),
              ),
              SwitchListTile(
                key: const Key('book-reading-tap-to-turn-pages'),
                contentPadding: EdgeInsets.zero,
                value: settings.value.tapToTurnPages,
                onChanged: (value) => settings.value = settings.value.copyWith(
                  tapToTurnPages: value,
                ),
                title: const Text('点击正文翻页'),
                subtitle: const Text('点击正文左右区域时按一个视口前进或后退。'),
              ),
            ],
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '文本前景色',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<_BookTextColoringMode>(
              segments: const [
                ButtonSegment(
                  value: _BookTextColoringMode.followGlobal,
                  label: Text('跟随全局'),
                ),
                ButtonSegment(
                  value: _BookTextColoringMode.enabled,
                  label: Text('开启'),
                ),
                ButtonSegment(
                  value: _BookTextColoringMode.disabled,
                  label: Text('关闭'),
                ),
              ],
              selected: {textColoringMode.value},
              onSelectionChanged: (value) =>
                  textColoringMode.value = value.first,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => TextColorTermsManagerDialog(
                    settings: textColoringSettings,
                    title: '本书文字词条',
                    bookId: bookId,
                  ),
                ),
                icon: const Icon(Icons.format_color_text_outlined),
                label: const Text('管理本书词条'),
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
          onPressed: () => Navigator.pop(
            context,
            BookSettingsResult(
              bookOverride: useOverride.value
                  ? BookReadingOverride(
                      bookId: bookId,
                      settings: settings.value,
                    )
                  : null,
              textColoringOverride: switch (textColoringMode.value) {
                _BookTextColoringMode.followGlobal => null,
                _BookTextColoringMode.enabled => true,
                _BookTextColoringMode.disabled => false,
              },
            ),
          ),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
