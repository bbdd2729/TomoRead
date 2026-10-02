import 'package:flutter/material.dart';

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../domain/models/reading_annotation.dart';
import '../../domain/models/reading_font.dart';
import '../../domain/models/reading_settings.dart';
import '../../domain/models/text_coloring.dart';
import '../settings/font_catalog_controller.dart';
import 'text_coloring_widgets.dart';
import 'reader_theme_controller.dart';
import 'reader_theme_settings.dart';

class BookSettingsResult {
  const BookSettingsResult({
    required this.bookOverride,
    required this.textColoringOverride,
  });

  final BookReadingOverride? bookOverride;
  final bool? textColoringOverride;
}

class ReaderUnderlineColorDialog extends StatelessWidget {
  const ReaderUnderlineColorDialog({super.key});

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('تحديد لون لوحة القيادة'),
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
        child: const Text('إلغاء'),
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
    super.key,
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
    final customThemes = ref.watch(customReaderThemesProvider);
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
      title: const Text('إعدادات قراءة الكتاب'),
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
              title: const Text('استخدم إعدادات منفصلة لهذا الكتاب'),
              subtitle: const Text('عند الإغلاق، سيتبع هذا الكتاب إعدادات القراءة العالمية.'),
            ),
            if (useOverride.value) ...[
              DropdownButtonFormField<ReadingFontRef>(
                initialValue: settings.value.font,
                decoration: const InputDecoration(labelText: 'خط الحجز'),
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
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'قراءة الموضوع',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 10),
              ReaderThemePicker(
                selection: settings.value.theme,
                customThemes: customThemes.value ?? const [],
                onChanged: (theme) =>
                    settings.value = settings.value.copyWith(theme: theme),
                onManageCustomThemes: () {
                  showDialog<void>(
                    context: context,
                    builder: (_) => const CustomReaderThemesDialog(),
                  );
                },
              ),
              if (customThemes.isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: LinearProgressIndicator(),
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
                  const SizedBox(width: 64, child: Text('حجم الخط:')),
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
                  const SizedBox(width: 64, child: Text('ارتفاع الخط')),
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
                  const SizedBox(width: 64, child: Text('ادمج النقاط')),
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
                title: const Text('شاشة عريضة ذات عمود مزدوج'),
                subtitle: const Text('تعرض قراءة ترقيم الصفحات عمودين على الشاشة العريضة ويتم استخدام عمود واحد تلقائيًا على الشاشة الضيقة.'),
              ),
              SwitchListTile(
                key: const Key('book-reading-tap-to-turn-pages'),
                contentPadding: EdgeInsets.zero,
                value: settings.value.tapToTurnPages,
                onChanged: (value) => settings.value = settings.value.copyWith(
                  tapToTurnPages: value,
                ),
                title: const Text('انقر على النص لقلب الصفحة'),
                subtitle: const Text('اضغط على منفذ عرض للأمام أو للخلف عند النقر على المناطق اليسرى واليمنى من الجسم.'),
              ),
            ],
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'لون مقدمة النص',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<_BookTextColoringMode>(
              segments: const [
                ButtonSegment(
                  value: _BookTextColoringMode.followGlobal,
                  label: Text('متابعة على المستوى العالمي'),
                ),
                ButtonSegment(
                  value: _BookTextColoringMode.enabled,
                  label: Text('تشغيل'),
                ),
                ButtonSegment(
                  value: _BookTextColoringMode.disabled,
                  label: Text('مغلق'),
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
                    title: 'إدخالات في نص هذا الكتاب',
                    bookId: bookId,
                  ),
                ),
                icon: const Icon(Icons.format_color_text_outlined),
                label: const Text('إدارة إدخالات الكتب'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
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
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}
