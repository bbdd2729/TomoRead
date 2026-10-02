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
      dialogTitle: 'تصدير نسخة احتياطية من TomoRead',
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
      message: 'جارٍ تحضير النسخة الاحتياطية...',
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
        message: 'تم إنشاء النسخة الاحتياطية والتحقق منها.',
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
      dialogTitle: 'تحديد نسخة احتياطية من TomoRead',
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
      message: 'جارٍ التحقق من النسخ الاحتياطي...',
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
        message: 'تمت استعادة المكتبة. أعد تشغيل صفحة القراءة لاستخدام المحتوى المستعاد.',
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
    BackupPhase.preparing => 'جارٍ تحضير النسخة الاحتياطية...',
    BackupPhase.snapshotting => 'إنشاء لقطة متسقة لقاعدة البيانات...',
    BackupPhase.collectingFiles => 'جمع الكتب والأغلفة والخطوط المستضافة...',
    BackupPhase.writingArchive => 'جارٍ كتابة حزمة النسخ الاحتياطي...',
    BackupPhase.verifying => 'جارٍ التحقق من حزمة النسخ الاحتياطي...',
    BackupPhase.completed => 'اكتمل النسخ الاحتياطي.',
  };

  String _restorePhaseLabel(RestorePhase phase) => switch (phase) {
    RestorePhase.validating => 'التحقق من بيان النسخ الاحتياطي والتجزئة...',
    RestorePhase.extracting => 'عزل النسخ الاحتياطي لتخفيف الضغط...',
    RestorePhase.validatingDatabase => 'التحقق من سلامة قاعدة البيانات...',
    RestorePhase.creatingRollback => 'جارٍ إنشاء نسخة احتياطية قبل الاستعادة...',
    RestorePhase.switchingData => 'تبديل بيانات المكتبة بأمان...',
    RestorePhase.reopeningDatabase => 'إعادة فتح قاعدة البيانات وترحيلها...',
    RestorePhase.completed => 'اكتمل الاسترداد.',
  };
}
