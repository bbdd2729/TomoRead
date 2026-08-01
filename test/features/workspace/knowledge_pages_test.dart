import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;
import 'package:tomoread/app/providers.dart';
import 'package:tomoread/domain/models/annotation_query.dart';
import 'package:tomoread/domain/models/library_book.dart';
import 'package:tomoread/domain/models/stats_models.dart';
import 'package:tomoread/features/chat/chat_controller.dart';
import 'package:tomoread/features/chat/chat_page.dart';
import 'package:tomoread/features/notes/notes_page.dart';
import 'package:tomoread/features/notes/notes_providers.dart';
import 'package:tomoread/features/statistics/statistics_page.dart';
import 'package:tomoread/features/statistics/statistics_providers.dart';

void main() {
  testWidgets('chat page exposes model setup and a usable composer', (
    tester,
  ) async {
    await _pumpPage(tester, const ChatPage(), [
      chatControllerProvider.overrideWith(_EmptyChatController.new),
      libraryBooksProvider.overrideWith(_EmptyLibraryBooksNotifier.new),
    ]);

    expect(find.text('尚未配置模型'), findsOneWidget);
    expect(find.byKey(const Key('chat-composer')), findsOneWidget);
    expect(find.text('配置模型'), findsOneWidget);
  });

  testWidgets('notes page renders a real empty state on compact layouts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(680, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpPage(tester, const NotesPage(), [
      annotationItemsProvider.overrideWith(
        (ref) async => const <AnnotationListItem>[],
      ),
      annotationFacetsProvider.overrideWith(
        (ref) async =>
            const AnnotationFacets(totalCount: 0, noteCount: 0, tags: []),
      ),
      libraryBooksProvider.overrideWith(_EmptyLibraryBooksNotifier.new),
    ]);

    expect(find.byKey(const Key('notes-search')), findsOneWidget);
    expect(find.text('还没有符合条件的笔记'), findsOneWidget);
  });

  testWidgets('statistics page reports that the selected period is empty', (
    tester,
  ) async {
    await _pumpPage(tester, const StatisticsPage(), [
      statsReportProvider.overrideWith((ref) async => _emptyStatsReport),
    ]);

    expect(find.text('阅读统计'), findsOneWidget);
    expect(find.textContaining('还没有阅读记录'), findsOneWidget);
    expect(find.text('日'), findsOneWidget);
    expect(find.text('周'), findsOneWidget);
  });
}

class _EmptyChatController extends ChatController {
  @override
  Future<ChatPageState> build() async =>
      const ChatPageState(threads: [], messages: []);
}

class _EmptyLibraryBooksNotifier extends LibraryBooksNotifier {
  @override
  Future<List<LibraryBook>> build() async => const [];
}

const _emptyStatsReport = StatsReport(
  dimension: StatsDimension.week,
  period: StatsPeriod(
    startKey: '2026-07-27',
    endKey: '2026-08-02',
    label: '7月27日 - 8月2日',
  ),
  summary: StatsSummary(
    activeMillis: 0,
    activeDays: 0,
    sessionCount: 0,
    booksTouched: 0,
    currentStreak: 0,
  ),
  timeline: [],
  topBooks: [],
  canGoNext: false,
);

Future<void> _pumpPage(
  WidgetTester tester,
  Widget page,
  List<Override> overrides,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(home: Scaffold(body: page)),
    ),
  );
  await tester.pump();
}
