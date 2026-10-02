import 'package:flutter/material.dart';

import '../../domain/models/text_coloring.dart';
import 'text_coloring_widgets.dart';

enum _TextColoringBookMode { followGlobal, enabled, disabled }

class TextColoringOverrideResult {
  const TextColoringOverrideResult(this.value);

  final bool? value;
}

class TextColoringBookDialog extends StatefulWidget {
  const TextColoringBookDialog({
    super.key,
    required this.bookId,
    required this.settings,
    required this.bookOverride,
  });

  final String bookId;
  final TextColoringSettings settings;
  final bool? bookOverride;

  @override
  State<TextColoringBookDialog> createState() => TextColoringBookDialogState();
}

class TextColoringBookDialogState extends State<TextColoringBookDialog> {
  late _TextColoringBookMode _mode = switch (widget.bookOverride) {
    true => _TextColoringBookMode.enabled,
    false => _TextColoringBookMode.disabled,
    null => _TextColoringBookMode.followGlobal,
  };

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('لون مقدمة النص في هذا الكتاب'),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<_TextColoringBookMode>(
            segments: const [
              ButtonSegment(
                value: _TextColoringBookMode.followGlobal,
                label: Text('متابعة على المستوى العالمي'),
              ),
              ButtonSegment(
                value: _TextColoringBookMode.enabled,
                label: Text('تشغيل'),
              ),
              ButtonSegment(
                value: _TextColoringBookMode.disabled,
                label: Text('مغلق'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (value) => setState(() => _mode = value.first),
          ),
          const SizedBox(height: 16),
          Text(
            widget.settings.enabled
                ? 'لون مقدمة النص العالمي قيد التشغيل حاليًا ؛ تتجاوز إعدادات الكتاب التبديل العالمي.'
                : 'تم إيقاف تشغيل لون مقدمة النص العام حاليًا ؛ لا يمكن تشغيله إلا لهذا الكتاب.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => TextColorTermsManagerDialog(
                settings: widget.settings,
                title: 'إدخالات في نص هذا الكتاب',
                bookId: widget.bookId,
              ),
            ),
            icon: const Icon(Icons.format_color_text_outlined),
            label: const Text('إدارة إدخالات الكتب'),
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
          TextColoringOverrideResult(switch (_mode) {
            _TextColoringBookMode.followGlobal => null,
            _TextColoringBookMode.enabled => true,
            _TextColoringBookMode.disabled => false,
          }),
        ),
        child: const Text('حفظ'),
      ),
    ],
  );
}

