import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:pdfrx/pdfrx.dart';

class PdfNavigationDialog extends HookWidget {
  const PdfNavigationDialog({
    super.key,
    required this.document,
    required this.outline,
    required this.isOutlineLoading,
    required this.outlineError,
    required this.currentPage,
  });

  final PdfDocument document;
  final List<PdfOutlineNode> outline;
  final bool isOutlineLoading;
  final Object? outlineError;
  final int currentPage;

  @override
  Widget build(BuildContext context) {
    final showThumbnails = useState(false);
    final outlineEntries = _flattenOutline(outline);

    return AlertDialog(
      title: const Text('PDF 导航'),
      content: SizedBox(
        width: 760,
        height: 560,
        child: Column(
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.format_list_bulleted),
                  label: Text('目录'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.grid_view_outlined),
                  label: Text('缩略图'),
                ),
              ],
              selected: {showThumbnails.value},
              onSelectionChanged: (selection) {
                showThumbnails.value = selection.first;
              },
            ),
            const SizedBox(height: 16),
            Expanded(
              child: showThumbnails.value
                  ? _PdfThumbnails(document: document, currentPage: currentPage)
                  : isOutlineLoading
                  ? const Center(child: CircularProgressIndicator())
                  : outlineError != null
                  ? Center(child: Text('无法读取 PDF 目录：$outlineError'))
                  : outlineEntries.isEmpty
                  ? const Center(child: Text('这个 PDF 没有内置目录。'))
                  : ListView.builder(
                      itemCount: outlineEntries.length,
                      itemBuilder: (context, index) {
                        final entry = outlineEntries[index];
                        final destination = entry.node.dest;
                        return ListTile(
                          contentPadding: EdgeInsets.only(
                            left: 12.0 + entry.depth * 20,
                            right: 12,
                          ),
                          leading: Icon(
                            entry.node.children.isEmpty
                                ? Icons.article_outlined
                                : Icons.folder_outlined,
                          ),
                          title: Text(
                            entry.node.title.isEmpty
                                ? '未命名章节'
                                : entry.node.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: destination == null
                              ? null
                              : Text('第 ${destination.pageNumber} 页'),
                          enabled: destination != null,
                          onTap: destination == null
                              ? null
                              : () => Navigator.pop(context, destination),
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

  List<({PdfOutlineNode node, int depth})> _flattenOutline(
    List<PdfOutlineNode> nodes, {
    int depth = 0,
  }) {
    return [
      for (final node in nodes) ...[
        (node: node, depth: depth),
        ..._flattenOutline(node.children, depth: depth + 1),
      ],
    ];
  }
}

class _PdfThumbnails extends StatelessWidget {
  const _PdfThumbnails({required this.document, required this.currentPage});

  final PdfDocument document;
  final int currentPage;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 156,
        mainAxisExtent: 208,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemCount: document.pages.length,
      itemBuilder: (context, index) {
        final pageNumber = index + 1;
        final selected = pageNumber == currentPage;
        return Material(
          clipBehavior: Clip.antiAlias,
          color: selected
              ? Theme.of(context).colorScheme.secondaryContainer
              : Theme.of(context).colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              width: selected ? 2 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => Navigator.pop(
              context,
              PdfDest(pageNumber, PdfDestCommand.fit, null),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Column(
                children: [
                  Expanded(
                    child: PdfPageView(
                      document: document,
                      pageNumber: pageNumber,
                      maximumDpi: 72,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('第 $pageNumber 页'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
