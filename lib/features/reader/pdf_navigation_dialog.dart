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
    final expandedKeys = useState<Set<String>>(const <String>{});

    useEffect(() {
      final automaticallyExpanded = _expandedOutlineKeysForCurrentPage(
        outline,
        currentPage,
      );
      if (!automaticallyExpanded.every(expandedKeys.value.contains)) {
        expandedKeys.value = {...expandedKeys.value, ...automaticallyExpanded};
      }
      return null;
    }, [outline, currentPage]);

    void toggleNode(String nodeKey) {
      final next = {...expandedKeys.value};
      if (!next.add(nodeKey)) next.remove(nodeKey);
      expandedKeys.value = next;
    }

    return AlertDialog(
      title: const Text('التنقل في ملفات PDF'),
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
                  label: Text('الكتالوج'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.grid_view_outlined),
                  label: Text('أعرض الأظافر'),
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
                  ? Center(child: Text('تعذر قراءة دليل PDF: $outlineError'))
                  : outline.isEmpty
                  ? const Center(child: Text('لا يحتوي ملف PDF هذا على كتالوج مدمج.'))
                  : ListView(
                      children: [
                        for (var index = 0; index < outline.length; index++)
                          _PdfOutlineEntry(
                            node: outline[index],
                            nodeKey: 'outline/$index',
                            currentPage: currentPage,
                            expandedKeys: expandedKeys.value,
                            onToggle: toggleNode,
                          ),
                      ],
                    ),
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

Set<String> _expandedOutlineKeysForCurrentPage(
  List<PdfOutlineNode> nodes,
  int currentPage, {
  String parentKey = 'outline',
}) {
  final expanded = <String>{};

  bool visit(List<PdfOutlineNode> entries, String ancestorKey) {
    var containsCurrentPage = false;
    for (var index = 0; index < entries.length; index++) {
      final node = entries[index];
      final nodeKey = '$ancestorKey/$index';
      final childContainsCurrentPage = visit(node.children, nodeKey);
      final nodeContainsCurrentPage =
          node.dest?.pageNumber == currentPage || childContainsCurrentPage;
      if (nodeContainsCurrentPage && node.children.isNotEmpty) {
        expanded.add(nodeKey);
      }
      if (nodeContainsCurrentPage) containsCurrentPage = true;
    }
    return containsCurrentPage;
  }

  visit(nodes, parentKey);
  return expanded;
}

class _PdfOutlineEntry extends StatelessWidget {
  const _PdfOutlineEntry({
    required this.node,
    required this.nodeKey,
    required this.currentPage,
    required this.expandedKeys,
    required this.onToggle,
    this.depth = 0,
  });

  final PdfOutlineNode node;
  final String nodeKey;
  final int currentPage;
  final Set<String> expandedKeys;
  final ValueChanged<String> onToggle;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final hasChildren = node.children.isNotEmpty;
    final expanded = expandedKeys.contains(nodeKey);
    final destination = node.dest;

    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsetsDirectional.only(
            start: 8 + depth * 20.0,
            end: 12,
          ),
          leading: hasChildren
              ? IconButton(
                  key: Key('pdf-outline-toggle-$nodeKey'),
                  tooltip: expanded ? 'طي المقطع' : 'توسيع المقطع',
                  onPressed: () => onToggle(nodeKey),
                  icon: Icon(
                    expanded ? Icons.expand_more : Icons.chevron_right,
                  ),
                )
              : const SizedBox(width: 48, child: Icon(Icons.article_outlined)),
          selected: destination?.pageNumber == currentPage,
          title: Text(
            node.title.isEmpty ? 'فصل بدون عنوان' : node.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: destination == null
              ? null
              : Text('الفقرتان 102${destination.pageNumber}الصفحة'),
          enabled: destination != null,
          onTap: destination == null
              ? null
              : () => Navigator.pop(context, destination),
        ),
        if (hasChildren && expanded)
          for (var index = 0; index < node.children.length; index++)
            _PdfOutlineEntry(
              node: node.children[index],
              nodeKey: '$nodeKey/$index',
              currentPage: currentPage,
              expandedKeys: expandedKeys,
              onToggle: onToggle,
              depth: depth + 1,
            ),
      ],
    );
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
                  Text('الصفحة $pageNumber'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
