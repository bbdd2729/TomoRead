import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'backup_restore_controller.dart';

class BackupRestorePage extends ConsumerWidget {
  const BackupRestorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(backupRestoreControllerProvider);
    final controller = ref.read(backupRestoreControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('النسخ الاحتياطي والاستعادة', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'تتضمن النسخ الاحتياطية لقطات متسقة مع قاعدة البيانات والنسخ الأصلية المستضافة والأغلفة والخطوط المستوردة.'
          'لن يتم تضمين مفتاح واجهة برمجة التطبيقات أو كلمة مرور WebDAV أو ملف خط النظام.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              key: const Key('create-library-backup'),
              onPressed: state.running ? null : controller.createWithPicker,
              icon: const Icon(Icons.archive_outlined),
              label: const Text('إنشاء نسخة احتياطية'),
            ),
            OutlinedButton.icon(
              key: const Key('restore-library-backup'),
              onPressed: state.running
                  ? null
                  : () => _confirmRestore(context, controller),
              icon: const Icon(Icons.settings_backup_restore),
              label: const Text('الاستعادة من النسخ الاحتياطي'),
            ),
            if (state.running)
              TextButton.icon(
                onPressed: controller.cancel,
                icon: const Icon(Icons.close),
                label: const Text('إلغاء'),
              ),
          ],
        ),
        if (state.running ||
            state.status == BackupRestoreStatus.failed ||
            state.status == BackupRestoreStatus.succeeded) ...[
          const SizedBox(height: 20),
          _OperationStatus(state: state, onRetry: controller.retry),
        ],
      ],
    );
  }

  Future<void> _confirmRestore(
    BuildContext context,
    BackupRestoreController controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('استعادة المكتبة ؟'),
        content: const Text(
          'يتم إنشاء نسخة احتياطية للمكتبة الحالية تلقائيًا قبل الاستعادة. فقط في البيانات والتجزئة وقواعد البيانات'
          'لن يتم تبديل البيانات حتى يتم اجتياز جميع عمليات التحقق من السلامة ؛ لا تغلق التطبيق أثناء الاسترداد.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('تحديد النسخ الاحتياطي'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.restoreWithPicker();
  }
}

class _OperationStatus extends StatelessWidget {
  const _OperationStatus({required this.state, required this.onRetry});

  final BackupRestoreState state;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final failed = state.status == BackupRestoreStatus.failed;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: failed ? scheme.errorContainer : scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (state.running) ...[
              state.progress == null
                  ? const LinearProgressIndicator()
                  : LinearProgressIndicator(value: state.progress),
              const SizedBox(height: 12),
            ],
            Text(state.error ?? state.message ?? ''),
            if (state.outputPath != null) ...[
              const SizedBox(height: 6),
              const Text('تم حفظ النسخة الاحتياطية في الموقع الذي حددته.'),
            ],
            if (state.rollbackBackupPath != null) ...[
              const SizedBox(height: 6),
              const Text('النسخ الاحتياطي قبل الاحتفاظ بالاستعادة في دليل النسخ الاحتياطي للتطبيق.'),
            ],
            if (failed) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('أعد المحاولة'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
