import 'package:hooks_riverpod/hooks_riverpod.dart';

enum ReaderRuntimePhase { idle, navigating, ready, failed }

class ReaderRuntimeState {
  const ReaderRuntimeState({
    this.phase = ReaderRuntimePhase.idle,
    this.revision = 0,
    this.error,
  });

  final ReaderRuntimePhase phase;
  final int revision;
  final Object? error;
}

final readerRuntimeControllerProvider =
    NotifierProvider.autoDispose<ReaderRuntimeController, ReaderRuntimeState>(
      ReaderRuntimeController.new,
    );

class ReaderRuntimeController extends Notifier<ReaderRuntimeState> {
  @override
  ReaderRuntimeState build() => const ReaderRuntimeState();

  int beginNavigation() {
    final revision = state.revision + 1;
    state = ReaderRuntimeState(
      phase: ReaderRuntimePhase.navigating,
      revision: revision,
    );
    return revision;
  }

  bool isCurrent(int revision) => state.revision == revision;

  void completeNavigation(int revision) {
    if (!isCurrent(revision)) return;
    state = ReaderRuntimeState(
      phase: ReaderRuntimePhase.ready,
      revision: revision,
    );
  }

  void reportFailure(int revision, Object error) {
    if (!isCurrent(revision)) return;
    state = ReaderRuntimeState(
      phase: ReaderRuntimePhase.failed,
      revision: revision,
      error: error,
    );
  }

  void reportRelocation() {
    if (state.phase == ReaderRuntimePhase.navigating) {
      state = ReaderRuntimeState(
        phase: ReaderRuntimePhase.ready,
        revision: state.revision,
      );
    }
  }
}
