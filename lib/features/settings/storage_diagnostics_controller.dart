import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../data/services/storage_diagnostics_service.dart';

class StorageDiagnosticsState {
  const StorageDiagnosticsState({
    required this.reports,
    this.cleaning = false,
    this.lastCleanup,
    this.error,
  });

  final List<StorageCategoryReport> reports;
  final bool cleaning;
  final StorageCleanupRecord? lastCleanup;
  final String? error;
}

final storageDiagnosticsControllerProvider = AsyncNotifierProvider<
  StorageDiagnosticsController,
  StorageDiagnosticsState
>(StorageDiagnosticsController.new);

class StorageDiagnosticsController
    extends AsyncNotifier<StorageDiagnosticsState> {
  @override
  Future<StorageDiagnosticsState> build() async => StorageDiagnosticsState(
    reports: await ref.watch(storageDiagnosticsServiceProvider).inspect(),
  );

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () async => StorageDiagnosticsState(
        reports: await ref.read(storageDiagnosticsServiceProvider).inspect(),
      ),
    );
  }

  Future<StorageCleanupPlan> planRegenerableCleanup() => ref
      .read(storageDiagnosticsServiceProvider)
      .planCleanup(StorageCategory.values);

  Future<StorageCleanupPlan> planOrphanCleanup() => ref
      .read(storageDiagnosticsServiceProvider)
      .planCleanup(
        const [
          StorageCategory.managedBooks,
          StorageCategory.covers,
          StorageCategory.importedFonts,
        ],
        includeConfirmedOrphans: true,
      );

  Future<void> execute(StorageCleanupPlan plan) async {
    final current = state.value;
    if (current == null || current.cleaning) return;
    state = AsyncData(
      StorageDiagnosticsState(
        reports: current.reports,
        cleaning: true,
        lastCleanup: current.lastCleanup,
      ),
    );
    try {
      final record = await ref
          .read(storageDiagnosticsServiceProvider)
          .executeCleanup(plan);
      ref.invalidate(contentIndexRevisionProvider);
      ref.invalidate(visualArtifactRevisionProvider);
      state = AsyncData(
        StorageDiagnosticsState(
          reports: await ref.read(storageDiagnosticsServiceProvider).inspect(),
          lastCleanup: record,
        ),
      );
    } on Object catch (error) {
      state = AsyncData(
        StorageDiagnosticsState(
          reports: current.reports,
          lastCleanup: current.lastCleanup,
          error: error.toString(),
        ),
      );
    }
  }
}
