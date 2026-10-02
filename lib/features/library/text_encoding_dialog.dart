import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../data/services/book_import_service.dart';
import '../../data/services/text_decoder_service.dart';

class TextEncodingDialog extends ConsumerStatefulWidget {
  const TextEncodingDialog({super.key, required this.result});

  final BookImportResult result;

  @override
  ConsumerState<TextEncodingDialog> createState() => _TextEncodingDialogState();
}

class _TextEncodingDialogState extends ConsumerState<TextEncodingDialog> {
  late String encoding =
      widget.result.detectedEncoding ?? supportedTextEncodings.first;
  late String preview = widget.result.textPreview ?? '';
  var loadingPreview = false;
  String? previewError;

  Future<void> selectEncoding(String value) async {
    setState(() {
      encoding = value;
      loadingPreview = true;
      previewError = null;
    });
    try {
      final decoded = await ref
          .read(textDecoderServiceProvider)
          .decodeFile(widget.result.sourcePath, encodingOverride: value);
      if (!mounted) return;
      setState(() => preview = decoded.preview);
    } on Object catch (error) {
      if (mounted) setState(() => previewError = error.toString());
    } finally {
      if (mounted) setState(() => loadingPreview = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('تأكيد ترميز النص'),
    content: SizedBox(
      width: 560,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('نتائج التعرف التلقائي ليس لديها ثقة كافية، يرجى معاينة وتحديد الترميز الصحيح.'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: encoding,
            decoration: const InputDecoration(labelText: 'الترميز'),
            items: supportedTextEncodings
                .map(
                  (value) => DropdownMenuItem(
                    value: value,
                    child: Text(value.toUpperCase()),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) unawaited(selectEncoding(value));
            },
          ),
          const SizedBox(height: 14),
          Container(
            constraints: const BoxConstraints(maxHeight: 260),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              child: loadingPreview
                  ? const Center(child: CircularProgressIndicator())
                  : previewError != null
                  ? Text('لا يمكن استخدام هذا الترميز للمعاينة: $previewError')
                  : SelectableText(preview),
            ),
          ),
          const SizedBox(height: 8),
          const Text('بمجرد تحديده، سيتم إعادة ترميز الفصل وإعادة بنائه ؛ لن يتم استبدال الملف الأصلي.'),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, encoding),
        child: const Text('استيراد باستخدام هذا الترميز'),
      ),
    ],
  );
}
