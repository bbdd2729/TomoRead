import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:pdfrx/pdfrx.dart';

class PdfSearchDialog extends HookWidget {
  const PdfSearchDialog({super.key, required this.searcher});

  final PdfTextSearcher searcher;

  @override
  Widget build(BuildContext context) {
    final queryController = useTextEditingController(
      text: searcher.pattern is String ? searcher.pattern! as String : '',
    );
    useListenable(searcher);

    useEffect(() {
      return searcher.resetTextSearch;
    }, [searcher]);

    final query = queryController.text.trim();
    final currentMatch = searcher.currentIndex == null
        ? 0
        : searcher.currentIndex! + 1;

    void search() {
      searcher.startTextSearch(queryController.text.trim());
    }

    return AlertDialog(
      title: const Text('搜索 PDF'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: queryController,
              autofocus: true,
              onChanged: (_) => search(),
              onSubmitted: (_) => search(),
              decoration: InputDecoration(
                hintText: '输入关键词',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: '清除搜索',
                  onPressed: query.isEmpty
                      ? null
                      : () {
                          queryController.clear();
                          searcher.resetTextSearch();
                        },
                  icon: const Icon(Icons.clear),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (query.isEmpty)
              const Text('输入关键词后，匹配内容会在文档中高亮显示。')
            else if (searcher.isSearching)
              Row(
                children: [
                  const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    searcher.searchingPageNumber == null ||
                            searcher.totalPageCount == null
                        ? '正在搜索...'
                        : '正在搜索第 ${searcher.searchingPageNumber} / ${searcher.totalPageCount} 页',
                  ),
                ],
              )
            else if (searcher.matches.isEmpty)
              const Text('未找到匹配内容。')
            else
              Row(
                children: [
                  Text('第 $currentMatch / ${searcher.matches.length} 个匹配'),
                  const Spacer(),
                  IconButton(
                    tooltip: '上一个匹配',
                    onPressed: searcher.matches.isEmpty
                        ? null
                        : searcher.goToPrevMatch,
                    icon: const Icon(Icons.keyboard_arrow_up),
                  ),
                  IconButton(
                    tooltip: '下一个匹配',
                    onPressed: searcher.matches.isEmpty
                        ? null
                        : searcher.goToNextMatch,
                    icon: const Icon(Icons.keyboard_arrow_down),
                  ),
                ],
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
