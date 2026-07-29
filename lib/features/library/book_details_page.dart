import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../domain/models/library_book.dart';
import '../../shared/widgets/book_cover.dart';

class BookDetailsPage extends HookWidget {
  const BookDetailsPage({
    super.key,
    required this.book,
    required this.onOpenReader,
  });

  final LibraryBook book;
  final ValueChanged<LibraryBook> onOpenReader;

  @override
  Widget build(BuildContext context) {
    final isDescriptionExpanded = useState(false);
    final hasProgress = book.progress > 0;
    final author = book.author.isEmpty ? '未知作者' : book.author;
    final description = book.description?.trim();
    final readLabel = hasProgress ? '继续阅读' : '开始阅读';

    return Scaffold(
      appBar: AppBar(title: const Text('书籍详情')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 760;
          final cover = SizedBox(
            width: isWide ? 232 : 184,
            height: isWide ? 340 : 270,
            child: Hero(
              tag: bookCoverHeroTag(book),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: BookCover(
                  key: const Key('book-detail-cover'),
                  book: book,
                ),
              ),
            ),
          );
          final details = _BookDetailsContent(
            book: book,
            author: author,
            description: description,
            isDescriptionExpanded: isDescriptionExpanded.value,
            onDescriptionExpansionChanged: () =>
                isDescriptionExpanded.value = !isDescriptionExpanded.value,
            readLabel: readLabel,
            onOpenReader: () => onOpenReader(book),
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

class _BookDetailsContent extends StatelessWidget {
  const _BookDetailsContent({
    required this.book,
    required this.author,
    required this.description,
    required this.isDescriptionExpanded,
    required this.onDescriptionExpansionChanged,
    required this.readLabel,
    required this.onOpenReader,
  });

  final LibraryBook book;
  final String author;
  final String? description;
  final bool isDescriptionExpanded;
  final VoidCallback onDescriptionExpansionChanged;
  final String readLabel;
  final VoidCallback onOpenReader;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final descriptionText = description ?? '';
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
          ],
        ),
        const SizedBox(height: 28),
        Text('简介', style: theme.textTheme.titleLarge),
        const SizedBox(height: 10),
        if (descriptionText.isEmpty)
          Text('暂无可用简介。', style: theme.textTheme.bodyMedium)
        else ...[
          Text(
            descriptionText,
            maxLines: isDescriptionExpanded ? null : 6,
            overflow: isDescriptionExpanded ? null : TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge,
          ),
          if (descriptionText.length > 300)
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
          label: Text(readLabel),
        ),
      ],
    );
  }
}
