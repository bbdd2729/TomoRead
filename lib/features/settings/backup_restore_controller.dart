import 'package:file_picker/file_picker.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../data/services/backup_service.dart';
import '../../data/services/restore_service.dart';
import 'font_catalog_controller.dart';

enum BackupRestoreStatus { idle, backingUp, restoring, succeeded, failed }

class BackupRestoreState {
  const BackupRestoreState({
    this.status = BackupRestoreStatus.idle,
    this.message,
    this.progress,
    this.error,
    this.outputPath,
    this.rollbackBackupPath,
  });

  final BackupRestoreStatus status;
  final String? message;
  final double? progress;
  final String? error;
  final String? outputPath;
  final String? rollbackBackupPath;

  bool get running =>
      status == BackupRestoreStatus.backingUp ||
      status == BackupRestoreStatus.restoring;
}

final backupRestoreControllerProvider =
    NotifierProvider<BackupRestoreController, BackupRestoreState>(
      BackupRestoreController.new,
    );

class BackupRestoreController extends Notifier<BackupRestoreState> {
  BackupCancellationToken? _backupCancellation;
  RestoreCancellationToken? _restoreCancellation;
  Future<void> Function()? _retry;

  @override
  BackupRestoreState build() => const BackupRestoreState();

  Future<void> createWithPicker() async {
    final destination = await FilePicker.saveFile(
      dialogTitle: '导出 TomoRead 备份',
      fileName: 'tomoread-backup-${_dateStamp()}.tomoread.zip',
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    if (destination == null) return;
    await createTo(destination);
  }

  Future<void> createTo(String destinationPath) async {
    if (state.running) return;
    _retry = () => createTo(destinationPath);
    final cancellation = BackupCancellationToken();
    _backupCancellation = cancellation;
    state = const BackupRestoreState(
      status: BackupRestoreStatus.backingUp,
      message: '正在准备备份…',
    );
    try {
      final service = await ref.read(backupServiceProvider.future);
      await service.create(
        destinationPath: destinationPath,
        cancellationToken: cancellation,
        onProgress: (progress) {
          if (!ref.mounted) return;
          state = BackupRestoreState(
            status: BackupRestoreStatus.backingUp,
            message: _backupPhaseLabel(progress.phase),
            progress: progress.total == 0
                ? null
                : progress.completed / progress.total,
          );
        },
      );
      state = BackupRestoreState(
        status: BackupRestoreStatus.succeeded,
        message: '备份已创建并完成校验。',
        outputPath: destinationPath,
      );
    } on Object catch (error) {
      state = BackupRestoreState(
        status: BackupRestoreStatus.failed,
        error: error.toString(),
      );
    } finally {
      _backupCancellation = null;
    }
  }

  Future<void> restoreWithPicker() async {
    final selection = await FilePicker.pickFiles(
      dialogTitle: '选择 TomoRead 备份',
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      allowMultiple: false,
      withData: false,
    );
    final archivePath = selection?.files.single.path;
    if (archivePath == null) return;
    await restoreFrom(archivePath);
  }

  Future<void> restoreFrom(String archivePath) async {
    if (state.running) return;
    _retry = () => restoreFrom(archivePath);
    final cancellation = RestoreCancellationToken();
    _restoreCancellation = cancellation;
    state = const BackupRestoreState(
      status: BackupRestoreStatus.restoring,
      message: '正在验证备份…',
    );
    try {
      final service = await ref.read(restoreServiceProvider.future);
      final result = await service.restore(
        archivePath: archivePath,
        cancellationToken: cancellation,
        onProgress: (progress) {
          if (!ref.mounted) return;
          state = BackupRestoreState(
            status: BackupRestoreStatus.restoring,
            message: _restorePhaseLabel(progress.phase),
            progress: progress.total == 0
                ? null
                : progress.completed / progress.total,
          );
        },
      );
      ref.invalidate(appSettingsProvider);
      ref.invalidate(libraryBooksProvider);
      ref.invalidate(fontCatalogControllerProvider);
      ref.invalidate(annotationRevisionProvider);
      ref.invalidate(statisticsRevisionProvider);
      ref.invalidate(contentIndexRevisionProvider);
      state = BackupRestoreState(
        status: BackupRestoreStatus.succeeded,
        message: '书库已恢复。重启阅读页即可使用恢复后的内容。',
        rollbackBackupPath: result.rollbackBackupPath,
      );
    } on Object catch (error) {
      state = BackupRestoreState(
        status: BackupRestoreStatus.failed,
        error: error.toString(),
      );
    } finally {
      _restoreCancellation = null;
    }
  }

  void cancel() {
    _backupCancellation?.cancel();
    _restoreCancellation?.cancel();
  }

  Future<void> retry() async {
    final action = _retry;
    if (action != null) await action();
  }

  void reset() => state = const BackupRestoreState();

  String _dateStamp() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
  }

  String _backupPhaseLabel(BackupPhase phase) => switch (phase) {
    BackupPhase.preparing => '正在准备备份…',
    BackupPhase.snapshotting => '正在创建一致性数据库快照…',
    BackupPhase.collectingFiles => '正在收集托管书籍、封面和字体…',
    BackupPhase.writingArchive => '正在写入备份包…',
    BackupPhase.verifying => '正在校验备份包…',
    BackupPhase.completed => '备份已完成。',
  };

  String _restorePhaseLabel(RestorePhase phase) => switch (phase) {
    RestorePhase.validating => '正在验证备份清单和哈希…',
    RestorePhase.extracting => '正在隔离解压备份…',
    RestorePhase.validatingDatabase => '正在校验数据库完整性…',
    RestorePhase.creatingRollback => '正在创建恢复前回滚备份…',
    RestorePhase.switchingData => '正在安全切换书库数据…',
    RestorePhase.reopeningDatabase => '正在重新打开并迁移数据库…',
    RestorePhase.completed => '恢复已完成。',
  };
}
