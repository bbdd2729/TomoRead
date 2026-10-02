import 'package:flutter/material.dart';

import '../../domain/models/reading_annotation.dart';

class PdfAnnotationDraft {
  const PdfAnnotationDraft({required this.color, required this.note});

  final AnnotationColor color;
  final String? note;
}

Color pdfAnnotationColor(AnnotationColor color) => switch (color) {
  AnnotationColor.yellow => Colors.amber,
  AnnotationColor.green => Colors.green,
  AnnotationColor.blue => Colors.lightBlue,
  AnnotationColor.pink => Colors.pink,
};

class PdfAnnotationEditorDialog extends StatefulWidget {
  const PdfAnnotationEditorDialog({
    super.key,
    required this.selectedText,
    this.title = 'إضافة تمييز وملاحظات',
  });

  final String selectedText;
  final String title;

  @override
  State<PdfAnnotationEditorDialog> createState() =>
      _PdfAnnotationEditorDialogState();
}

class _PdfAnnotationEditorDialogState extends State<PdfAnnotationEditorDialog> {
  final _noteController = TextEditingController();
  AnnotationColor _color = AnnotationColor.yellow;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    scrollable: true,
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.selectedText,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 20),
          _PdfAnnotationColorPicker(
            value: _color,
            onChanged: (value) => setState(() => _color = value),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('pdf-annotation-note'),
            controller: _noteController,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'ملاحظات (اختيارية)',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
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
        key: const Key('pdf-annotation-save'),
        onPressed: () {
          final note = _noteController.text.trim();
          Navigator.pop(
            context,
            PdfAnnotationDraft(color: _color, note: note.isEmpty ? null : note),
          );
        },
        child: const Text('حفظ'),
      ),
    ],
  );
}

class PdfAnnotationColorDialog extends StatefulWidget {
  const PdfAnnotationColorDialog({
    super.key,
    required this.title,
    this.initialColor = AnnotationColor.yellow,
  });

  final String title;
  final AnnotationColor initialColor;

  @override
  State<PdfAnnotationColorDialog> createState() =>
      _PdfAnnotationColorDialogState();
}

class _PdfAnnotationColorDialogState extends State<PdfAnnotationColorDialog> {
  late AnnotationColor _color = widget.initialColor;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: _PdfAnnotationColorPicker(
      value: _color,
      onChanged: (value) => setState(() => _color = value),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _color),
        child: const Text('تأكيد'),
      ),
    ],
  );
}

class _PdfAnnotationColorPicker extends StatelessWidget {
  const _PdfAnnotationColorPicker({
    required this.value,
    required this.onChanged,
  });

  final AnnotationColor value;
  final ValueChanged<AnnotationColor> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final option in AnnotationColor.values)
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Tooltip(
            message: option.label,
            child: IconButton(
              key: Key('pdf-annotation-color-${option.name}'),
              isSelected: value == option,
              onPressed: () => onChanged(option),
              icon: CircleAvatar(
                radius: 12,
                backgroundColor: pdfAnnotationColor(option),
              ),
            ),
          ),
        ),
    ],
  );
}

class PdfAnnotationsDialog extends StatefulWidget {
  const PdfAnnotationsDialog({
    super.key,
    required this.annotations,
    required this.onDelete,
  });

  final List<ReadingAnnotation> annotations;
  final Future<void> Function(ReadingAnnotation annotation) onDelete;

  @override
  State<PdfAnnotationsDialog> createState() => _PdfAnnotationsDialogState();
}

class _PdfAnnotationsDialogState extends State<PdfAnnotationsDialog> {
  late final List<ReadingAnnotation> _annotations;
  final _deleting = <String>{};

  @override
  void initState() {
    super.initState();
    _annotations = [...widget.annotations];
  }

  Future<void> _delete(ReadingAnnotation annotation) async {
    if (!_deleting.add(annotation.id)) return;
    setState(() {});
    try {
      await widget.onDelete(annotation);
      if (mounted) {
        setState(
          () => _annotations.removeWhere((item) => item.id == annotation.id),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('فشل حذف وسيلة الشرح: $error')));
      }
    } finally {
      if (mounted) setState(() => _deleting.remove(annotation.id));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('وسيلة شرح PDF'),
    content: SizedBox(
      width: 560,
      height: (MediaQuery.sizeOf(context).height * .55)
          .clamp(240.0, 420.0)
          .toDouble(),
      child: _annotations.isEmpty
          ? const Center(child: Text('لا توجد تعليقات توضيحية بصيغة PDF حتى الآن.'))
          : ListView.separated(
              itemCount: _annotations.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final annotation = _annotations[index];
                final deleting = _deleting.contains(annotation.id);
                return ListTile(
                  key: Key('pdf-annotation-item-${annotation.id}'),
                  leading: Icon(
                    annotation.renderStyle == AnnotationRenderStyle.underline
                        ? Icons.format_underlined
                        : Icons.highlight,
                    color: pdfAnnotationColor(annotation.color),
                  ),
                  title: Text(
                    annotation.selectedText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    [
                      annotation.chapterTitle ?? 'صفحة غير معروفة',
                      if (annotation.note?.isNotEmpty == true) annotation.note!,
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: deleting
                      ? null
                      : () => Navigator.pop(context, annotation),
                  trailing: IconButton(
                    key: Key('pdf-annotation-delete-${annotation.id}'),
                    tooltip: 'حذف وسيلة الشرح',
                    onPressed: deleting ? null : () => _delete(annotation),
                    icon: deleting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_outline),
                  ),
                );
              },
            ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('مغلق'),
      ),
    ],
  );
}
