import 'package:flutter/material.dart';

import '../../domain/models/bookmark.dart';
import '../../domain/models/reading_annotation.dart';

class MobileReaderSideDrawer extends StatelessWidget {
  const MobileReaderSideDrawer({
    required this.showBookmarks,
    required this.bookmarks,
    required this.annotations,
    required this.onPanelChanged,
    required this.onSelectBookmark,
    required this.onRemoveBookmark,
    required this.onEditBookmark,
    required this.onSelectAnnotation,
    required this.onEditAnnotation,
    required this.onRemoveAnnotation,
  });

  final bool showBookmarks;
  final List<Bookmark> bookmarks;
  final List<ReadingAnnotation> annotations;
  final ValueChanged<bool> onPanelChanged;
  final Future<void> Function(Bookmark bookmark) onSelectBookmark;
  final Future<void> Function(Bookmark bookmark) onRemoveBookmark;
  final Future<void> Function(Bookmark bookmark) onEditBookmark;
  final ValueChanged<ReadingAnnotation> onSelectAnnotation;
  final Future<void> Function(ReadingAnnotation annotation) onEditAnnotation;
  final Future<void> Function(ReadingAnnotation annotation) onRemoveAnnotation;

  @override
  Widget build(BuildContext context) => ReaderBottomSheet(
    child: Column(
      children: [
        Padding(
          key: const Key('reader-mobile-side-header'),
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '书签与笔记',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: '关闭面板',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ReaderSidePanel(
            showBookmarks: showBookmarks,
            bookmarks: bookmarks,
            annotations: annotations,
            onPanelChanged: onPanelChanged,
            onSelectBookmark: onSelectBookmark,
            onRemoveBookmark: onRemoveBookmark,
            onEditBookmark: onEditBookmark,
            onSelectAnnotation: onSelectAnnotation,
            onEditAnnotation: onEditAnnotation,
            onRemoveAnnotation: onRemoveAnnotation,
          ),
        ),
      ],
    ),
  );
}

class ReaderBottomSheet extends StatelessWidget {
  const ReaderBottomSheet({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: .82,
    alignment: Alignment.bottomCenter,
    child: Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    ),
  );
}

class ReaderSidePanel extends StatelessWidget {
  const ReaderSidePanel({
    required this.showBookmarks,
    required this.bookmarks,
    required this.annotations,
    required this.onPanelChanged,
    required this.onSelectBookmark,
    required this.onRemoveBookmark,
    required this.onEditBookmark,
    required this.onSelectAnnotation,
    required this.onEditAnnotation,
    required this.onRemoveAnnotation,
  });

  final bool showBookmarks;
  final List<Bookmark> bookmarks;
  final List<ReadingAnnotation> annotations;
  final ValueChanged<bool> onPanelChanged;
  final Future<void> Function(Bookmark bookmark) onSelectBookmark;
  final Future<void> Function(Bookmark bookmark) onRemoveBookmark;
  final Future<void> Function(Bookmark bookmark) onEditBookmark;
  final ValueChanged<ReadingAnnotation> onSelectAnnotation;
  final Future<void> Function(ReadingAnnotation annotation) onEditAnnotation;
  final Future<void> Function(ReadingAnnotation annotation) onRemoveAnnotation;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: false,
                icon: const Icon(Icons.sticky_note_2_outlined),
                label: Text('笔记 ${annotations.length}'),
              ),
              ButtonSegment(
                value: true,
                icon: const Icon(Icons.bookmark_border),
                label: Text('书签 ${bookmarks.length}'),
              ),
            ],
            selected: {showBookmarks},
            onSelectionChanged: (selection) => onPanelChanged(selection.first),
          ),
          const SizedBox(height: 20),
          if (showBookmarks) ...[
            Text('书签', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (bookmarks.isEmpty)
              const Expanded(child: Center(child: Text('当前书籍还没有书签。')))
            else
              Expanded(
                child: ListView.builder(
                  itemCount: bookmarks.length,
                  itemBuilder: (context, index) {
                    final bookmark = bookmarks[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.bookmark),
                      title: Text(bookmark.label ?? bookmark.chapterTitle),
                      subtitle: Text(
                        '保存于 ${bookmark.createdAt.hour.toString().padLeft(2, '0')}:${bookmark.createdAt.minute.toString().padLeft(2, '0')}',
                      ),
                      onTap: () => onSelectBookmark(bookmark),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '编辑书签',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => onEditBookmark(bookmark),
                          ),
                          IconButton(
                            tooltip: '删除书签',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => onRemoveBookmark(bookmark),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ] else ...[
            Text('笔记与标注', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            if (annotations.isEmpty)
              const Expanded(child: Center(child: Text('选中文本后可创建高亮和笔记。')))
            else
              Expanded(
                child: ListView.separated(
                  itemCount: annotations.length,
                  separatorBuilder: (context, index) => const Divider(),
                  itemBuilder: (context, index) {
                    final annotation = annotations[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 8,
                        backgroundColor: _annotationColor(annotation.color),
                      ),
                      title: Text(
                        annotation.selectedText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: annotation.note == null
                          ? const Text('高亮')
                          : Text(annotation.note!, maxLines: 3),
                      onTap: () => onSelectAnnotation(annotation),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '编辑笔记',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => onEditAnnotation(annotation),
                          ),
                          IconButton(
                            tooltip: '删除标注',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => onRemoveAnnotation(annotation),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ],
      ),
    );
  }

  Color _annotationColor(AnnotationColor color) => switch (color) {
    AnnotationColor.yellow => Colors.amber,
    AnnotationColor.green => Colors.green,
    AnnotationColor.blue => Colors.lightBlue,
    AnnotationColor.pink => Colors.pink,
  };
}
