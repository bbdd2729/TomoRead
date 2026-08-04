import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tomoread/app/providers.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/services/backup_service.dart';
import 'package:tomoread/data/services/restore_service.dart';
import 'package:tomoread/domain/models/backup_manifest.dart';
import 'package:tomoread/features/settings/backup_restore_controller.dart';

void main() {
  late AppDatabase database;
  late ProviderContainer container;
  late FakeBackupService backup;
  late FakeRestoreService restore;

  setUp(() async {
    database = AppDatabase.inMemory();
    backup = FakeBackupService(database);
    restore = FakeRestoreService(database, backup);
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        backupServiceProvider.overrideWith((ref) => backup),
        restoreServiceProvider.overrideWith((ref) => restore),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });
  });

  test('createTo reports progress and succeeds with an output path', () async {
    final notifier = container.read(backupRestoreControllerProvider.notifier);
    expect(
      container.read(backupRestoreControllerProvider).status,
      BackupRestoreStatus.idle,
    );

    await notifier.createTo('C:/backups/out.zip');

    final state = container.read(backupRestoreControllerProvider);
    expect(state.status, BackupRestoreStatus.succeeded);
    expect(state.outputPath, 'C:/backups/out.zip');
    expect(backup.createdTo, 'C:/backups/out.zip');
  });

  test('createTo records a failure without throwing', () async {
    backup.failWith = StateError('disk full');
    final notifier = container.read(backupRestoreControllerProvider.notifier);

    await notifier.createTo('C:/backups/fail.zip');

    final state = container.read(backupRestoreControllerProvider);
    expect(state.status, BackupRestoreStatus.failed);
    expect(state.error, contains('disk full'));
  });

  test('restoreFrom succeeds and records the rollback path', () async {
    final notifier = container.read(backupRestoreControllerProvider.notifier);

    await notifier.restoreFrom('C:/backups/in.zip');

    final state = container.read(backupRestoreControllerProvider);
    expect(state.status, BackupRestoreStatus.succeeded);
    expect(state.rollbackBackupPath, 'C:/rollback.zip');
    expect(restore.restoredFrom, 'C:/backups/in.zip');
  });

  test('restoreFrom records a failure without throwing', () async {
    restore.failWith = StateError('corrupt archive');
    final notifier = container.read(backupRestoreControllerProvider.notifier);

    await notifier.restoreFrom('C:/backups/corrupt.zip');

    final state = container.read(backupRestoreControllerProvider);
    expect(state.status, BackupRestoreStatus.failed);
    expect(state.error, contains('corrupt archive'));
  });

  test('retry re-runs the last action after a failure', () async {
    backup.failWith = StateError('first try failed');
    final notifier = container.read(backupRestoreControllerProvider.notifier);
    await notifier.createTo('C:/backups/retry.zip');
    expect(
      container.read(backupRestoreControllerProvider).status,
      BackupRestoreStatus.failed,
    );

    backup.failWith = null;
    await notifier.retry();

    final state = container.read(backupRestoreControllerProvider);
    expect(state.status, BackupRestoreStatus.succeeded);
    expect(backup.createdTo, 'C:/backups/retry.zip');
  });
}

class FakeBackupService extends BackupService {
  FakeBackupService(AppDatabase database)
    : super(
        database: database,
        appVersion: '1.0.0+1',
        deviceId: 'device-1',
      );

  String? createdTo;
  Object? failWith;

  @override
  Future<BackupManifest> create({
    required String destinationPath,
    BackupOptions options = const BackupOptions(),
    BackupProgressCallback? onProgress,
    BackupCancellationToken? cancellationToken,
  }) async {
    final error = failWith;
    if (error != null) throw error;
    createdTo = destinationPath;
    onProgress?.call(const BackupProgress(phase: BackupPhase.preparing));
    onProgress?.call(const BackupProgress(phase: BackupPhase.completed));
    return _manifest();
  }
}

class FakeRestoreService extends RestoreService {
  FakeRestoreService(AppDatabase database, BackupService backupService)
    : super(database: database, backupService: backupService);

  String? restoredFrom;
  Object? failWith;

  @override
  Future<RestoreResult> restore({
    required String archivePath,
    RestoreProgressCallback? onProgress,
    RestoreCancellationToken? cancellationToken,
  }) async {
    final error = failWith;
    if (error != null) throw error;
    restoredFrom = archivePath;
    return RestoreResult(
      manifest: _manifest(),
      rollbackBackupPath: 'C:/rollback.zip',
    );
  }
}

BackupManifest _manifest() => BackupManifest(
  createdAt: DateTime(2026, 8, 4),
  appVersion: '1.0.0+1',
  databaseSchemaVersion: 23,
  deviceId: 'device-1',
  includesBooks: true,
  includesFonts: false,
  contentSha256: 'deadbeef',
  entries: const [],
);
