import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/main.dart';

void main() {
  testWidgets('renders the desktop library workspace', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TomoReadApp());

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('书库'), findsWidgets);
    expect(find.text('继续阅读'), findsOneWidget);
    expect(find.text('全部书籍'), findsOneWidget);
  });

  testWidgets('opens a reader tab from a book card', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TomoReadApp());
    await tester.tap(find.byKey(const Key('book-阅读的技艺')));
    await tester.pumpAndSettle();

    expect(find.text('阅读的层次'), findsOneWidget);
    expect(find.text('目录'), findsOneWidget);
    expect(find.text('笔记与标注'), findsOneWidget);
  });

  testWidgets('switches theme color in settings', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TomoReadApp());
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('theme-green')));
    await tester.pump();

    expect(find.byKey(const Key('theme-green')), findsOneWidget);
    expect(find.byIcon(Icons.check), findsWidgets);
  });
}
