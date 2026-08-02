import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/domain/models/reader_commands.dart';
import 'package:tomoread/features/reader/reader_auto_scroll.dart';

void main() {
  testWidgets('uses elapsed frame time and stops without further movement', (
    tester,
  ) async {
    final scrollController = ScrollController();
    final autoScrollController = ReaderAutoScrollController(
      preference: const AutoScrollPreference(speed: 60),
    );
    addTearDown(scrollController.dispose);
    addTearDown(autoScrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 200,
          child: ReaderAutoScrollRegion(
            controller: autoScrollController,
            scrollController: scrollController,
            lineExtent: 20,
            child: ListView.builder(
              controller: scrollController,
              itemExtent: 20,
              itemCount: 100,
              itemBuilder: (_, index) => Text('Line $index'),
            ),
          ),
        ),
      ),
    );

    autoScrollController.start();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(scrollController.offset, closeTo(20, 1));

    autoScrollController.stop();
    final stoppedOffset = scrollController.offset;
    await tester.pump(const Duration(seconds: 1));
    expect(scrollController.offset, stoppedOffset);
  });

  testWidgets('pointer input pauses automatic scrolling', (tester) async {
    final scrollController = ScrollController();
    final autoScrollController = ReaderAutoScrollController();
    addTearDown(scrollController.dispose);
    addTearDown(autoScrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 200,
          child: ReaderAutoScrollRegion(
            controller: autoScrollController,
            scrollController: scrollController,
            lineExtent: 20,
            child: ListView.builder(
              controller: scrollController,
              itemExtent: 20,
              itemCount: 100,
              itemBuilder: (_, index) => Text('Line $index'),
            ),
          ),
        ),
      ),
    );

    autoScrollController.start();
    await tester.pump();
    await tester.tap(find.text('Line 0'));

    expect(autoScrollController.active, isFalse);
    expect(
      autoScrollController.lastStopReason,
      AutoScrollStopReason.userInput,
    );
  });
}
