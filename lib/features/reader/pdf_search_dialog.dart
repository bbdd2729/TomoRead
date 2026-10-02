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
      title: const Text('البحث في ملف PDF'),
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
                hintText: 'أدخل الكلمات الرئيسية',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'مسح البحث',
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
              const Text('بعد إدخال الكلمات الرئيسية، يتم تمييز التطابقات في المستند.')
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
                        ? 'ابحث'
                        : 'البحث عن${searcher.searchingPageNumber} / ${searcher.totalPageCount}الصفحة',
                  ),
                ],
              )
            else if (searcher.matches.isEmpty)
              const Text('لم يتم العثور على تطابقات.')
            else
              Row(
                children: [
                  Text('المباراة $currentMatch / ${searcher.matches.length}'),
                  const Spacer(),
                  IconButton(
                    tooltip: 'المباراة السابقة',
                    onPressed: searcher.matches.isEmpty
                        ? null
                        : searcher.goToPrevMatch,
                    icon: const Icon(Icons.keyboard_arrow_up),
                  ),
                  IconButton(
                    tooltip: 'المباراة التالية',
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
          child: const Text('مغلق'),
        ),
      ],
    );
  }
}
