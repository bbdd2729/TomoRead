import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models/epub_manifest.dart';
import '../../domain/models/library_book.dart';
import '../../domain/models/reader_chapter.dart';

class ReaderSearchDialog extends HookConsumerWidget {
  const ReaderSearchDialog({
    super.key,
    required this.book,
    required this.manifest,
  });

  final LibraryBook book;
  final EpubManifest manifest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queryController = useTextEditingController();
    final results = useState(const <EpubSearchResult>[]);
    final searching = useState(false);
    final error = useState<Object?>(null);

    Future<void> search() async {
      final query = queryController.text.trim();
      if (query.isEmpty) return;
      searching.value = true;
      error.value = null;
      try {
        results.value = await ref
            .read(epubContentServiceProvider)
            .search(book: book, manifest: manifest, query: query);
      } catch (searchError) {
        error.value = searchError;
      } finally {
        searching.value = false;
      }
    }

    return AlertDialog(
      title: const Text('搜索书内内容'),
      content: SizedBox(
        width: 680,
        height: 520,
        child: Column(
          children: [
            TextField(
              controller: queryController,
              autofocus: true,
              onSubmitted: (_) => search(),
              decoration: InputDecoration(
                hintText: '输入关键词',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: '搜索',
                  onPressed: search,
                  icon: const Icon(Icons.search),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: searching.value
                  ? const Center(child: CircularProgressIndicator())
                  : error.value != null
                  ? Center(child: Text('搜索失败：${error.value}'))
                  : results.value.isEmpty
                  ? const Center(child: Text('输入关键词后开始搜索。'))
                  : ListView.separated(
                      itemCount: results.value.length,
                      separatorBuilder: (context, index) => const Divider(),
                      itemBuilder: (context, index) {
                        final result = results.value[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(result.chapterTitle),
                          subtitle: Text(result.excerpt, maxLines: 3),
                          onTap: () => Navigator.pop(context, result),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
