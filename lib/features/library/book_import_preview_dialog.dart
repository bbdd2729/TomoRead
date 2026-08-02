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
            child: const Text('取消扫描'),
          ),
        ],
        ImportWorkflowPhase.preview => [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: state.preview?.requests.isEmpty == false
                ? () => unawaited(controller.startImport())
                : null,
            child: Text('开始导入 ${state.preview?.supportedCount ?? 0} 本'),
          ),
        ],
        ImportWorkflowPhase.importing => [
          TextButton(
            onPressed: controller.cancel,
            child: const Text('停止后续导入'),
          ),
        ],
        ImportWorkflowPhase.completed || ImportWorkflowPhase.cancelled => [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(state.results),
            child: const Text('完成'),
          ),
        ],
        ImportWorkflowPhase.failed => [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      };

  String _title(ImportWorkflowPhase phase) => switch (phase) {
    ImportWorkflowPhase.idle || ImportWorkflowPhase.scanning => '正在扫描导入内容',
    ImportWorkflowPhase.preview => '确认导入内容',
    ImportWorkflowPhase.importing => '正在导入书籍',
    ImportWorkflowPhase.completed => '导入完成',
    ImportWorkflowPhase.cancelled => '导入已取消',
    ImportWorkflowPhase.failed => '无法处理导入内容',
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
                ? '正在校验 ${state.completed}/${state.total} 个候选文件…'
                : '正在递归扫描目录并过滤不支持的文件…',
          ),
        ],
      );
    }
    if (state.phase == ImportWorkflowPhase.failed) {
      return SelectableText('扫描或导入失败：${state.error}');
    }
    final preview = state.preview;
    if (preview == null) {
      return const Text('没有可显示的导入结果。');
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
          Text('已处理 ${state.completed}/${state.total} 本'),
          const SizedBox(height: 16),
        ],
        _ImportSummary(preview: preview, results: state.results),
        if (preview.limitReached) ...[
          const SizedBox(height: 12),
          const Text('扫描已达到数量或大小上限，超出部分不会导入。'),
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
        _SummaryChip(label: '可导入', value: preview.supportedCount),
        _SummaryChip(label: '已跳过', value: preview.skippedCount),
        _SummaryChip(label: '重复', value: preview.duplicateCount),
        _SummaryChip(label: '失败', value: preview.failedCount),
        if (results.isNotEmpty) _SummaryChip(label: '已导入', value: imported),
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
