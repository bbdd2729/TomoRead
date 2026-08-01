import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models/annotation_query.dart';
import '../../domain/models/epub_location.dart';
import '../../domain/models/library_book.dart';
import '../../domain/models/reading_annotation.dart';
import '../../shared/widgets/page_header.dart';
import 'notes_providers.dart';

class NotesPage extends HookConsumerWidget {
  const NotesPage({super.key, this.onOpenReader});

  final ValueChanged<LibraryBook>? onOpenReader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(annotationQueryProvider);
    final itemsState = ref.watch(annotationItemsProvider);
    final facetsState = ref.watch(annotationFacetsProvider);
    final books =
        ref.watch(libraryBooksProvider).value ?? const <LibraryBook>[];
    final selectedId = useState<String?>(null);
    final searchController = useTextEditingController(text: query.text);
    final searchTimer = useRef<Timer?>(null);

    useEffect(
      () =>
          () => searchTimer.value?.cancel(),
      const [],
    );

    final items = itemsState.value ?? const <AnnotationListItem>[];
    final selected = items
        .where((item) => item.annotation.id == selectedId.value)
        .firstOrNull;
    useEffect(() {
      if (items.isEmpty) {
        selectedId.value = null;
      } else if (selected == null) {
        selectedId.value = items.first.annotation.id;
      }
      return null;
    }, [itemsState.value]);

    void updateQuery(AnnotationQuery value) {
      ref.read(annotationQueryProvider.notifier).update(value);
    }

