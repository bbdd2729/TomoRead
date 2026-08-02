import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../data/services/mind_map_generation_service.dart';
import '../../data/services/visual_artifact_export_service.dart';
import '../../domain/models/visual_artifact.dart';
import 'visual_artifact_widgets.dart';
import 'visualization_controller.dart';

class ReaderVisualizationDialog extends HookConsumerWidget {
  const ReaderVisualizationDialog({
    super.key,
    required this.bookId,
    required this.bookTitle,
    required this.currentChapterIndex,
    this.onOpenCitation,
  });

  final String bookId;
  final String bookTitle;
  final int currentChapterIndex;
  final ValueChanged<ArtifactCitation>? onOpenCitation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(visualizationControllerProvider(bookId));
    final artifactsState = ref.watch(visualArtifactsForBookProvider(bookId));
    final selectedScope = useState(VisualArtifactScope.currentChapter);
    final selectedArtifact = useState<VisualArtifact?>(null);
    final busyKind = useState<VisualArtifactKind?>(null);
    final cancelling = useState(false);
    final errorMessage = useState<String?>(null);
    final rawResponse = useState<String?>(null);

    final storedArtifacts = artifactsState.value ?? const <VisualArtifact>[];
    final artifactOptions = <VisualArtifact>[
      if (selectedArtifact.value != null) selectedArtifact.value!,
      for (final artifact in storedArtifacts)
        if (artifact.id != selectedArtifact.value?.id) artifact,
    ];
    final activeArtifact = selectedArtifact.value ??
        (storedArtifacts.isEmpty ? null : storedArtifacts.first);

