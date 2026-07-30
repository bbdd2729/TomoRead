import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models/library_book.dart';
import '../../shared/widgets/book_cover.dart';

class BookDetailsPage extends HookConsumerWidget {
  const BookDetailsPage({
    super.key,
    required this.book,
    required this.onOpenReader,
  });

  final LibraryBook book;
  final ValueChanged<LibraryBook> onOpenReader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentBook = useState(book);
    final isEditing = useState(false);
    final isSaving = useState(false);
    final isDescriptionExpanded = useState(false);
    final titleController = useTextEditingController();
    final authorController = useTextEditingController();
    final descriptionController = useTextEditingController();
    final categoryController = useTextEditingController();
    final tagsController = useTextEditingController();
    final displayedBook = currentBook.value;

    void beginEditing() {
      titleController.text = displayedBook.title;
      authorController.text = displayedBook.author;
      descriptionController.text = displayedBook.description ?? '';
      categoryController.text = displayedBook.category ?? '';
      tagsController.text = displayedBook.tags.join(', ');
      isEditing.value = true;
    }

    Future<void> saveMetadata() async {
      if (isSaving.value) return;
      final title = titleController.text.trim();
      if (title.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('书名不能为空。')));
        return;
      }
      final description = descriptionController.text.trim();
      final category = categoryController.text.trim();
      final tags = _parseTags(tagsController.text);
      isSaving.value = true;
      try {
        await ref
            .read(bookRepositoryProvider)
            .updateMetadata(
              bookId: displayedBook.id,
              title: title,
              author: authorController.text.trim(),
              description: description.isEmpty ? null : description,
              category: category.isEmpty ? null : category,
              tags: tags,
            );
        final updatedBook = displayedBook.copyWith(
          title: title,
          author: authorController.text.trim(),
          description: description,
          category: category,
          tags: tags,
          clearDescription: description.isEmpty,
          clearCategory: category.isEmpty,
        );
        currentBook.value = updatedBook;
        ref.invalidate(libraryBooksProvider);
        ref.invalidate(readerBookProvider(displayedBook.id));
        isEditing.value = false;
      } catch (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存书籍信息失败：$error')));
      } finally {
        if (context.mounted) isSaving.value = false;
      }
    }

    Future<void> toggleFavorite() async {
      final nextValue = !displayedBook.isFavorite;
      try {
        await ref
            .read(bookRepositoryProvider)
            .setFavorite(displayedBook.id, nextValue);
        currentBook.value = displayedBook.copyWith(isFavorite: nextValue);
        ref.invalidate(libraryBooksProvider);
        ref.invalidate(readerBookProvider(displayedBook.id));
      } catch (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('更新收藏状态失败：$error')));
      }
    }

    Future<void> resetProgress() async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('重置阅读进度'),
          content: const Text('将从第一章重新开始阅读。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('重置'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await ref
          .read(bookRepositoryProvider)
          .resetReadingPosition(displayedBook.id);
      currentBook.value = displayedBook.copyWith(
        progress: 0,
        chapterIndex: 0,
        clearLocator: true,
      );
      ref.invalidate(libraryBooksProvider);
      ref.invalidate(readerBookProvider(displayedBook.id));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing.value ? '编辑书籍' : '书籍详情'),
        actions: [
          if (isEditing.value) ...[
            IconButton(
              tooltip: '取消编辑',
              onPressed: isSaving.value ? null : () => isEditing.value = false,
              icon: const Icon(Icons.close),
            ),
            IconButton(
              key: const Key('book-detail-save'),
              tooltip: '保存',
              onPressed: isSaving.value ? null : saveMetadata,
              icon: isSaving.value
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
            ),
          ] else ...[
            IconButton(
              key: const Key('book-detail-favorite'),
              tooltip: displayedBook.isFavorite ? '取消收藏' : '收藏书籍',
              onPressed: toggleFavorite,
              icon: Icon(
                displayedBook.isFavorite
                    ? Icons.favorite
                    : Icons.favorite_border,
              ),
            ),
            if (displayedBook.progress > 0)
              PopupMenuButton<_BookDetailAction>(
                tooltip: '更多操作',
                onSelected: (action) {
                  if (action == _BookDetailAction.resetProgress) {
                    resetProgress();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _BookDetailAction.resetProgress,
                    child: ListTile(
                      leading: Icon(Icons.restart_alt),
                      title: Text('重置阅读进度'),
                    ),
                  ),
                ],
              ),
            IconButton(
              key: const Key('book-detail-edit'),
              tooltip: '编辑书籍信息',
              onPressed: beginEditing,
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 760;
          final cover = SizedBox(
            width: isWide ? 232 : 184,
            height: isWide ? 340 : 270,
            child: Hero(
              tag: bookCoverHeroTag(displayedBook),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: BookCover(
                  key: const Key('book-detail-cover'),
                  book: displayedBook,
                ),
              ),
            ),
          );
          final details = isEditing.value
              ? _BookDetailsEditForm(
                  titleController: titleController,
                  authorController: authorController,
                  descriptionController: descriptionController,
                  categoryController: categoryController,
                  tagsController: tagsController,
                  isSaving: isSaving.value,
                  onSave: saveMetadata,
                )
              : _BookDetailsContent(
                  book: displayedBook,
                  isDescriptionExpanded: isDescriptionExpanded.value,
                  onDescriptionExpansionChanged: () =>
                      isDescriptionExpanded.value =
                          !isDescriptionExpanded.value,
                  onOpenReader: () => onOpenReader(displayedBook),
                );

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              isWide ? 48 : 24,
              32,
              isWide ? 48 : 24,
              48,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          cover,
                          const SizedBox(width: 48),
                          Expanded(child: details),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(child: cover),
                          const SizedBox(height: 28),
                          details,
                        ],
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}

