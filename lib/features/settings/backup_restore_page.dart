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
        Text('备份与恢复', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          '备份包含数据库一致性快照、托管原书、封面和已导入字体，'
          '不会包含 API Key、WebDAV 密码或系统字体文件。',
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
              label: const Text('创建备份'),
            ),
            OutlinedButton.icon(
              key: const Key('restore-library-backup'),
              onPressed: state.running
                  ? null
                  : () => _confirmRestore(context, controller),
              icon: const Icon(Icons.settings_backup_restore),
              label: const Text('从备份恢复'),
            ),
            if (state.running)
              TextButton.icon(
                onPressed: controller.cancel,
                icon: const Icon(Icons.close),
                label: const Text('取消'),
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
        title: const Text('恢复书库？'),
        content: const Text(
          '恢复前会自动创建当前书库的回滚备份。只有在清单、哈希和数据库'
          '完整性全部验证通过后才会切换数据；恢复期间请不要关闭应用。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('选择备份'),
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
              const Text('备份已保存到你选择的位置。'),
            ],
            if (state.rollbackBackupPath != null) ...[
              const SizedBox(height: 6),
              const Text('恢复前的回滚备份已保留在应用备份目录。'),
            ],
            if (failed) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
