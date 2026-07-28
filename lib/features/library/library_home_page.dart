import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/services/book_import_service.dart';
import '../../domain/models/library_book.dart';
import '../../shared/widgets/page_header.dart';
import 'library_controller.dart';

class LibraryHomePage extends StatefulWidget {
  const LibraryHomePage({
    super.key,
    required this.controller,
    required this.onOpenReader,
  });

  final LibraryController controller;
  final ValueChanged<LibraryBook> onOpenReader;

  @override
  State<LibraryHomePage> createState() => _LibraryHomePageState();
}

class _LibraryHomePageState extends State<LibraryHomePage> {
  @override
  void initState() {
    super.initState();
    widget.controller.load();
  }

  Future<void> _importBooks() async {
    final results = await widget.controller.importFromPicker();
    if (!mounted || results.isEmpty) return;
    final imported = results
        .where((result) => result.status == BookImportStatus.imported)
        .length;
    final duplicates = results
        .where((result) => result.status == BookImportStatus.duplicate)
        .length;
    final failed = results
        .where((result) => result.status == BookImportStatus.failed)
        .length;
    final message = [
      if (imported > 0) '已导入 $imported 本',
      if (duplicates > 0) '$duplicates 本已存在',
      if (failed > 0) '$failed 本导入失败',
    ].join('，');
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            PageHeader(
              title: '书库',
              subtitle: '管理并继续阅读你的 EPUB 书籍。',
              actionLabel: controller.isImporting ? '正在导入' : '导入 EPUB',
              actionIcon: Icons.add,
              onAction: controller.isImporting ? null : _importBooks,
            ),
            const SizedBox(height: 24),
            if (controller.error != null) ...[
              _LibraryError(
                message: controller.error!,
                onRetry: controller.load,
              ),
              const SizedBox(height: 24),
            ],
            if (controller.isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 96),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (controller.books.isEmpty)
              _EmptyLibrary(
                onImport: controller.isImporting ? null : _importBooks,
              )
            else ...[
              _ContinueReadingCard(
                book: controller.books.first,
                onOpenReader: () => widget.onOpenReader(controller.books.first),
              ),
              const SizedBox(height: 28),
              Text('全部书籍', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 190,
                  mainAxisExtent: 270,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                ),
                itemCount: controller.books.length,
                itemBuilder: (context, index) => _BookCard(
                  book: controller.books[index],
                  onTap: () => widget.onOpenReader(controller.books[index]),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onImport});

  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 96),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_stories_outlined, size: 52),
          const SizedBox(height: 16),
          Text('还没有书籍', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('导入 EPUB 后会在这里显示。'),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.add),
            label: const Text('导入 EPUB'),
          ),
        ],
      ),
    ),
  );
}

class _LibraryError extends StatelessWidget {
  const _LibraryError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.error_outline),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
          IconButton(
            tooltip: '重试',
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    ),
  );
}

class _ContinueReadingCard extends StatelessWidget {
  const _ContinueReadingCard({required this.book, required this.onOpenReader});

  final LibraryBook book;
  final VoidCallback onOpenReader;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          SizedBox(width: 96, height: 132, child: _BookCover(book: book)),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('继续阅读', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Text(
                  book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  book.author.isEmpty ? '未知作者' : book.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(value: book.progress),
                const SizedBox(height: 8),
                Text(
                  '已读 ${(book.progress * 100).round()}%',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          IconButton.filledTonal(
            tooltip: '继续阅读',
            onPressed: onOpenReader,
            icon: const Icon(Icons.play_arrow),
          ),
        ],
      ),
    ),
  );
}

class _BookCard extends StatelessWidget {
  const _BookCard({required this.book, required this.onTap});

  final LibraryBook book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    key: Key('book-${book.id}'),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: _BookCover(book: book),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              book.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              book.author.isEmpty ? '未知作者' : book.author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: book.progress),
          ],
        ),
      ),
    ),
  );
}

class _BookCover extends StatelessWidget {
  const _BookCover({required this.book});

  final LibraryBook book;

  @override
  Widget build(BuildContext context) {
    final coverPath = book.coverPath;
    if (coverPath != null && File(coverPath).existsSync()) {
      return Image.file(
        File(coverPath),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallback(context),
      );
    }
    return _fallback(context);
  }

  Widget _fallback(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
    ),
    child: const Center(child: Icon(Icons.menu_book_outlined, size: 44)),
  );
}
