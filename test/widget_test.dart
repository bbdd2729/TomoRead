import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/main.dart';

void main() {
  testWidgets('renders the library home page on a desktop layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TomoReadApp());

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('书库'), findsWidgets);
    expect(find.text('继续阅读'), findsOneWidget);
    expect(find.text('全部书籍'), findsOneWidget);
    expect(find.text('阅读的技艺'), findsWidgets);
  });

  testWidgets('switches to the notes placeholder from the sidebar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TomoReadApp());
    await tester.tap(find.text('笔记').first);
    await tester.pumpAndSettle();

    expect(find.text('高亮、笔记和导出功能将在后续接入。'), findsOneWidget);
  });
}
