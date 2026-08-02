import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../data/services/storage_diagnostics_service.dart';
import 'storage_diagnostics_controller.dart';

class StorageDiagnosticsPage extends ConsumerWidget {
  const StorageDiagnosticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(storageDiagnosticsControllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '存储诊断',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: '刷新',
              onPressed: state.isLoading
                  ? null
                  : ref
                        .read(storageDiagnosticsControllerProvider.notifier)
                        .refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text('清理只处理可重建缓存；数据库、原书、字体、备份和主动导出的文件默认受保护。'),
        const SizedBox(height: 16),
        state.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Text('无法读取存储信息：$error'),
          data: (value) => _DiagnosticsContent(value: value),
        ),
      ],
    );
  }
}

class _DiagnosticsContent extends ConsumerWidget {
  const _DiagnosticsContent({required this.value});

  final StorageDiagnosticsState value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(storageDiagnosticsControllerProvider.notifier);
    final orphanCount = value.reports.fold<int>(
      0,
      (total, report) => total + report.orphanCount,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final report in value.reports)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(_categoryIcon(report.category)),
            title: Text(_categoryLabel(report.category)),
            subtitle: Text(
              '${report.fileCount} 项 · ${_formatBytes(report.totalBytes)}'
              '${report.orphanCount == 0 ? '' : ' · ${report.orphanCount} 个孤儿文件'}',
            ),
            trailing: report.regenerable
                ? const Chip(label: Text('可重建'))
                : const Chip(label: Text('受保护')),
          ),
        if (value.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              value.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (value.lastCleanup != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '上次清理：${value.lastCleanup!.itemCount} 项，'
              '释放约 ${_formatBytes(value.lastCleanup!.bytes)}。',
            ),
          ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.tonalIcon(
              key: const Key('clean-regenerable-storage'),
              onPressed: value.cleaning
                  ? null
                  : () async {
                      final plan = await controller.planRegenerableCleanup();
                      if (!context.mounted || plan.itemCount == 0) return;
                      if (await _confirmCleanup(context, plan, orphans: false)) {
                        await controller.execute(plan);
                      }
                    },
              icon: const Icon(Icons.cleaning_services_outlined),
              label: const Text('清理可重建缓存'),
            ),
            if (orphanCount > 0)
              OutlinedButton.icon(
                onPressed: value.cleaning
                    ? null
                    : () async {
                        final plan = await controller.planOrphanCleanup();
                        if (!context.mounted || plan.itemCount == 0) return;
                        if (await _confirmCleanup(context, plan, orphans: true)) {
                          await controller.execute(plan);
                        }
                      },
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('检查并删除孤儿文件'),
              ),
          ],
        ),
        if (value.cleaning) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
      ],
    );
  }

  Future<bool> _confirmCleanup(
    BuildContext context,
    StorageCleanupPlan plan, {
    required bool orphans,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(orphans ? '删除已确认的孤儿文件？' : '清理可重建缓存？'),
          content: Text(
            '将处理 ${plan.itemCount} 项，预计释放 ${_formatBytes(plan.bytes)}。'
            '${orphans ? '这些文件未被数据库引用，删除后无法由清理操作撤销。' : '缓存会在下次使用对应功能时自动重建。'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('确认清理'),
            ),
          ],
        ),
      ) ??
      false;
}

String _categoryLabel(StorageCategory category) => switch (category) {
  StorageCategory.database => '数据库',
  StorageCategory.managedBooks => '托管原书',
  StorageCategory.covers => '封面',
  StorageCategory.epubCache => 'EPUB 解压缓存',
  StorageCategory.textProjectionCache => '正文索引缓存',
  StorageCategory.wordCloudCache => '词云缓存',
  StorageCategory.visualExportTemporary => '可视化导出临时文件',
  StorageCategory.importStaging => '导入临时文件',
  StorageCategory.importedFonts => '已导入字体',
  StorageCategory.backups => '自动回滚备份',
};

IconData _categoryIcon(StorageCategory category) => switch (category) {
  StorageCategory.database => Icons.storage_outlined,
  StorageCategory.managedBooks => Icons.menu_book_outlined,
  StorageCategory.covers => Icons.image_outlined,
  StorageCategory.epubCache || StorageCategory.textProjectionCache || StorageCategory.wordCloudCache =>
    Icons.cached_outlined,
  StorageCategory.visualExportTemporary || StorageCategory.importStaging =>
    Icons.hourglass_empty,
  StorageCategory.importedFonts => Icons.font_download_outlined,
  StorageCategory.backups => Icons.settings_backup_restore,
};

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
