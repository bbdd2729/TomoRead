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
                'تشخيصات التخزين',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: 'تحديث',
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
        const Text('يعالج التنظيف ذاكرات التخزين المؤقت القابلة لإعادة الإنشاء فقط ؛ قواعد البيانات والنُسخ الأصلية والخطوط والنسخ الاحتياطية والملفات التي يتم تصديرها بشكل نشط محمية افتراضيًا.'),
        const SizedBox(height: 16),
        state.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Text('غير قادر على قراءة معلومات التخزين: $error'),
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
              '${report.fileCount}العنصر${_formatBytes(report.totalBytes)}'
              '${report.orphanCount == 0 ? '' : ' · ${report.orphanCount} ملفات يتيمة'}',
            ),
            trailing: report.regenerable
                ? const Chip(label: Text('قابلة لإعادة البناء'))
                : const Chip(label: Text('محمي')),
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
              'تاريخ آخر تنظيف:${value.lastCleanup!.itemCount}العنصر'
              'الإصدار التقريبي.${_formatBytes(value.lastCleanup!.bytes)}。',
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
              label: const Text('تنظيف ذاكرة التخزين المؤقت القابلة لإعادة البناء'),
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
                label: const Text('مراجعة وحذف الملفات اليتيمة'),
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
          title: Text(orphans ? 'هل تريد حذف الملفات اليتيمة المؤكدة ؟' : 'هل تريد تنظيف ذاكرة التخزين المؤقت القابلة لإعادة البناء ؟'),
          content: Text(
            'ستتم معالجته${plan.itemCount}البند، الإصدار المتوقع${_formatBytes(plan.bytes)}。'
            '${orphans ? 'لا تتم الإشارة إلى هذه الملفات بواسطة قاعدة البيانات ولا يمكن التراجع عنها بواسطة عملية تنظيف بعد الحذف.' : 'تتم إعادة بناء ذاكرة التخزين المؤقت تلقائيًا في المرة التالية التي يتم فيها استخدام الوظيفة المقابلة.'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('تأكيد التنظيف'),
            ),
          ],
        ),
      ) ??
      false;
}

String _categoryLabel(StorageCategory category) => switch (category) {
  StorageCategory.database => 'قواعد البيانات',
  StorageCategory.managedBooks => 'حفظ الكتب الأصلية',
  StorageCategory.covers => 'الغلاف',
  StorageCategory.epubCache => 'EPUB Unzip Cache',
  StorageCategory.textProjectionCache => 'ذاكرة التخزين المؤقت لمؤشر الجسم',
  StorageCategory.wordCloudCache => 'ذاكرة التخزين المؤقت لـ Word Cloud',
  StorageCategory.visualExportTemporary => 'تصدير الملفات المؤقتة المرئية',
  StorageCategory.importStaging => 'استيراد الملفات المؤقتة',
  StorageCategory.importedFonts => 'الخطوط المستوردة',
  StorageCategory.backups => 'استرجاع النسخ الاحتياطية تلقائيًا',
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
