import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/domain/models/library_workspace_state.dart';
import 'package:tomoread/features/library/library_controls.dart';

void main() {
  testWidgets('uses compact selectors without overflowing at large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.25)),
        child: MaterialApp(
          home: Scaffold(
            body: LibraryControls(
              formatFilter: LibraryFormatFilter.all,
              sort: LibrarySort.recent,
              viewMode: LibraryViewMode.grid,
              categories: const [],
              tags: const [],
              category: allCategoriesFilter,
              tag: null,
              favoritesOnly: false,
              onQueryChanged: (_) {},
              onFormatChanged: (_) {},
              onSortChanged: (_) {},
              onViewModeChanged: (_) {},
              onCategoryChanged: (_) {},
              onTagChanged: (_) {},
              onFavoritesChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('library-format-selector')), findsOneWidget);
    expect(find.byType(SegmentedButton<LibraryFormatFilter>), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
