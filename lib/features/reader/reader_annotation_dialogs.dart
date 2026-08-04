import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../domain/models/bookmark.dart';
import '../../domain/models/reader_text_selection.dart';
import '../../domain/models/reading_annotation.dart';
import 'reader_drafts.dart';

class BookmarkLabelDialog extends HookWidget {
  const BookmarkLabelDialog({super.key, required this.bookmark});

  final Bookmark bookmark;

  @override
  Widget build(BuildContext context) {
    final controller = useTextEditingController(text: bookmark.label ?? '');
    return AlertDialog(
      title: const Text('编辑书签'),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: InputDecoration(
            labelText: '书签名称',
            hintText: bookmark.chapterTitle,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class AnnotationNoteDialog extends HookWidget {
  const AnnotationNoteDialog({super.key, required this.annotation});

  final ReadingAnnotation annotation;

  @override
  Widget build(BuildContext context) {
    final noteController = useTextEditingController(
      text: annotation.note ?? '',
    );
    return AlertDialog(
      title: const Text('编辑笔记'),
      scrollable: true,
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              annotation.selectedText,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: noteController,
              maxLines: 4,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '笔记（留空以移除）',
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
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, AnnotationNoteDraft(noteController.text)),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class AnnotationDialog extends HookWidget {
  const AnnotationDialog({super.key, required this.selection});

  final ReaderTextSelection selection;

  @override
  Widget build(BuildContext context) {
    final color = useState(AnnotationColor.yellow);
    final noteController = useTextEditingController();
    return AlertDialog(
      title: const Text('添加高亮与笔记'),
      scrollable: true,
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              selection.text,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                for (final option in AnnotationColor.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Tooltip(
                      message: option.label,
                      child: IconButton(
                        isSelected: color.value == option,
                        onPressed: () => color.value = option,
                        icon: CircleAvatar(
                          radius: 12,
                          backgroundColor: _annotationSwatch(option),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '笔记（可选）',
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
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            AnnotationDraft(color: color.value, note: noteController.text),
          ),
          child: const Text('保存'),
        ),
      ],
    );
  }

  Color _annotationSwatch(AnnotationColor color) => switch (color) {
    AnnotationColor.yellow => Colors.amber,
    AnnotationColor.green => Colors.green,
    AnnotationColor.blue => Colors.lightBlue,
    AnnotationColor.pink => Colors.pink,
  };
}
