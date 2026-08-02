import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';

class ContentSearchDialog extends HookConsumerWidget {
  const ContentSearchDialog({
    super.key,
    required this.bookId,
    required this.maxChapterIndex,
  });

  final String bookId;
  final int? maxChapterIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = useState('');
    final request = (
      bookId: bookId,
      query: query.value,
      maxChapterIndex: maxChapterIndex,
      limit: 50,
    );
    final results = ref.watch(contentSearchProvider(request));
    return AlertDialog(
      title: const Text('搜索本地正文索引'),
      content: SizedBox(
        width: 620,
        height: 520,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '输入关键词或短语',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => query.value = value,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: query.value.trim().isEmpty
                  ? const Center(child: Text('索引只包含解析后的可信纯文本。'))
                  : results.when(
                      loading: () => const Center(
                        child: CircularProgressIndicator(),
                      ),
                      error: (error, _) => Center(child: Text('搜索失败：$error')),
                      data: (items) => items.isEmpty
                          ? const Center(child: Text('没有找到匹配内容。'))
                          : ListView.builder(
                              itemCount: items.length,
                              itemBuilder: (context, index) {
                                final result = items[index];
                                return ListTile(
                                  title: Text(result.chunk.chapterTitle),
                                  subtitle: Text(
                                    result.excerpt,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () => Navigator.pop(
                                    context,
                                    result.chunk,
                                  ),
                                );
                              },
                            ),
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
