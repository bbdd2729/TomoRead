import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/services/book_import_service.dart';
import '../../domain/models/book_import.dart';
import 'import_workflow_controller.dart';

class BookImportPreviewDialog extends StatelessWidget {
  const BookImportPreviewDialog({super.key, required this.controller});

  final ImportWorkflowController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final state = controller.state;
      return AlertDialog(
        title: Text(_title(state.phase)),
        content: SizedBox(
          width: 680,
          child: _ImportDialogContent(state: state),
        ),
        actions: _actions(context, state),
      );
    },
  );

  List<Widget> _actions(BuildContext context, ImportWorkflowState state) =>
      switch (state.phase) {
        ImportWorkflowPhase.idle || ImportWorkflowPhase.scanning => [
          TextButton(
            onPressed: controller.cancel,
            child: const Text('إلغاء المسح الضوئي'),
          ),
        ],
        ImportWorkflowPhase.preview => [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: state.preview?.requests.isEmpty == false
                ? () => unawaited(controller.startImport())
                : null,
            child: Text('بدء الاستيراد${state.preview?.supportedCount ?? 0}حجز'),
          ),
        ],
        ImportWorkflowPhase.importing => [
          TextButton(
            onPressed: controller.cancel,
            child: const Text('إيقاف الواردات اللاحقة'),
          ),
        ],
        ImportWorkflowPhase.completed || ImportWorkflowPhase.cancelled => [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(state.results),
            child: const Text('اكتمال'),
          ),
        ],
        ImportWorkflowPhase.failed => [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('مغلق'),
          ),
        ],
      };

  String _title(ImportWorkflowPhase phase) => switch (phase) {
    ImportWorkflowPhase.idle || ImportWorkflowPhase.scanning => 'استيراد المسح الضوئي',
    ImportWorkflowPhase.preview => 'تأكيد الاستيراد',
    ImportWorkflowPhase.importing => 'استيراد الكتب',
    ImportWorkflowPhase.completed => 'فشل أستيراد vCard',
    ImportWorkflowPhase.cancelled => 'تم إلغاء الاستيراد',
    ImportWorkflowPhase.failed => 'تعذر معالجة الاستيراد',
  };
}

class _ImportDialogContent extends StatelessWidget {
  const _ImportDialogContent({required this.state});

  final ImportWorkflowState state;

  @override
  Widget build(BuildContext context) {
    if (state.phase == ImportWorkflowPhase.idle ||
        state.phase == ImportWorkflowPhase.scanning) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const LinearProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            state.total > 0
                ? 'جاري التَحقق...${state.completed}/${state.total}ملفات المرشحين...'
                : 'مسح الدلائل ضوئيًا بشكل متكرر وتصفية الملفات غير المدعومة...',
          ),
        ],
      );
    }
    if (state.phase == ImportWorkflowPhase.failed) {
      return SelectableText('فشل المسح الضوئي أو الاستيراد:${state.error}');
    }
    final preview = state.preview;
    if (preview == null) {
      return const Text('لا توجد نتائج استيراد لعرضها.');
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.phase == ImportWorkflowPhase.importing) ...[
          LinearProgressIndicator(
            value: state.total == 0 ? null : state.completed / state.total,
          ),
          const SizedBox(height: 12),
          Text('تمت معالجته${state.completed}/${state.total}حجز'),
          const SizedBox(height: 16),
        ],
        _ImportSummary(preview: preview, results: state.results),
        if (preview.limitReached) ...[
          const SizedBox(height: 12),
          const Text('وصل المسح إلى الحد الأقصى للعدد أو الحجم، ولن يتم استيراد الفائض.'),
        ],
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: preview.items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = preview.items[index];
              return ListTile(
                dense: true,
                leading: Icon(_icon(item.disposition)),
                title: Text(
                  item.source.displayName ?? item.source.location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: item.reason == null ? null : Text(item.reason!),
              );
            },
          ),
        ),
      ],
    );
  }

  IconData _icon(ImportScanDisposition disposition) => switch (disposition) {
    ImportScanDisposition.supported => Icons.check_circle_outline,
    ImportScanDisposition.duplicate => Icons.content_copy,
    ImportScanDisposition.skipped => Icons.do_not_disturb_alt_outlined,
    ImportScanDisposition.failed => Icons.error_outline,
  };
}

class _ImportSummary extends StatelessWidget {
  const _ImportSummary({required this.preview, required this.results});

  final ImportScanPreview preview;
  final List<BookImportResult> results;

  @override
  Widget build(BuildContext context) {
    final imported = results
        .where((result) => result.status == BookImportStatus.imported)
        .length;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _SummaryChip(label: 'يمكن استيرادها', value: preview.supportedCount),
        _SummaryChip(label: 'تم التخطي', value: preview.skippedCount),
        _SummaryChip(label: 'التكرار', value: preview.duplicateCount),
        _SummaryChip(label: 'فشلت', value: preview.failedCount),
        if (results.isNotEmpty) _SummaryChip(label: 'مستورد:', value: imported),
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Chip(label: Text('$label $value'));
}
