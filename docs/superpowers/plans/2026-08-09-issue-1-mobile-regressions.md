# Issue #1 Mobile Regressions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix narrow-screen control layout, persist library filters across application restarts, and remove blocking/duplicate work from EPUB chapter changes.

**Architecture:** A typed library workspace state is stored in the existing `app_settings` table and exposed through a dedicated Riverpod notifier. Compact layouts replace label-heavy segments with labeled dropdowns. A pure reader progress coordinator owns deduplication, debounce, and serialized persistence so the widget dispatches navigation immediately.

**Tech Stack:** Flutter, Flutter Hooks, Riverpod, sqflite, flutter_test.

---

### Task 1: Persist typed library workspace state

**Files:**
- Create: `lib/domain/models/library_workspace_state.dart`
- Modify: `lib/features/library/library_controls.dart:5-41`
- Modify: `lib/data/repositories/settings_repository.dart:5-72`
- Test: `test/domain/models/library_workspace_state_test.dart`
- Test: `test/data/repositories/settings_repository_test.dart`

- [ ] **Step 1: Write failing model and repository tests**

```dart
test('round-trips selected library workspace state', () async {
  const expected = LibraryWorkspaceState(
    formatFilter: LibraryFormatFilter.text,
    sort: LibrarySort.progress,
    viewMode: LibraryViewMode.list,
    category: 'Markdown',
    tag: 'reference',
    favoritesOnly: true,
  );

  await settings.saveLibraryWorkspaceState(expected);

  expect(await settings.loadLibraryWorkspaceState(), expected);
});

test('invalid persisted values use defaults', () {
  expect(
    LibraryWorkspaceState.fromJson({
      'version': 1,
      'formatFilter': 'unknown',
      'sort': 'unknown',
      'viewMode': 'unknown',
      'category': 'Markdown',
      'tag': '   ',
      'favoritesOnly': 'invalid',
    }),
    const LibraryWorkspaceState(category: 'Markdown'),
  );
});
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run: `flutter test test/domain/models/library_workspace_state_test.dart test/data/repositories/settings_repository_test.dart`

Expected: FAIL because the state type and repository methods do not exist.

- [ ] **Step 3: Create the typed state model**

Move `LibraryFormatFilter`, `LibrarySort`, `LibraryViewMode`, `allCategoriesFilter`, and `uncategorizedCategoryFilter` from `library_controls.dart` to the new domain model. Keep only UI label extensions in the widget file.

```dart
class LibraryWorkspaceState {
  const LibraryWorkspaceState({
    this.formatFilter = LibraryFormatFilter.all,
    this.sort = LibrarySort.recent,
    this.viewMode = LibraryViewMode.grid,
    this.category = allCategoriesFilter,
    this.tag,
    this.favoritesOnly = false,
  });

  static const version = 1;
  final LibraryFormatFilter formatFilter;
  final LibrarySort sort;
  final LibraryViewMode viewMode;
  final String category;
  final String? tag;
  final bool favoritesOnly;

  Map<String, Object?> toJson() => {
    'version': version,
    'formatFilter': formatFilter.name,
    'sort': sort.name,
    'viewMode': viewMode.name,
    'category': category,
    'tag': tag,
    'favoritesOnly': favoritesOnly,
  };
}
```

Implement `fromJson`, `copyWith`, equality, and `normalizedForOptions(categories:, tags:)`. `fromJson` accepts only version 1 maps, falls back per invalid field, and trims blank tags to `null`. Normalization retains the two special category constants, otherwise falls back to all categories and clears absent tags.

- [ ] **Step 4: Add repository methods without a schema change**

Import the domain model in `SettingsRepository`. Store it under the existing `library_workspace` key; do not change `AppDatabase.schemaVersion`.

```dart
Future<LibraryWorkspaceState> loadLibraryWorkspaceState() async {
  final database = await _database.database;
  final rows = await database.query(
    'app_settings',
    columns: ['setting_value'],
    where: 'setting_key = ?',
    whereArgs: const ['library_workspace'],
    limit: 1,
  );
  if (rows.isEmpty) return const LibraryWorkspaceState();
  try {
    return LibraryWorkspaceState.fromJson(
      jsonDecode(rows.single['setting_value']! as String),
    );
  } on FormatException {
    return const LibraryWorkspaceState();
  }
}

Future<void> saveLibraryWorkspaceState(LibraryWorkspaceState state) =>
    _put('library_workspace', jsonEncode(state.toJson()));
