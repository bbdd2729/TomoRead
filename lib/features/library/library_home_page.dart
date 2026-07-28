import 'package:flutter/material.dart';

import '../../shared/widgets/page_header.dart';

class BookSummary {
  const BookSummary({
    required this.title,
    required this.author,
    required this.progress,
    required this.icon,
    required this.color,
  });

  final String title;
  final String author;
  final double progress;
  final IconData icon;
  final Color color;
}

class LibraryHomePage extends StatelessWidget {
  const LibraryHomePage({
    super.key,
    required this.onOpenReader,
    required this.onAction,
  });

  final ValueChanged<BookSummary> onOpenReader;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        PageHeader(
          title: '书库',
          subtitle: '管理并继续阅读你的书籍。',
          actionLabel: '导入书籍',
          actionIcon: Icons.add,
          onAction: () => onAction('导入书籍功能将在下一阶段接入。'),
        ),
        const SizedBox(height: 24),
        _ContinueReadingCard(
          onOpenReader: () => onOpenReader(sampleBooks.first),
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            Text('全部书籍', style: Theme.of(context).textTheme.headlineSmall),
            const Spacer(),
            IconButton(
              tooltip: '列表视图',
              onPressed: () => onAction('列表视图将在下一阶段接入。'),
              icon: const Icon(Icons.view_list_outlined),
            ),
            IconButton(
              tooltip: '排序',
              onPressed: () => onAction('排序功能将在下一阶段接入。'),
              icon: const Icon(Icons.sort),
            ),
          ],
        ),
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
          itemCount: sampleBooks.length,
          itemBuilder: (context, index) => _BookCard(
            book: sampleBooks[index],
            onTap: () => onOpenReader(sampleBooks[index]),
          ),
        ),
      ],
    );
  }
}

class _ContinueReadingCard extends StatelessWidget {
  const _ContinueReadingCard({required this.onOpenReader});

  final VoidCallback onOpenReader;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('继续阅读', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Text('阅读的技艺', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              const Text('第二章  阅读的层次'),
              const SizedBox(height: 16),
              const LinearProgressIndicator(value: .38),
              const SizedBox(height: 8),
              Text('已读 38%', style: Theme.of(context).textTheme.bodySmall),
            ],
          );
          return Padding(
            padding: const EdgeInsets.all(20),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(
                        height: 120,
                        child: _BookCover(
                          icon: Icons.auto_stories,
                          color: Colors.indigo,
                        ),
                      ),
                      const SizedBox(height: 16),
                      details,
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: onOpenReader,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('继续阅读'),
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      const SizedBox(
                        width: 96,
                        height: 132,
                        child: _BookCover(
                          icon: Icons.auto_stories,
                          color: Colors.indigo,
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(child: details),
                      const SizedBox(width: 16),
                      IconButton.filledTonal(
                        tooltip: '继续阅读',
                        onPressed: onOpenReader,
                        icon: const Icon(Icons.play_arrow),
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }
}

class _BookCard extends StatelessWidget {
  const _BookCard({required this.book, required this.onTap});

  final BookSummary book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: Key('book-${book.title}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _BookCover(icon: book.icon, color: book.color),
              ),
              const SizedBox(height: 12),
              Text(
                book.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 2),
              Text(
                book.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
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
      ),
    );
  }
}

class _BookCover extends StatelessWidget {
  const _BookCover({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: color.withValues(alpha: .16)),
      child: Center(child: Icon(icon, size: 44, color: color)),
    );
  }
}

const sampleBooks = [
  BookSummary(
    title: '阅读的技艺',
    author: '莫提默·J. 艾德勒',
    progress: .38,
    icon: Icons.auto_stories,
    color: Colors.indigo,
  ),
  BookSummary(
    title: '思考，快与慢',
    author: '丹尼尔·卡尼曼',
    progress: .16,
    icon: Icons.psychology,
    color: Colors.deepOrange,
  ),
  BookSummary(
    title: '月亮与六便士',
    author: '毛姆',
    progress: .72,
    icon: Icons.nightlight_round,
    color: Colors.teal,
  ),
  BookSummary(
    title: '人类简史',
    author: '尤瓦尔·赫拉利',
    progress: .05,
    icon: Icons.public,
    color: Colors.brown,
  ),
  BookSummary(
    title: '置身事内',
    author: '兰小欢',
    progress: .48,
    icon: Icons.account_balance,
    color: Colors.blue,
  ),
  BookSummary(
    title: '纳瓦尔宝典',
    author: '埃里克·乔根森',
    progress: .92,
    icon: Icons.diamond_outlined,
    color: Colors.purple,
  ),
];
