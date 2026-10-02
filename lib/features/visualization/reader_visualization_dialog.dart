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
            title: const Text('استخدام الكتاب بأكمله ؟'),
            content: const Text(
              'قد يحتوي نطاق الكتاب بأكمله على فصول لم تتم قراءتها بعد. عند إنشاء سحابة كلمات، تتم معالجتها محليًا فقط ؛'
              'يتم إرسال شظايا الجسم التي يتم التحكم فيها ضمن النطاق إلى مزود خدمة الذكاء الاصطناعي الحالي عند إنشاء خريطة ذهنية.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('تأكيد نطاق الكتاب بأكمله'),
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
        if (context.mounted) errorMessage.value = 'تم إلغاء إنشاء الخريطة الذهنية.';
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
          title: const Text('هل تريد حذف السجل المرئي ؟'),
          content: Text('سيتم إزالة "${artifact.title}" من البيانات المشتقة محليًا ولن يؤثر ذلك على الكتاب الأصلي.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      try {
        await controller.delete(artifact);
        if (context.mounted) selectedArtifact.value = null;
      } on Object catch (error) {
        if (context.mounted) errorMessage.value = 'فشل الحذف: $error';
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
          title: const Text('تحديد تنسيق التصدير'),
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
          ).showSnackBar(SnackBar(content: Text('تم التصدير إلى $path')));
        }
      } on Object catch (error) {
        if (context.mounted) errorMessage.value = 'فشل التصدير: $error';
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
                            'سحابة الكلمات والخرائط الذهنية',
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
                      tooltip: 'مغلق',
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
                    label: const Text('سحابة الكلمات المحلية'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: busyKind.value == null
                        ? () => unawaited(
                            generate(VisualArtifactKind.mindMap),
                          )
                        : null,
                    icon: const Icon(Icons.account_tree_outlined),
                    label: const Text('الخريطة الذهنية للذكاء الاصطناعي'),
                  ),
                  if (busyKind.value != null)
                    OutlinedButton.icon(
                      onPressed: cancelling.value
                          ? null
                          : () => unawaited(cancelGeneration()),
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: Text(cancelling.value ? 'إلغاء' : 'إلغاء'),
                    ),
                ],
              ),
            ),
            if (busyKind.value != null)
              LinearProgressIndicator(
                semanticsLabel: busyKind.value == VisualArtifactKind.wordCloud
                    ? 'توليد سحابة الكلمات محليًا'
                    : 'إنشاء خريطة ذهنية للذكاء الاصطناعي',
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
                error: (error, _) => Center(child: Text('تعذر قراءة السجل المرئي: $error')),
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
                                        '${artifact.kind == VisualArtifactKind.wordCloud ? 'سحابة وورد' : 'الخريطة'} · '
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
                                tooltip: 'استبدال إعادة ترتيب البذور (بدون إعادة صياغة)',
                                onPressed: busyKind.value == null
                                    ? () => unawaited(reseed())
                                    : null,
                                icon: const Icon(Icons.shuffle),
                              ),
                            IconButton(
                              tooltip: 'التصدير',
                              onPressed: () => unawaited(exportArtifact()),
                              icon: const Icon(Icons.download_outlined),
                            ),
                            IconButton(
                              tooltip: 'احذف سجل',
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
                tooltip: 'إغلاق الخطأ',
                onPressed: onDismiss,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          if (rawResponse?.isNotEmpty == true)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('عرض نموذج استجابة نص عادي خام'),
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
          Text('لا توجد تسجيلات مرئية حتى الآن', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 7),
          const Text(
            'لا تتطلب سحابة الكلمات المحلية الربط الشبكي ؛ تستخدم الخريطة الذهنية للذكاء الاصطناعي مزود خدمة التنشيط الحالي.'
            'كلاهما يقرأ فقط مؤشر الجسم الموثوق به ولا يعدل الكتاب الأصلي.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