    Future<void> openOriginal(AnnotationListItem item) async {
      final book = item.book;
      if (book == null || onOpenReader == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('原书籍已移除，无法打开原文。')));
        }
        return;
      }
      var chapterIndex = item.annotation.chapterIndex;
      if (chapterIndex == null && book.format == 'epub') {
        final manifest = await ref
            .read(bookRepositoryProvider)
            .loadManifest(book.id);
        chapterIndex = manifest?.spine.indexWhere(
          (entry) =>
              _stripFragment(entry.href) ==
              _stripFragment(item.annotation.href),
        );
        if (chapterIndex != null && chapterIndex < 0) chapterIndex = null;
      }
      final index = chapterIndex ?? book.chapterIndex;
      final cfi = item.annotation.locator.startsWith('cfi:')
          ? item.annotation.locator.substring(4)
          : null;
      final locator = book.format == 'epub'
          ? EpubLocation(
              chapterIndex: index,
              scrollRatio: 0,
              cfi: cfi,
            ).toLocator()
          : item.annotation.locator;
      await ref
          .read(bookRepositoryProvider)
          .updateReadingPosition(
            bookId: book.id,
            chapterIndex: index,
            progress: book.chapterCount <= 1
                ? 0
                : index / (book.chapterCount - 1),
            locator: locator,
          );
      ref.invalidate(readerBookProvider(book.id));
      ref.invalidate(libraryBooksProvider);
      if (context.mounted) onOpenReader!(book);
    }

    Future<void> exportNotes(bool json) async {
      try {
        final service = ref.read(annotationExportServiceProvider);
        final content = json
            ? await service.buildJson(query)
            : await service.buildMarkdown(query);
        final mobile = Platform.isAndroid || Platform.isIOS;
        final path = await FilePicker.saveFile(
          dialogTitle: '导出阅读笔记',
          fileName: json ? 'tomoread-notes.json' : 'tomoread-notes.md',
          type: FileType.custom,
          allowedExtensions: [json ? 'json' : 'md'],
          bytes: mobile ? Uint8List.fromList(utf8.encode(content)) : null,
        );
        if (path == null) return;
        if (!mobile) await File(path).writeAsString(content);
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('已导出到 $path')));
        }
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('导出失败：$error')));
        }
      }
    }

    Widget buildFilterButton() => IconButton(
      tooltip: '筛选笔记',
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: _AnnotationFilterPanel(
              query: query,
              books: books,
              tags: facetsState.value?.tags ?? const [],
              onChanged: updateQuery,
            ),
          ),
        ),
      ),
      icon: const Icon(Icons.tune),
    );

    final list = _AnnotationResultList(
      itemsState: itemsState,
      selectedId: selectedId.value,
      onSelected: (item) async {
        selectedId.value = item.annotation.id;
        if (MediaQuery.sizeOf(context).width < 760) {
          await showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (context) => FractionallySizedBox(
              heightFactor: .92,
              child: _AnnotationDetailPane(
                key: ValueKey(item.annotation.id),
                item: item,
                onOpenOriginal: () => openOriginal(item),
              ),
            ),
          );
        }
      },
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final wide = constraints.maxWidth >= 1120;
        final header = Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 20 : 28,
            24,
            compact ? 12 : 20,
            18,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeader(
                title: '笔记',
                subtitle: facetsState.value == null
                    ? '整理高亮、注释与阅读思考'
                    : '${facetsState.value!.totalCount} 条高亮 · ${facetsState.value!.noteCount} 条笔记',
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('notes-search'),
                      controller: searchController,
                      decoration: const InputDecoration(
                        hintText: '搜索摘录、笔记、书名或作者',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) {
                        searchTimer.value?.cancel();
                        searchTimer.value = Timer(
                          const Duration(milliseconds: 280),
                          () => updateQuery(query.copyWith(text: value)),
                        );
                      },
                    ),
                  ),
                  if (!wide) ...[const SizedBox(width: 8), buildFilterButton()],
                  const SizedBox(width: 4),
                  PopupMenuButton<bool>(
                    tooltip: '导出',
                    onSelected: exportNotes,
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: false, child: Text('导出 Markdown')),
                      PopupMenuItem(value: true, child: Text('导出 JSON')),
                    ],
                    icon: const Icon(Icons.download_outlined),
                  ),
                ],
              ),
            ],
          ),
        );

        if (compact) {
          return Column(
            children: [
              header,
              const Divider(height: 1),
              Expanded(child: list),
            ],
          );
        }
        return Column(
          children: [
            header,
            const Divider(height: 1),
            Expanded(
              child: Row(
                children: [
                  if (wide) ...[
                    SizedBox(
                      width: 276,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: _AnnotationFilterPanel(
                          query: query,
                          books: books,
                          tags: facetsState.value?.tags ?? const [],
                          onChanged: updateQuery,
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                  ],
                  SizedBox(width: wide ? 360 : 330, child: list),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: selected == null
                        ? const _NoAnnotationSelected()
                        : _AnnotationDetailPane(
                            key: ValueKey(selected.annotation.id),
                            item: selected,
                            onOpenOriginal: () => openOriginal(selected),
                          ),
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

class _AnnotationFilterPanel extends StatelessWidget {
  const _AnnotationFilterPanel({
    required this.query,
    required this.books,
    required this.tags,
    required this.onChanged,
  });

  final AnnotationQuery query;
  final List<LibraryBook> books;
  final List<String> tags;
  final ValueChanged<AnnotationQuery> onChanged;

  @override
  Widget build(BuildContext context) => ListView(
    shrinkWrap: true,
    children: [
      Row(
        children: [
          Expanded(
            child: Text('筛选', style: Theme.of(context).textTheme.titleMedium),
          ),
          TextButton(
            onPressed: () => onChanged(const AnnotationQuery()),
            child: const Text('重置'),
          ),
        ],
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<String?>(
        initialValue: query.bookId,
        decoration: const InputDecoration(labelText: '书籍'),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('全部书籍')),
          ...books.map(
            (book) => DropdownMenuItem<String?>(
              value: book.id,
              child: Text(book.title, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        onChanged: (value) => onChanged(
          value == null
              ? query.copyWith(clearBook: true)
              : query.copyWith(bookId: value),
        ),
      ),
      const SizedBox(height: 20),
      Text('类型', style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 8),
      SegmentedButton<bool?>(
        segments: const [
          ButtonSegment(value: null, label: Text('全部')),
          ButtonSegment(value: true, label: Text('有笔记')),
          ButtonSegment(value: false, label: Text('仅高亮')),
        ],
        selected: {query.hasNote},
        onSelectionChanged: (value) => onChanged(
          value.first == null
              ? query.copyWith(clearHasNote: true)
              : query.copyWith(hasNote: value.first),
        ),
      ),
      const SizedBox(height: 20),
      Text('颜色', style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        children: AnnotationColor.values.map((color) {
          final selected = query.colors.contains(color);
          return FilterChip(
            selected: selected,
            avatar: CircleAvatar(
              backgroundColor: _annotationColor(context, color),
              radius: 6,
            ),
            label: Text(color.label),
            onSelected: (_) {
              final next = {...query.colors};
              selected ? next.remove(color) : next.add(color);
              onChanged(query.copyWith(colors: next));
            },
          );
        }).toList(),
      ),
      if (tags.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text('标签', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: tags.take(12).map((tag) {
            final selected = query.tags.contains(tag);
            return FilterChip(
              selected: selected,
              label: Text(tag),
              onSelected: (_) {
                final next = {...query.tags};
                selected ? next.remove(tag) : next.add(tag);
                onChanged(query.copyWith(tags: next));
              },
            );
          }).toList(),
        ),
      ],
      const SizedBox(height: 20),
      DropdownButtonFormField<AnnotationSort>(
        initialValue: query.sort,
        decoration: const InputDecoration(labelText: '排序'),
        items: const [
          DropdownMenuItem(value: AnnotationSort.newest, child: Text('最新创建')),
          DropdownMenuItem(
            value: AnnotationSort.recentlyEdited,
            child: Text('最近编辑'),
          ),
          DropdownMenuItem(value: AnnotationSort.oldest, child: Text('最早创建')),
        ],
        onChanged: (value) {
          if (value != null) onChanged(query.copyWith(sort: value));
        },
      ),
    ],
  );
}

class _AnnotationResultList extends StatelessWidget {
  const _AnnotationResultList({
    required this.itemsState,
    required this.selectedId,
    required this.onSelected,
  });

  final AsyncValue<List<AnnotationListItem>> itemsState;
  final String? selectedId;
  final ValueChanged<AnnotationListItem> onSelected;

  @override
  Widget build(BuildContext context) => itemsState.when(
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (error, _) => Center(child: Text('无法加载笔记：$error')),
    data: (items) {
      if (items.isEmpty) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_stories_outlined, size: 44),
                SizedBox(height: 12),
                Text('还没有符合条件的笔记'),
                SizedBox(height: 4),
                Text('在阅读器中选择文字即可创建高亮或注释。'),
              ],
            ),
          ),
        );
      }
      return ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = items[index];
          final annotation = item.annotation;
          return ListTile(
            selected: selectedId == annotation.id,
            contentPadding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            leading: Container(
              width: 4,
              height: 52,
              decoration: BoxDecoration(
                color: _annotationColor(context, annotation.color),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            title: Text(
              annotation.selectedText.replaceAll(RegExp(r'\s+'), ' '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${item.book?.title ?? '已移除的书籍'} · ${annotation.chapterTitle ?? '未知章节'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            trailing: annotation.note == null
                ? null
                : const Icon(Icons.sticky_note_2_outlined, size: 18),
            onTap: () => onSelected(item),
          );
        },
      );
    },
  );
}

class _AnnotationDetailPane extends HookConsumerWidget {
  const _AnnotationDetailPane({
    super.key,
    required this.item,
    required this.onOpenOriginal,
  });

  final AnnotationListItem item;
  final VoidCallback onOpenOriginal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final annotation = item.annotation;
    final noteController = useTextEditingController(
      text: annotation.note ?? '',
    );
    final tagController = useTextEditingController();
    final saveTimer = useRef<Timer?>(null);
    final saving = useState(false);
    final preview = useState(false);
    useEffect(
      () =>
          () => saveTimer.value?.cancel(),
      [annotation.id],
    );

    Future<void> saveNote() async {
      saveTimer.value?.cancel();
      saving.value = true;
      try {
        await ref
            .read(annotationControllerProvider)
            .updateNote(annotation.id, noteController.text);
      } finally {
        if (context.mounted) saving.value = false;
      }
    }

    Future<void> remove() async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除这条标注？'),
          content: const Text('高亮、笔记和标签都会从本地书库中移除。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await ref.read(annotationControllerProvider).remove(annotation.id);
        if (context.mounted && Navigator.of(context).canPop()) {
          Navigator.maybePop(context);
        }
      }
    }

    Future<void> addTag() async {
      final tag = tagController.text.trim();
      if (tag.isEmpty || annotation.tags.contains(tag)) return;
      await ref.read(annotationControllerProvider).replaceTags(annotation.id, [
        ...annotation.tags,
        tag,
      ]);
      tagController.clear();
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 48),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.book?.title ?? '已移除的书籍',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    annotation.chapterTitle ?? '未知章节',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '打开原文',
              onPressed: onOpenOriginal,
              icon: const Icon(Icons.open_in_new),
            ),
            IconButton(
              tooltip: '删除',
              onPressed: remove,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        const SizedBox(height: 22),
        DecoratedBox(
          decoration: BoxDecoration(
            color: _annotationColor(
              context,
              annotation.color,
            ).withValues(alpha: .14),
            border: Border(
              left: BorderSide(
                color: _annotationColor(context, annotation.color),
                width: 4,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: SelectableText(
              annotation.selectedText,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ),
        const SizedBox(height: 26),
        Row(
          children: [
            Expanded(
              child: Text(
                '我的笔记',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (saving.value)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.edit_outlined),
                  label: Text('编辑'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.visibility_outlined),
                  label: Text('预览'),
                ),
              ],
              selected: {preview.value},
              onSelectionChanged: (value) => preview.value = value.first,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (preview.value)
          noteController.text.trim().isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Text('还没有笔记内容。'),
                )
              : SelectionArea(child: MarkdownBody(data: noteController.text))
        else
          TextField(
            controller: noteController,
            minLines: 7,
            maxLines: 18,
            decoration: const InputDecoration(
              hintText: '记录想法，支持 Markdown',
              alignLabelWithHint: true,
            ),
            onChanged: (_) {
              saveTimer.value?.cancel();
              saveTimer.value = Timer(
                const Duration(milliseconds: 700),
                saveNote,
              );
            },
            onSubmitted: (_) => saveNote(),
          ),
        const SizedBox(height: 24),
        Text('标签', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...annotation.tags.map(
              (tag) => InputChip(
                label: Text(tag),
                onDeleted: () => ref
                    .read(annotationControllerProvider)
                    .replaceTags(
                      annotation.id,
                      annotation.tags.where((item) => item != tag).toList(),
                    ),
              ),
            ),
            SizedBox(
              width: 180,
              child: TextField(
                controller: tagController,
                decoration: InputDecoration(
                  hintText: '添加标签',
                  isDense: true,
                  suffixIcon: IconButton(
                    tooltip: '添加标签',
                    onPressed: addTag,
                    icon: const Icon(Icons.add),
                  ),
                ),
                onSubmitted: (_) => addTag(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NoAnnotationSelected extends StatelessWidget {
  const _NoAnnotationSelected();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.notes_outlined, size: 42),
        SizedBox(height: 10),
        Text('选择一条标注查看详情'),
      ],
    ),
  );
}

Color _annotationColor(BuildContext context, AnnotationColor color) {
  final scheme = Theme.of(context).colorScheme;
  return switch (color) {
    AnnotationColor.yellow => const Color(0xFFE6B84A),
    AnnotationColor.green => const Color(0xFF53A56B),
    AnnotationColor.blue => scheme.primary,
    AnnotationColor.pink => const Color(0xFFD76D8C),
  };
}

String _stripFragment(String href) => href.split('#').first;