enum _BookDetailAction { resetProgress }

class _BookDetailsContent extends StatelessWidget {
  const _BookDetailsContent({
    required this.book,
    required this.isDescriptionExpanded,
    required this.onDescriptionExpansionChanged,
    required this.onOpenReader,
  });

  final LibraryBook book;
  final bool isDescriptionExpanded;
  final VoidCallback onDescriptionExpansionChanged;
  final VoidCallback onOpenReader;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = book.description?.trim() ?? '';
    final author = book.author.isEmpty ? '未知作者' : book.author;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(book.title, style: theme.textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(author, style: theme.textTheme.titleMedium),
        const SizedBox(height: 24),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(
              avatar: Icon(
                book.format == 'pdf'
                    ? Icons.picture_as_pdf_outlined
                    : Icons.menu_book_outlined,
                size: 18,
              ),
              label: Text(book.format.toUpperCase()),
            ),
            Chip(
              avatar: const Icon(Icons.format_list_numbered, size: 18),
              label: Text('${book.chapterCount} 章'),
            ),
            if (book.category?.isNotEmpty ?? false)
              Chip(
                avatar: const Icon(Icons.folder_outlined, size: 18),
                label: Text(book.category!),
              ),
            for (final tag in book.tags)
              Chip(
                avatar: const Icon(Icons.sell_outlined, size: 18),
                label: Text(tag),
              ),
          ],
        ),
        const SizedBox(height: 28),
        Text('简介', style: theme.textTheme.titleLarge),
        const SizedBox(height: 10),
        if (description.isEmpty)
          Text('暂无可用简介。', style: theme.textTheme.bodyMedium)
        else ...[
          Text(
            description,
            maxLines: isDescriptionExpanded ? null : 6,
            overflow: isDescriptionExpanded ? null : TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge,
          ),
          if (description.length > 300)
            TextButton(
              onPressed: onDescriptionExpansionChanged,
              child: Text(isDescriptionExpanded ? '收起' : '展开全部'),
            ),
        ],
        const SizedBox(height: 28),
        Text('阅读进度', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        LinearProgressIndicator(value: book.progress),
        const SizedBox(height: 8),
        Text(
          '已读 ${(book.progress * 100).round()}%',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 32),
        FilledButton.icon(
          key: const Key('book-detail-read'),
          onPressed: onOpenReader,
          icon: Icon(
            book.progress > 0 ? Icons.play_arrow : Icons.menu_book_outlined,
          ),
          label: Text(book.progress > 0 ? '继续阅读' : '开始阅读'),
        ),
      ],
    );
  }
}

class _BookDetailsEditForm extends StatelessWidget {
  const _BookDetailsEditForm({
    required this.titleController,
    required this.authorController,
    required this.descriptionController,
    required this.categoryController,
    required this.tagsController,
    required this.isSaving,
    required this.onSave,
  });

  final TextEditingController titleController;
  final TextEditingController authorController;
  final TextEditingController descriptionController;
  final TextEditingController categoryController;
  final TextEditingController tagsController;
  final bool isSaving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        key: const Key('book-detail-title-input'),
        controller: titleController,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: '书名',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: authorController,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: '作者',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: categoryController,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: '分类',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: tagsController,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: '标签',
          hintText: '多个标签用逗号分隔',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: descriptionController,
        minLines: 5,
        maxLines: 10,
        decoration: const InputDecoration(
          labelText: '简介',
          alignLabelWithHint: true,
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 24),
      FilledButton.icon(
        onPressed: isSaving ? null : onSave,
        icon: const Icon(Icons.save_outlined),
        label: const Text('保存书籍信息'),
      ),
    ],
  );
}

List<String> _parseTags(String source) {
  final seen = <String>{};
  return source
      .split(RegExp('[,，]'))
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty && seen.add(tag.toLowerCase()))
      .toList();
}