    Future<void> chooseScope(VisualArtifactScope scope) async {
      if (scope == selectedScope.value) return;
      if (scope == VisualArtifactScope.wholeBook) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('使用整本书内容？'),
            content: const Text(
              '整书范围可能包含尚未阅读的章节。生成词云时仅在本地处理；'
              '生成思维导图时，范围内的受控正文片段会发送给当前 AI 服务商。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认整书范围'),
              ),
            ],
          ),
        );
        if (confirmed != true || !context.mounted) return;
      }
      selectedScope.value = scope;
    }

    Future<void> generate(VisualArtifactKind kind) async {
      if (busyKind.value != null) return;
      busyKind.value = kind;
      cancelling.value = false;
      errorMessage.value = null;
      rawResponse.value = null;
      try {
        final artifact = switch (kind) {
          VisualArtifactKind.wordCloud => (await controller.generateWordCloud(
            bookId: bookId,
            bookTitle: bookTitle,
            scope: selectedScope.value,
            currentChapterIndex: currentChapterIndex,
          ))
              .artifact,
          VisualArtifactKind.mindMap => (await controller.generateMindMap(
            bookId: bookId,
            bookTitle: bookTitle,
            scope: selectedScope.value,
            currentChapterIndex: currentChapterIndex,
          ))
              .artifact,
        };
        if (context.mounted) selectedArtifact.value = artifact;
      } on MindMapValidationException catch (error) {
        if (context.mounted) {
          errorMessage.value = error.message;
          rawResponse.value = error.rawResponse;
        }
      } on MindMapGenerationCancelledException {
        if (context.mounted) errorMessage.value = '思维导图生成已取消。';
      } on Object catch (error) {
        if (context.mounted) errorMessage.value = error.toString();
      } finally {
        if (context.mounted) {
          busyKind.value = null;
          cancelling.value = false;
        }
      }
    }

    Future<void> cancelGeneration() async {
      if (busyKind.value == null || cancelling.value) return;
      cancelling.value = true;
      await controller.cancel();
    }

    Future<void> reseed() async {
      final artifact = activeArtifact;
      if (artifact == null || artifact.kind != VisualArtifactKind.wordCloud) {
        return;
      }
      try {
        final reseeded = await controller.reseedWordCloud(artifact);
        if (context.mounted) selectedArtifact.value = reseeded;
      } on Object catch (error) {
        if (context.mounted) errorMessage.value = error.toString();
      }
    }

    Future<void> deleteArtifact() async {
      final artifact = activeArtifact;
      if (artifact == null) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除可视化记录？'),
          content: Text('“${artifact.title}”将从本地派生数据中删除，不会影响原书。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      try {
        await controller.delete(artifact);
        if (context.mounted) selectedArtifact.value = null;
      } on Object catch (error) {
        if (context.mounted) errorMessage.value = '删除失败：$error';
      }
    }

    Future<void> exportArtifact() async {
      final artifact = activeArtifact;
      if (artifact == null) return;
      final formats = <VisualArtifactExportFormat>[
        VisualArtifactExportFormat.json,
        if (artifact.kind == VisualArtifactKind.mindMap)
          VisualArtifactExportFormat.markdown,
        VisualArtifactExportFormat.svg,
        VisualArtifactExportFormat.png,
      ];
      final format = await showDialog<VisualArtifactExportFormat>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('选择导出格式'),
          children: [
            for (final format in formats)
              ListTile(
                leading: Icon(switch (format) {
                  VisualArtifactExportFormat.json => Icons.data_object,
                  VisualArtifactExportFormat.markdown => Icons.notes,
                  VisualArtifactExportFormat.svg => Icons.draw_outlined,
                  VisualArtifactExportFormat.png => Icons.image_outlined,
                }),
                title: Text(format.label),
                onTap: () => Navigator.pop(context, format),
              ),
          ],
        ),
      );
      if (format == null || !context.mounted) return;
      try {
        final path = await controller.export(artifact, format);
        if (path != null && context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('已导出到 $path')));
        }
      } on Object catch (error) {
        if (context.mounted) errorMessage.value = '导出失败：$error';
      }
    }

    final media = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: min<double>(media.width - 24, 1120.0),
        height: min<double>(media.height - 24, 840.0),
        child: Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                child: Row(
                  children: [
                    const Icon(Icons.account_tree_outlined),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '词云与思维导图',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            bookTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<VisualArtifactScope>(
                      segments: [
                        for (final scope in VisualArtifactScope.values)
                          ButtonSegment(
                            value: scope,
                            label: Text(scope.label),
                          ),
                      ],
                      selected: {selectedScope.value},
                      onSelectionChanged: busyKind.value == null
                          ? (values) => unawaited(chooseScope(values.first))
                          : null,
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: busyKind.value == null
                        ? () => unawaited(
                            generate(VisualArtifactKind.wordCloud),
                          )
                        : null,
                    icon: const Icon(Icons.bubble_chart_outlined),
                    label: const Text('本地词云'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: busyKind.value == null
                        ? () => unawaited(
                            generate(VisualArtifactKind.mindMap),
                          )
                        : null,
                    icon: const Icon(Icons.account_tree_outlined),
                    label: const Text('AI 思维导图'),
                  ),
                  if (busyKind.value != null)
                    OutlinedButton.icon(
                      onPressed: cancelling.value
                          ? null
                          : () => unawaited(cancelGeneration()),
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: Text(cancelling.value ? '正在取消' : '取消'),
                    ),
                ],
              ),
            ),
            if (busyKind.value != null)
              LinearProgressIndicator(
                semanticsLabel: busyKind.value == VisualArtifactKind.wordCloud
                    ? '正在本地生成词云'
                    : '正在生成 AI 思维导图',
              ),
            if (errorMessage.value != null)
              _RecoverableError(
                message: errorMessage.value!,
                rawResponse: rawResponse.value,
                onDismiss: () {
                  errorMessage.value = null;
                  rawResponse.value = null;
                },
              ),
            Expanded(
              child: artifactsState.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(child: Text('无法读取可视化记录：$error')),
                data: (_) => Column(
                  children: [
                    if (activeArtifact != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: DropdownButton<VisualArtifact>(
                                isExpanded: true,
                                value: activeArtifact,
                                items: [
                                  for (final artifact in artifactOptions)
                                    DropdownMenuItem(
                                      value: artifact,
                                      child: Text(
                                        '${artifact.kind == VisualArtifactKind.wordCloud ? '词云' : '导图'} · '
                                        '${artifact.scope.label} · ${artifact.title}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: busyKind.value == null
                                    ? (artifact) =>
                                          selectedArtifact.value = artifact
                                    : null,
                              ),
                            ),
                            if (activeArtifact.kind ==
                                VisualArtifactKind.wordCloud)
                              IconButton(
                                tooltip: '更换 seed 重新排布（不重新分词）',
                                onPressed: busyKind.value == null
                                    ? () => unawaited(reseed())
                                    : null,
                                icon: const Icon(Icons.shuffle),
                              ),
                            IconButton(
                              tooltip: '导出',
                              onPressed: () => unawaited(exportArtifact()),
                              icon: const Icon(Icons.download_outlined),
                            ),
                            IconButton(
                              tooltip: '删除记录',
                              onPressed: busyKind.value == null
                                  ? () => unawaited(deleteArtifact())
                                  : null,
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: activeArtifact == null
                          ? const _VisualizationEmptyState()
                          : Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: ColoredBox(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerLowest,
                                  child: VisualArtifactView(
                                    key: ValueKey(activeArtifact.id),
                                    artifact: activeArtifact,
                                    onOpenCitation: onOpenCitation,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecoverableError extends StatelessWidget {
  const _RecoverableError({
    required this.message,
    required this.onDismiss,
    this.rawResponse,
  });

  final String message;
  final String? rawResponse;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
              IconButton(
                tooltip: '关闭错误',
                onPressed: onDismiss,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          if (rawResponse?.isNotEmpty == true)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('查看模型原始纯文本响应'),
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: SingleChildScrollView(
                    child: SelectionArea(
                      child: Text(
                        rawResponse!,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    ),
  );
}

class _VisualizationEmptyState extends StatelessWidget {
  const _VisualizationEmptyState();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.hub_outlined,
            size: 54,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 14),
          Text('尚无可视化记录', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 7),
          const Text(
            '本地词云无需联网；AI 思维导图使用当前激活服务商。'
            '两者只读取可信正文索引，不修改原书。',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
