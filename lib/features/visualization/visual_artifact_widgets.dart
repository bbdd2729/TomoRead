import 'dart:convert';

import 'package:flutter/material.dart';

import '../../data/services/word_cloud_layout_service.dart';
import '../../domain/models/visual_artifact.dart';

class VisualArtifactView extends StatelessWidget {
  const VisualArtifactView({
    super.key,
    required this.artifact,
    this.onOpenCitation,
  });

  final VisualArtifact artifact;
  final ValueChanged<ArtifactCitation>? onOpenCitation;

  @override
  Widget build(BuildContext context) {
    try {
      final payload = jsonDecode(artifact.payloadJson) as Map<String, Object?>;
      return switch (artifact.kind) {
        VisualArtifactKind.wordCloud => WordCloudView(
          payload: WordCloudPayload.fromJson(payload),
        ),
        VisualArtifactKind.mindMap => MindMapView(
          payload: MindMapPayload.fromJson(payload),
          onOpenCitation: onOpenCitation,
        ),
      };
    } on Object catch (error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('无法读取可视化数据：$error'),
        ),
      );
    }
  }
}

class WordCloudView extends StatefulWidget {
  const WordCloudView({super.key, required this.payload});

  final WordCloudPayload payload;

  @override
  State<WordCloudView> createState() => _WordCloudViewState();
}

class _WordCloudViewState extends State<WordCloudView> {
  static const _width = 1200.0;
  static const _height = 760.0;
  static const _layoutService = WordCloudLayoutService();

  late Future<List<WordCloudLayoutEntry>> layout;

  @override
  void initState() {
    super.initState();
    layout = _createLayout();
  }

  @override
  void didUpdateWidget(covariant WordCloudView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.payload.layoutSeed != widget.payload.layoutSeed ||
        oldWidget.payload.contentHash != widget.payload.contentHash) {
      layout = _createLayout();
    }
  }

  Future<List<WordCloudLayoutEntry>> _createLayout() => _layoutService.layout(
    widget.payload,
    width: _width,
    height: _height,
  );

  @override
  Widget build(BuildContext context) {
    final payload = widget.payload;
    if (payload.terms.isEmpty) {
      return const Center(child: Text('词云没有有效词项。'));
    }
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: payload.terms
          .take(20)
          .map((term) => '${term.term} ${term.frequency} 次')
          .join('，'),
      child: FutureBuilder<List<WordCloudLayoutEntry>>(
        future: layout,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('词云布局失败：${snapshot.error}'));
          }
          final entries = snapshot.data;
          if (entries == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return InteractiveViewer(
            minScale: .35,
            maxScale: 4,
            boundaryMargin: const EdgeInsets.all(240),
            constrained: false,
            child: SizedBox(
              width: _width,
              height: _height,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: CustomPaint(
                  painter: _WordCloudPainter(payload, entries),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WordCloudPainter extends CustomPainter {
  _WordCloudPainter(this.payload, this.entries);

  final WordCloudPayload payload;
  final List<WordCloudLayoutEntry> entries;

  @override
  void paint(Canvas canvas, Size size) {
    for (final entry in entries) {
      final painter = TextPainter(
        text: TextSpan(
          text: entry.term,
          style: TextStyle(
            color: _wordColor(payload, entry.colorIndex),
            fontSize: entry.fontSize,
            fontWeight: entry.colorIndex < 12
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset(entry.x, entry.y));
    }
  }

  @override
  bool shouldRepaint(_WordCloudPainter oldDelegate) =>
      oldDelegate.payload.layoutSeed != payload.layoutSeed ||
      oldDelegate.payload.contentHash != payload.contentHash ||
      oldDelegate.payload.colorPalette != payload.colorPalette ||
      oldDelegate.entries != entries;
}

class MindMapView extends StatelessWidget {
  const MindMapView({
    super.key,
    required this.payload,
    this.onOpenCitation,
  });

  final MindMapPayload payload;
  final ValueChanged<ArtifactCitation>? onOpenCitation;

  @override
  Widget build(BuildContext context) {
    if (payload.nodes.isEmpty) {
      return const Center(child: Text('思维导图没有节点。'));
    }
    return InteractiveViewer(
      minScale: .4,
      maxScale: 3.5,
      boundaryMargin: const EdgeInsets.all(240),
      constrained: false,
      child: SizedBox(
        width: 980,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                payload.title,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              for (final node in payload.nodes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _MindMapNodeBranch(
                    node: node,
                    depth: 0,
                    onOpenCitation: onOpenCitation,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MindMapNodeBranch extends StatefulWidget {
  const _MindMapNodeBranch({
    required this.node,
    required this.depth,
    this.onOpenCitation,
  });

  final MindMapNode node;
  final int depth;
  final ValueChanged<ArtifactCitation>? onOpenCitation;

  @override
  State<_MindMapNodeBranch> createState() => _MindMapNodeBranchState();
}

class _MindMapNodeBranchState extends State<_MindMapNodeBranch> {
  var expanded = true;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final node = widget.node;
    final hasChildren = node.children.isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(left: widget.depth == 0 ? 0 : 34),
      child: DecoratedBox(
        decoration: widget.depth == 0
            ? const BoxDecoration()
            : BoxDecoration(
                border: Border(
                  left: BorderSide(color: colors.outlineVariant, width: 2),
                ),
              ),
        child: Padding(
          padding: EdgeInsets.only(left: widget.depth == 0 ? 0 : 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Material(
                color: widget.depth == 0
                    ? colors.primaryContainer
                    : colors.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: colors.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
                  child: Row(
                    children: [
                      if (hasChildren)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: expanded ? '折叠节点' : '展开节点',
                          onPressed: () => setState(() => expanded = !expanded),
                          icon: Icon(
                            expanded ? Icons.expand_more : Icons.chevron_right,
                          ),
                        )
                      else
                        const SizedBox(width: 40),
                      Expanded(
                        child: Text(
                          node.label,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      if (node.citations.isNotEmpty)
                        Wrap(
                          spacing: 5,
                          children: [
                            for (var index = 0;
                                index < node.citations.length;
                                index++)
                              Tooltip(
                                message: node.citations[index].quote,
                                child: ActionChip(
                                  visualDensity: VisualDensity.compact,
                                  label: Text('引用 ${index + 1}'),
                                  avatar: const Icon(
                                    Icons.menu_book_outlined,
                                    size: 16,
                                  ),
                                  onPressed: widget.onOpenCitation == null
                                      ? null
                                      : () => widget.onOpenCitation!(
                                          node.citations[index],
                                        ),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              if (expanded && hasChildren) ...[
                const SizedBox(height: 8),
                for (final child in node.children)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _MindMapNodeBranch(
                      key: ValueKey(child.id),
                      node: child,
                      depth: widget.depth + 1,
                      onOpenCitation: widget.onOpenCitation,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Color _wordColor(WordCloudPayload payload, int index) {
  final palette = payload.colorPalette.isEmpty
      ? defaultWordCloudPalette
      : payload.colorPalette;
  final encoded = palette[index % palette.length].replaceFirst('#', '');
  final value = int.tryParse(encoded, radix: 16);
  if (value == null) return const Color(0xff315b62);
  return Color(encoded.length <= 6 ? 0xff000000 | value : value);
}
