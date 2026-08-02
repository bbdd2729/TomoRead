import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/features/reader/reader_navigation_command.dart';

void main() {
  test('location commands clamp their reading ratio', () {
    final command = ReaderNavigationCommand.goToLocation(
      id: 4,
      href: 'OPS/chapter.xhtml',
      ratio: 2.5,
      anchor: 'section-2',
      cfi: 'epubcfi(/6/4)',
    );

    expect(command.id, 4);
    expect(command.kind, ReaderNavigationKind.goToLocation);
    expect(command.ratio, 1);
    expect(command.href, 'OPS/chapter.xhtml');
    expect(command.anchor, 'section-2');
    expect(command.cfi, 'epubcfi(/6/4)');
  });

  test('page commands carry no stale location payload', () {
    const command = ReaderNavigationCommand.nextPage(id: 9);

    expect(command.kind, ReaderNavigationKind.nextPage);
    expect(command.href, isNull);
    expect(command.ratio, isNull);
  });

  test('scroll commands preserve viewport and speed payloads', () {
    const scroll = ReaderNavigationCommand.scrollBy(id: 3, amount: 0.5);
    const automatic = ReaderNavigationCommand.startAutoScroll(
      id: 4,
      unit: 'screensPerMinute',
      speed: 0.8,
    );

    expect(scroll.kind, ReaderNavigationKind.scrollBy);
    expect(scroll.amount, 0.5);
    expect(automatic.kind, ReaderNavigationKind.startAutoScroll);
    expect(automatic.unit, 'screensPerMinute');
    expect(automatic.speed, 0.8);
  });
}
