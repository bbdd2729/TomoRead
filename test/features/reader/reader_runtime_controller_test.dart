import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tomoread/features/reader/reader_runtime_controller.dart';

void main() {
  test('keeps runtime callbacks harmless after auto-dispose', () {
    final container = ProviderContainer();
    final controller = container.read(readerRuntimeControllerProvider.notifier);
    final revision = controller.beginNavigation();

    expect(revision, 1);
    expect(
      container.read(readerRuntimeControllerProvider).phase,
      ReaderRuntimePhase.navigating,
    );

    container.dispose();

    // A WebView callback can race route disposal. It must be ignored rather
    // than throwing while trying to read the disposed notifier state.
    expect(() => controller.reportRelocation(), returnsNormally);
    expect(() => controller.completeNavigation(revision), returnsNormally);
    expect(
      () => controller.reportFailure(revision, StateError('stale')),
      returnsNormally,
    );
  });
}
