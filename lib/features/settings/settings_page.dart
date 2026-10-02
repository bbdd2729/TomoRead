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
import '../reader/reader_shortcut_settings.dart';
import '../reader/reader_theme_controller.dart';
import '../reader/reader_theme_settings.dart';
import 'backup_restore_page.dart';
import 'embedding_settings_page.dart';
import 'font_catalog_controller.dart';
import 'storage_diagnostics_page.dart';
import 'volume_key_page_turning_setting.dart';

enum _SettingsSection { appearance, reading, aiVector, dataPrivacy }

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
              title: const Text('استيراد خطوط القراءة'),
              content: const Text(
                'يتم نسخ ملف الخط إلى دليل بيانات التطبيق. يرجى تأكيد أن لديك إذنًا باستخدام هذا الخط ؛'
                'لا تحصل TomoRead على تراخيص الخطوط أو تتحقق منها نيابة عنك.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('اختر ملفا…'),
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
              onReadingSettingsChanged(
                readingSettings.copyWith(font: font.ref),
              );
            }
          } on Object catch (error) {
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('فشل استيراد الخط: $error')));
            }
          }
        },
        onDeleteFont: readingSettings.font.importedFontId == null
            ? null
            : () async {
                final accepted = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('هل تريد حذف الخطوط المستوردة ؟'),
                    content: const Text('سيتم أولاً استبدال جميع إعدادات الكتب العامة والمفردة التي تشير إلى هذا الخط بالخط الافتراضي للنظام.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('إلغاء'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('استبدال وحذف'),
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
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('فشل حذف الخط: $error')));
                  }
                }
              },
        textColoring: textColoring,
        textColoringLoading: textColoringState.isLoading,
        onTextColoringChanged: (value) =>
            ref.read(textColoringSettingsProvider.notifier).saveSettings(value),
      ),
      _SettingsSection.aiVector => const EmbeddingSettingsPage(),
      _SettingsSection.dataPrivacy => const _DataPrivacySettings(),
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 840;
        if (compact) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
            children: [
              const PageHeader(title: 'الإعدادات', subtitle: 'اضبط مظهر التطبيق وتفضيلات القراءة الافتراضية.'),
              const SizedBox(height: 24),
              DropdownButtonFormField<_SettingsSection>(
                key: const Key('settings-section-selector'),
                initialValue: section.value,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'تعيين الفئات',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final value in _SettingsSection.values)
                    DropdownMenuItem(
                      value: value,
                      child: Row(
                        children: [
                          Icon(_settingsSectionIcon(value), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _sectionTitle(value),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) section.value = value;
                },
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
        child: Text('الإعدادات', style: Theme.of(context).textTheme.titleLarge),
      ),
      _NavigationItem(
        icon: Icons.palette_outlined,
        label: 'المظهر',
        selected: selected == _SettingsSection.appearance,
        onTap: () => onSelected(_SettingsSection.appearance),
      ),
      _NavigationItem(
        icon: Icons.menu_book_outlined,
        label: 'القراءة الافتراضية',
        selected: selected == _SettingsSection.reading,
        onTap: () => onSelected(_SettingsSection.reading),
      ),
      _NavigationItem(
        icon: Icons.hub_outlined,
        label: 'نماذج الذكاء الاصطناعي والمتجهات',
        selected: selected == _SettingsSection.aiVector,
        onTap: () => onSelected(_SettingsSection.aiVector),
      ),
      _NavigationItem(
        icon: Icons.shield_outlined,
        label: 'البيانات والخصوصية',
        selected: selected == _SettingsSection.dataPrivacy,
        onTap: () => onSelected(_SettingsSection.dataPrivacy),
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
      const _SettingsHeading('تطبيق الخط'),
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
      const _SettingsHeading('وضع العرض'),
      SegmentedButton<ThemeMode>(
        segments: const [
          ButtonSegment(
            value: ThemeMode.system,
            icon: Icon(Icons.brightness_auto),
            label: Text('اتبع النظام'),
          ),
          ButtonSegment(
            value: ThemeMode.light,
            icon: Icon(Icons.light_mode_outlined),
            label: Text('الضوء'),
          ),
          ButtonSegment(
            value: ThemeMode.dark,
            icon: Icon(Icons.dark_mode_outlined),
            label: Text('داكن'),
          ),
        ],
        selected: {appearance.mode},
        onSelectionChanged: (selection) =>
            onChanged(appearance.copyWith(mode: selection.first)),
      ),
      const SizedBox(height: 32),
      const _SettingsHeading('نظام ألوان الواجهة'),
      Text(
        'يقوم نظام الألوان بمزامنة خلفيات قراءة واجهة التطبيق و EPUB و TXT ؛ يحتفظ PDF بلون الصفحة الأصلي ويضبط فقط لون خلفية منطقة القراءة.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final style in AppThemeStyle.values)
            _ThemeStyleCard(
              style: style,
              selected: appearance.themeStyle == style,
              onPressed: () =>
                  onChanged(appearance.copyWith(themeStyle: style)),
            ),
        ],
      ),
      const SizedBox(height: 32),
      const _SettingsHeading('لون القالب'),
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
      const _SettingsHeading('تحجيم نص الواجهة'),
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

class _ThemeStyleCard extends StatelessWidget {
  const _ThemeStyleCard({
    required this.style,
    required this.selected,
    required this.onPressed,
  });

  final AppThemeStyle style;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '${style.label}موائمة الألوان${style.description}',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: Key('theme-style-${style.name}'),
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 150,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: selected
                  ? colors.primaryContainer.withValues(alpha: .38)
                  : colors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? colors.primary : colors.outlineVariant,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 72,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: style.previewColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: style == AppThemeStyle.white
                          ? const Color(0xFFDADADD)
                          : Colors.transparent,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TomoRead',
                        style: TextStyle(
                          color: style.previewForeground,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        height: 5,
                        width: 94,
                        decoration: BoxDecoration(
                          color: style.previewForeground.withValues(alpha: .34),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        height: 5,
                        width: 66,
                        decoration: BoxDecoration(
                          color: style.previewForeground.withValues(alpha: .2),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        style.label,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    if (selected)
                      Icon(Icons.check_circle, color: colors.primary, size: 18),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  style.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReadingDefaultsSettings extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final customThemes = ref.watch(customReaderThemesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SettingsHeading('خط الكتاب الافتراضي'),
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
        const _SettingsHeading('موضوع القراءة الافتراضي'),
        Text(
          'موضوع القراءة مستقل عن واجهة التطبيق ويمكن تجاوزه في إعدادات القراءة لكتاب واحد.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        ReaderThemePicker(
          selection: settings.theme,
          customThemes: customThemes.value ?? const [],
          onChanged: (theme) => onChanged(settings.copyWith(theme: theme)),
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
          )
        else if (customThemes.hasError)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'غير قادر على قراءة القالب المخصص:${customThemes.error}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 32),
        _SettingsHeading('حجم الكتاب الافتراضي${settings.fontSize.round()}'),
        Slider(
          value: settings.fontSize,
          min: 14,
          max: 28,
          divisions: 14,
          label: settings.fontSize.round().toString(),
          onChanged: (value) => onChanged(settings.copyWith(fontSize: value)),
        ),
        const SizedBox(height: 24),
        _SettingsHeading('ارتفاع سطر الكتاب الافتراضي${settings.lineHeight.toStringAsFixed(1)}'),
        Slider(
          value: settings.lineHeight,
          min: 1.4,
          max: 2.2,
          divisions: 8,
          label: settings.lineHeight.toStringAsFixed(1),
          onChanged: (value) => onChanged(settings.copyWith(lineHeight: value)),
        ),
        const SizedBox(height: 32),
        const _SettingsHeading('تخطيط القراءة'),
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
        const _SettingsHeading('حركة ترقيم الصفحات'),
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
          selected: {settings.pageTransition},
          onSelectionChanged: (selection) =>
              onChanged(settings.copyWith(pageTransition: selection.first)),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: settings.doubleColumn,
          onChanged: (value) =>
              onChanged(settings.copyWith(doubleColumn: value)),
          title: const Text('شاشة عريضة ذات عمود مزدوج'),
          subtitle: const Text('تعرض قراءة ترقيم الصفحات عمودين على الشاشة العريضة ويتم استخدام عمود واحد تلقائيًا على الشاشة الضيقة.'),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: settings.tapToTurnPages,
          onChanged: (value) =>
              onChanged(settings.copyWith(tapToTurnPages: value)),
          title: const Text('انقر فوق المنطقة لقلب الصفحة (تجريبي)'),
          subtitle: const Text('اضغط على منفذ عرض للأمام أو للخلف عند النقر على المناطق اليسرى واليمنى من الجسم.'),
        ),
        VolumeKeyPageTurningSetting(
          settings: settings,
          onChanged: onChanged,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton.icon(
              onPressed: fontsLoading ? null : onImportFont,
              icon: const Icon(Icons.font_download_outlined),
              label: const Text('استيراد الخطوط'),
            ),
            if (onDeleteFont != null)
              TextButton.icon(
                onPressed: onDeleteFont,
                icon: const Icon(Icons.delete_outline),
                label: const Text('حذف الخط الحالي'),
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
        const _SettingsHeading('لون مقدمة النص'),
        TextColoringSettingsPanel(
          settings: textColoring,
          loading: textColoringLoading,
          onChanged: onTextColoringChanged,
        ),
        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 24),
        const ReaderShortcutSettingsPanel(),
      ],
    );
  }
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

class _DataPrivacySettings extends StatelessWidget {
  const _DataPrivacySettings();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      BackupRestorePage(),
      SizedBox(height: 32),
      Divider(),
      SizedBox(height: 28),
      StorageDiagnosticsPage(),
    ],
  );
}

String _sectionTitle(_SettingsSection section) => switch (section) {
  _SettingsSection.appearance => 'المظهر',
  _SettingsSection.reading => 'القراءة الافتراضية',
  _SettingsSection.aiVector => 'نماذج الذكاء الاصطناعي والمتجهات',
  _SettingsSection.dataPrivacy => 'البيانات والخصوصية',
};

IconData _settingsSectionIcon(_SettingsSection section) => switch (section) {
  _SettingsSection.appearance => Icons.palette_outlined,
  _SettingsSection.reading => Icons.menu_book_outlined,
  _SettingsSection.aiVector => Icons.hub_outlined,
  _SettingsSection.dataPrivacy => Icons.shield_outlined,
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
  _SettingsSection.appearance => 'اضبط السمة واللون والخط وقياس الواجهة.',
  _SettingsSection.reading => 'قم بتعيين الطباعة الافتراضية لكتب EPUB المفتوحة حديثًا.',
  _SettingsSection.aiVector => 'تكوين خدمة التضمين، وتفويض الجسم عن بعد، والفهرسة الدلالية بشكل مستقل.',
  _SettingsSection.dataPrivacy => 'إنشاء نسخ احتياطية يمكن التحقق منها، واستردادها بشكل آمن وتنظيفها لإعادة بناء ذاكرة التخزين المؤقت.',
};
