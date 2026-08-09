import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/domain/models/library_workspace_state.dart';

void main() {
  test('round-trips the selected library workspace state', () {
    const state = LibraryWorkspaceState(
      formatFilter: LibraryFormatFilter.text,
      sort: LibrarySort.progress,
      viewMode: LibraryViewMode.list,
      category: 'Markdown',
      tag: 'reference',
      favoritesOnly: true,
    );

    expect(LibraryWorkspaceState.fromJson(state.toJson()), state);
  });

  test('uses defaults for invalid values and clears blank tags', () {
    final state = LibraryWorkspaceState.fromJson({
      'version': 1,
      'formatFilter': 'unknown',
      'sort': 'unknown',
      'viewMode': 'unknown',
      'category': 'Markdown',
      'tag': '   ',
      'favoritesOnly': 'invalid',
    });

    expect(state, const LibraryWorkspaceState(category: 'Markdown'));
  });

  test('drops unavailable category and tag selections', () {
    const state = LibraryWorkspaceState(category: 'Markdown', tag: 'reference');

    expect(
      state.normalizedForOptions(
        categories: const ['Articles'],
        tags: const ['notes'],
      ),
      const LibraryWorkspaceState(),
    );
  });
}
