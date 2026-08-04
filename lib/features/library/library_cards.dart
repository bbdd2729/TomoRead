import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../domain/models/library_book.dart';
import '../../shared/widgets/book_cover.dart';

class ContinueReadingCard extends StatelessWidget {
  const ContinueReadingCard({
    super.key,
    required this.book,
    required this.onOpenReader,
  });

  final LibraryBook book;
  final VoidCallback onOpenReader;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      key: Key('continue-reading-${book.id}'),
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: SizedBox(
                width: 96,
                height: 132,
                child: BookCover(book: book),
              ),
            ),
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
                  const SizedBox(height: 4),
                  Text(
                    book.format.toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall,
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
}

class BookCard extends HookWidget {
  const BookCard({
    super.key,
    required this.book,
    required this.onTap,
    required this.onLongPress,
    required this.isSelected,
    required this.selectionMode,
    required this.isRemoving,
    required this.onDelete,
    required this.onToggleFavorite,
  });

  final LibraryBook book;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool isSelected;
  final bool selectionMode;
  final bool isRemoving;
  final VoidCallback onDelete;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final isHovered = useState(false);
    final colorScheme = Theme.of(context).colorScheme;
    final background = isSelected
        ? colorScheme.secondaryContainer
        : isHovered.value
        ? colorScheme.surfaceContainerLow
        : colorScheme.surface;
    final border = isSelected
        ? colorScheme.primary
        : colorScheme.outlineVariant;
    return MouseRegion(
      onEnter: (_) => isHovered.value = true,
      onExit: (_) => isHovered.value = false,
      child: AnimatedContainer(
        key: Key('book-${book.id}'),
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: isRemoving ? null : onTap,
            onLongPress: isRemoving ? null : onLongPress,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: Hero(
                            tag: bookCoverHeroTag(book),
                            child: BookCover(book: book),
                          ),
                        ),
                        if (selectionMode)
                          Positioned(
                            top: 4,
                            left: 4,
                            child: Checkbox(
                              value: isSelected,
                              onChanged: (_) => onTap(),
                            ),
                          ),
                        if (!selectionMode)
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Material(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainer,
                              shape: const CircleBorder(),
                              child: PopupMenuButton<String>(
                                tooltip: '更多操作',
                                enabled: !isRemoving,
                                onSelected: (action) => action == 'favorite'
                                    ? onToggleFavorite()
                                    : onDelete(),
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                    value: 'favorite',
                                    child: Text(
                                      book.isFavorite ? '取消收藏' : '收藏书籍',
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('删除书籍'),
                                  ),
                                ],
                                icon: isRemoving
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.more_vert),
                              ),
                            ),
                          ),
                      ],
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
        ),
      ),
    );
  }
}

class BookListItem extends StatelessWidget {
  const BookListItem({
    super.key,
    required this.book,
    required this.onTap,
    required this.onLongPress,
    required this.isSelected,
    required this.selectionMode,
    required this.isRemoving,
    required this.onDelete,
    required this.onToggleFavorite,
  });

  final LibraryBook book;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool isSelected;
  final bool selectionMode;
  final bool isRemoving;
  final VoidCallback onDelete;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) => Card(
    key: Key('book-list-${book.id}'),
    color: isSelected ? Theme.of(context).colorScheme.secondaryContainer : null,
    child: InkWell(
      onTap: isRemoving ? null : onTap,
      onLongPress: isRemoving ? null : onLongPress,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            if (selectionMode)
              Checkbox(value: isSelected, onChanged: (_) => onTap()),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 52,
                height: 76,
                child: Hero(
                  tag: bookCoverHeroTag(book),
                  child: BookCover(book: book),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    book.author.isEmpty ? '未知作者' : book.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        book.format.toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: LinearProgressIndicator(value: book.progress),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(book.progress * 100).round()}%',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (!selectionMode)
              PopupMenuButton<String>(
                tooltip: '更多操作',
                enabled: !isRemoving,
                onSelected: (action) =>
                    action == 'favorite' ? onToggleFavorite() : onDelete(),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'favorite',
                    child: Text(book.isFavorite ? '取消收藏' : '收藏书籍'),
                  ),
                  PopupMenuItem(value: 'delete', child: Text('删除书籍')),
                ],
                icon: isRemoving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.more_vert),
              ),
          ],
        ),
      ),
    ),
  );
}