```

- [ ] **Step 5: Run the focused tests**

Run: `flutter test test/domain/models/library_workspace_state_test.dart test/data/repositories/settings_repository_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/domain/models/library_workspace_state.dart lib/features/library/library_controls.dart lib/data/repositories/settings_repository.dart test/domain/models/library_workspace_state_test.dart test/data/repositories/settings_repository_test.dart
git commit -m "feat(library): persist workspace filters"
```

### Task 2: Restore validated filters through Riverpod

**Files:**
- Modify: `lib/app/providers.dart:523-561`
- Modify: `lib/features/library/library_home_page.dart:1-55,250-340`
- Test: `test/features/library/library_workspace_state_test.dart`

- [ ] **Step 1: Write the failing provider reload test**

```dart
test('restores workspace state in a new provider container', () async {
  final database = AppDatabase.inMemory();
  final repository = SettingsRepository(database);
  final first = ProviderContainer(
    overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(() async { first.dispose(); await database.close(); });

  await first.read(libraryWorkspaceStateProvider.future);
  await first.read(libraryWorkspaceStateProvider.notifier).update(
    const LibraryWorkspaceState(category: 'Markdown'),
  );

  final second = ProviderContainer(
    overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(second.dispose);
  expect(
    (await second.read(libraryWorkspaceStateProvider.future)).category,
    'Markdown',
  );
});
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `flutter test test/features/library/library_workspace_state_test.dart`

Expected: FAIL because `libraryWorkspaceStateProvider` is missing.

- [ ] **Step 3: Add the dedicated notifier**

Add this provider close to `appSettingsProvider`; keep it separate from `StoredSettings` so a filter update does not rebuild global appearance state.

```dart
final libraryWorkspaceStateProvider =
    AsyncNotifierProvider<LibraryWorkspaceStateNotifier, LibraryWorkspaceState>(
      LibraryWorkspaceStateNotifier.new,
    );

class LibraryWorkspaceStateNotifier
    extends AsyncNotifier<LibraryWorkspaceState> {
  @override
  Future<LibraryWorkspaceState> build() =>
      ref.watch(settingsRepositoryProvider).loadLibraryWorkspaceState();

  Future<void> update(LibraryWorkspaceState next) async {
    state = AsyncData(next);
    await ref.read(settingsRepositoryProvider).saveLibraryWorkspaceState(next);
  }
}
```

- [ ] **Step 4: Replace local library filter hooks**

In `LibraryHomePage`, retain only `searchQuery` and transient multi-selection hooks. Read `libraryWorkspaceStateProvider`, use a default state while loading, and use the workspace state for `filterAndSortBooks` and `LibraryControls`.

When book categories/tags arrive, normalize the state in a `useEffect`; call `unawaited(workspaceNotifier.update(normalized))` only when it differs. Do not write during widget build.

```dart
onCategoryChanged: (value) => unawaited(
  workspaceNotifier.update(workspace.copyWith(category: value)),
),
onTagChanged: (value) => unawaited(
  workspaceNotifier.update(
    value == null ? workspace.copyWith(clearTag: true) : workspace.copyWith(tag: value),
  ),
),
```

- [ ] **Step 5: Run persistence regression tests**

Run: `flutter test test/features/library/library_workspace_state_test.dart test/data/repositories/settings_repository_test.dart`

Expected: PASS, including stale category/tag normalization.

- [ ] **Step 6: Commit**

```bash
git add lib/app/providers.dart lib/features/library/library_home_page.dart test/features/library/library_workspace_state_test.dart
git commit -m "fix(library): restore selected filters"
```

### Task 3: Replace compact text-wrapping controls

**Files:**
- Modify: `lib/features/library/library_controls.dart:95-282`
- Modify: `lib/features/settings/settings_page.dart:145-207,620-682`
- Test: `test/features/library/library_controls_test.dart`
- Test: `test/features/settings/settings_page_test.dart`

- [ ] **Step 1: Write failing 360px/125% text-scale widget tests**

```dart
testWidgets('library controls use a compact format selector', (tester) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(_appWithScale(
    const TextScaler.linear(1.25),
    LibraryControls(
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
  ));

  expect(tester.takeException(), isNull);
  expect(find.byKey(const Key('library-format-selector')), findsOneWidget);
  expect(find.byType(SegmentedButton<LibraryFormatFilter>), findsNothing);
});
```

The settings test must assert that `settings-section-selector` is visible in compact mode and that the top-level selector is not wrapped in a horizontal `SingleChildScrollView`.

- [ ] **Step 2: Run the tests and verify they fail**

Run: `flutter test test/features/library/library_controls_test.dart test/features/settings/settings_page_test.dart`

Expected: FAIL because compact selector keys and layout branches do not exist.

- [ ] **Step 3: Add compact library controls**

Keep the existing wide `Wrap` at widths >= 600. Below 600, use a vertical group: full-width search, full-width format dropdown, full-width sort dropdown, full-width category dropdown, then a wrapping favorite/view row. Dropdowns use `isExpanded: true`.

```dart
DropdownButtonFormField<LibraryFormatFilter>(
  key: const Key('library-format-selector'),
  value: formatFilter,
  isExpanded: true,
  decoration: const InputDecoration(labelText: '格式'),
  items: [
    for (final value in LibraryFormatFilter.values)
      DropdownMenuItem(
        value: value,
        child: Text(value.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
  ],
  onChanged: (value) {
    if (value != null) onFormatChanged(value);
  },
)
```

Use one-line/ellipsis labels in every dropdown and wide-mode `ButtonSegment`. Cap tag chip label width at 180 logical pixels with a `ConstrainedBox`; retain 44dp minimum touch targets.

- [ ] **Step 4: Replace compact settings segments**

Add private `_SettingsSectionSelector` with key `settings-section-selector`, an expanded dropdown, and one-line icon-plus-label choices. Replace only the compact page's horizontal `SegmentedButton`; preserve `_SettingsNavigation` for desktop. In `_ReadingSettings`, use a `LayoutBuilder` to replace label-bearing segmented layout/page-transition controls with equivalent dropdowns below 480px.

- [ ] **Step 5: Run compact UI tests**

Run: `flutter test test/features/library/library_controls_test.dart test/features/settings/settings_page_test.dart`

Expected: PASS without a Flutter overflow exception at 360px and 125% scale.

- [ ] **Step 6: Commit**

```bash
git add lib/features/library/library_controls.dart lib/features/settings/settings_page.dart test/features/library/library_controls_test.dart test/features/settings/settings_page_test.dart
git commit -m "fix(ui): adapt compact controls"
```

### Task 4: Coalesce reader progress writes outside the navigation path

**Files:**
- Create: `lib/features/reader/reader_progress_coordinator.dart`
- Modify: `lib/features/reader/reader_workspace.dart:390-465`
- Test: `test/features/reader/reader_progress_coordinator_test.dart`

- [ ] **Step 1: Write failing coordinator tests**

```dart
test('deduplicates nearby relocations and persists the latest snapshot', () async {
  final writes = <PendingReaderProgress>[];
  final reports = <PendingReaderProgress>[];
  final coordinator = ReaderProgressCoordinator(
    persist: (value) async => writes.add(value),
    report: reports.add,
    debounce: Duration.zero,
  );
  addTearDown(coordinator.dispose);

  coordinator.capture(const PendingReaderProgress(chapterIndex: 1, progress: .500, locator: '1:.500'));
  coordinator.capture(const PendingReaderProgress(chapterIndex: 1, progress: .501, locator: '1:.501'));
  coordinator.capture(const PendingReaderProgress(chapterIndex: 1, progress: .750, locator: '1:.750'));
  await coordinator.flush();

  expect(reports, hasLength(2));
  expect(writes.single.locator, '1:.750');
});
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `flutter test test/features/reader/reader_progress_coordinator_test.dart`

Expected: FAIL because `ReaderProgressCoordinator` does not exist.

- [ ] **Step 3: Implement the coordinator**

The constructor takes `persist`, `report`, and injectable `debounce`. `capture` keeps the newest snapshot, only reports when the chapter changes or progress differs by at least 0.005, and resets a timer. `flush` cancels the timer, removes the pending snapshot, and appends its write to a private serial tail.

```dart
Future<void> _enqueue(PendingReaderProgress pending) {
  final write = _writeTail.then((_) => persist(pending));
  _writeTail = write.catchError((_) {});
  return write;
}
```

`dispose` cancels the timer and begins a final flush without any widget or provider access.

- [ ] **Step 4: Integrate it into the reader**

Create the coordinator with `useMemoized`; call the app-scoped `libraryBooksController.reportReadingPosition` in its report callback and `updateReadingPosition` in its persist callback. Replace `pendingProgressWrite` and `progressWriteTimer` with `progressCoordinator.capture(pending)`.

On lifecycle background and reader dispose, call `unawaited(progressCoordinator.flush())`. In `selectChapter`, replace `await flushPendingProgress()` with `unawaited(progressCoordinator.flush())`; do not delay the new `goToLocation` command for SQLite.

- [ ] **Step 5: Run reader persistence tests**

Run: `flutter test test/features/reader/reader_progress_coordinator_test.dart test/app/library_books_notifier_test.dart`

Expected: PASS with only the final location persisted for the relocation burst.

- [ ] **Step 6: Commit**

```bash
git add lib/features/reader/reader_progress_coordinator.dart lib/features/reader/reader_workspace.dart test/features/reader/reader_progress_coordinator_test.dart
git commit -m "fix(reader): coalesce progress writes"
```

### Task 5: Gate repeated navigation and collect safe timing diagnostics

**Files:**
- Modify: `lib/features/reader/reader_navigation_command.dart`
- Modify: `lib/features/reader/reader_workspace.dart:991-1020,1304-1380`
- Test: `test/features/reader/reader_navigation_gate_test.dart`

- [ ] **Step 1: Write the failing gate test**

```dart
test('allows one navigation command until it completes', () {
  final gate = ReaderNavigationGate();
  expect(gate.tryStart(41), isTrue);
  expect(gate.tryStart(42), isFalse);
  gate.complete(41);
  expect(gate.tryStart(42), isTrue);
});
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `flutter test test/features/reader/reader_navigation_gate_test.dart`

Expected: FAIL because `ReaderNavigationGate` does not exist.

- [ ] **Step 3: Implement and wire the gate**

Add `ReaderNavigationGate` next to `ReaderNavigationCommand`; it stores one active id, and only matching `complete`/ `fail` calls clear it. Use `useRef(ReaderNavigationGate())` in the workspace. Before emitting `goToLocation`, `nextPage`, or `previousPage`, allocate the command id and return if `tryStart(id)` is false. In `onNavigationCommandFinished`, always complete the gate before clearing the matching hook state.

At dispatch, record `AppDiagnostics.info` with command id, chapter index, and monotonic start time. At the first matching relocation and command completion/failure, record elapsed milliseconds. Do not log text, CFI values, annotations, or secrets.

- [ ] **Step 4: Run focused reader tests and analyzer**

Run: `flutter test test/features/reader/reader_navigation_gate_test.dart test/features/reader/reader_progress_coordinator_test.dart test/features/reader/reader_runtime_controller_test.dart`

Expected: PASS.

Run: `flutter analyze lib test`

Expected: no diagnostics.

- [ ] **Step 5: Commit**

```bash
git add lib/features/reader/reader_navigation_command.dart lib/features/reader/reader_workspace.dart test/features/reader/reader_navigation_gate_test.dart
git commit -m "fix(reader): gate duplicate navigation"
```

### Task 6: Verify locally, merge into main, and let CI build Android

**Files:**
- Modify: no source files expected

- [ ] **Step 1: Format modified Dart sources and tests**

Run: `dart format lib/domain/models/library_workspace_state.dart lib/data/repositories/settings_repository.dart lib/app/providers.dart lib/features/library/library_controls.dart lib/features/library/library_home_page.dart lib/features/settings/settings_page.dart lib/features/reader/reader_progress_coordinator.dart lib/features/reader/reader_navigation_command.dart lib/features/reader/reader_workspace.dart test/domain/models/library_workspace_state_test.dart test/data/repositories/settings_repository_test.dart test/features/library/library_workspace_state_test.dart test/features/library/library_controls_test.dart test/features/settings/settings_page_test.dart test/features/reader/reader_progress_coordinator_test.dart test/features/reader/reader_navigation_gate_test.dart`

Expected: formatter exits 0; inspect the resulting diff and keep only Issue #1 files.

- [ ] **Step 2: Run the full local quality gate**

Run: `flutter analyze lib test`

Expected: no diagnostics.

Run: `flutter test`

Expected: all tests pass.

- [ ] **Step 3: Verify integration scope**

Run: `git status --short; git log --oneline main..HEAD`

Expected: a clean worktree and only the design/spec and Issue #1 implementation commits.

- [ ] **Step 4: Merge and push main**

```bash
git switch main
git pull --ff-only origin main
git merge --no-ff bbdd2729/issue-1 -m "fix: resolve Issue #1 mobile regressions"
git push origin main
```

Expected: the push starts the repository's GitHub Actions workflow. Do not build Android locally; report the Actions run URL and status after the push.
