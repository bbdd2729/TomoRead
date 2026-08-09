import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/features/reader/volume_control_service.dart';
import 'package:tomoread/features/reader/volume_key_page_turner.dart';

void main() {
  test(
    'maps volume up and down to page navigation and disables on disposal',
    () async {
      final events = StreamController<VolumeKeyEvent>();
      final control = _FakeVolumeKeyControl(events.stream);
      final turner = VolumeKeyPageTurner(control: control);
      var previousCount = 0;
      var nextCount = 0;

      await turner.configure(
        enabled: true,
        onPrevious: () => previousCount++,
        onNext: () => nextCount++,
      );
      events
        ..add(VolumeKeyEvent.up)
        ..add(VolumeKeyEvent.down);
      await Future<void>.delayed(Duration.zero);
      await turner.dispose();

      expect(previousCount, 1);
      expect(nextCount, 1);
      expect(control.enableCalls, 1);
      expect(control.disableCalls, 1);
    },
  );

  test('does not subscribe while disabled', () async {
    final events = StreamController<VolumeKeyEvent>();
    final control = _FakeVolumeKeyControl(events.stream);
    final turner = VolumeKeyPageTurner(control: control);
    var nextCount = 0;

    await turner.configure(
      enabled: false,
      onPrevious: () {},
      onNext: () => nextCount++,
    );
    events.add(VolumeKeyEvent.down);
    await Future<void>.delayed(Duration.zero);

    expect(nextCount, 0);
    expect(control.enableCalls, 0);
    expect(control.disableCalls, 1);
  });

  test('parses only supported Android volume-key events', () {
    expect(parseAndroidVolumeKeyEvent('up'), VolumeKeyEvent.up);
    expect(parseAndroidVolumeKeyEvent('down'), VolumeKeyEvent.down);
    expect(parseAndroidVolumeKeyEvent('unknown'), isNull);
    expect(parseAndroidVolumeKeyEvent(1), isNull);
  });
}

class _FakeVolumeKeyControl implements VolumeKeyControl {
  _FakeVolumeKeyControl(this.events);

  @override
  final Stream<VolumeKeyEvent> events;
  int enableCalls = 0;
  int disableCalls = 0;

  @override
  Future<void> disable() async => disableCalls++;

  @override
  Future<void> enable() async => enableCalls++;
}
