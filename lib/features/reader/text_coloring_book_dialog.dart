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
    title: const Text('本书文字前景色'),
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
                label: Text('跟随全局'),
              ),
              ButtonSegment(
                value: _TextColoringBookMode.enabled,
                label: Text('开启'),
              ),
              ButtonSegment(
                value: _TextColoringBookMode.disabled,
                label: Text('关闭'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (value) => setState(() => _mode = value.first),
          ),
          const SizedBox(height: 16),
          Text(
            widget.settings.enabled
                ? '全局文字前景色当前已开启；本书设置可覆盖全局开关。'
                : '全局文字前景色当前已关闭；可仅为本书开启。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => TextColorTermsManagerDialog(
                settings: widget.settings,
                title: '本书文字词条',
                bookId: widget.bookId,
              ),
            ),
            icon: const Icon(Icons.format_color_text_outlined),
            label: const Text('管理本书词条'),
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
          TextColoringOverrideResult(switch (_mode) {
            _TextColoringBookMode.followGlobal => null,
            _TextColoringBookMode.enabled => true,
            _TextColoringBookMode.disabled => false,
          }),
        ),
        child: const Text('保存'),
      ),
    ],
  );
}

