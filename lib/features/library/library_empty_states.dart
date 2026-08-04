import 'package:flutter/material.dart';

class NoMatchingBooks extends StatelessWidget {
  const NoMatchingBooks();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 72),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.manage_search_outlined, size: 44),
          const SizedBox(height: 12),
          Text('没有匹配的书籍', style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    ),
  );
}

class EmptyLibrary extends StatelessWidget {
  const EmptyLibrary({required this.onImport});

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
          const Text('导入 EPUB 或 PDF 后会在这里显示。'),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.add),
            label: const Text('导入书籍'),
          ),
        ],
      ),
    ),
  );
}

class LibraryFailure extends StatelessWidget {
  const LibraryFailure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: FilledButton.icon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh),
      label: Text(message),
    ),
  );
}
