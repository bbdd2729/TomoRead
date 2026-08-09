# Issue #1 Mobile Regressions Design

**Issue:** https://github.com/bbdd2729/TomoRead/issues/1

## Goal

Fix the mobile layout, state-loss, and Android EPUB chapter-transition regressions reported in Issue #1 while preserving text accessibility and reliable reading-position recovery.

## Scope

This change covers four user-visible problems:

1. Buttons and control labels wrap or overflow on narrow Android screens.
2. Library selection state is lost when changing sections, backgrounding, or restarting the application.
3. Moving to the next EPUB chapter can stutter or crash on Android.
4. The compact settings section selector has horizontal scrolling without a discoverable affordance.

It does not change the reader's persisted reading-location format, restore open reader tabs after a cold start, or alter the desktop settings navigation.

## Design

### Persistent workspace state

Store a versioned workspace-state JSON value in the existing `app_settings` key/value table. It is backed up with other application settings, so a new database table or schema migration is unnecessary.

The state contains the library format filter, category filter, selected tag, sort order, favorites-only flag, and grid/list view choice. The active application destination is deliberately excluded: reopening directly into an arbitrary settings page is not required to preserve the reported library selection and would make startup less predictable. Reader tabs are also excluded because each book already restores from its saved reading position.

On startup the state is loaded before the library is shown. After books, categories, and tags are available, invalid category or tag values fall back respectively to the all-categories filter and no tag. User actions update in-memory state immediately and schedule durable persistence through the repository.

### Responsive controls

Retain the app-level text scale preference and make controls adapt to available width instead of globally reducing text size. Labels in constrained buttons and navigation controls remain one line; long labels use ellipsis or an icon-only presentation with a semantic label and tooltip.

The library control area remains horizontal at comfortable widths. On compact layouts it becomes an intentional vertical/wrapping filter group: format and tag controls can wrap, while category and sort controls take an available full row. All actions retain at least a 44dp touch target.

The compact settings page replaces its horizontally scrollable `SegmentedButton` with a single, labeled section selector that displays the current section and opens all four choices. The desktop left settings navigation is unchanged. Reader setting segmented controls that cannot fit will use the same compact selector treatment rather than wrapping labels.

### EPUB chapter navigation

Treat a chapter transition as a navigation transaction with two independent paths:

- **Interactive path:** stop auto-scroll/TTS as needed, coalesce duplicate next/previous requests, and send the runtime navigation command immediately. Never wait for SQLite before sending it.
- **Persistence path:** capture the newest stable relocation in memory, coalesce it in a single serialized writer, and persist it after a debounce. Backgrounding and reader disposal flush the last snapshot without mutating disposed widget state.

Runtime relocation messages are normalized and deduplicated using chapter/href plus meaningful position changes. Duplicate or near-identical messages do not trigger a fresh UI state update, activity record, or database write. A transition remains in flight until its completion or failure event; repeated boundary navigation inputs during that interval are ignored.

Instrumentation records timestamps for command dispatch, runtime completion, first relocation, and settled relocation, together with chapter identity. It is diagnostic-only and must not include book text or secrets.

## Error handling

- A failed workspace-state parse uses defaults and overwrites the invalid value only after a successful user interaction.
- A stale library category/tag is ignored rather than preventing the library from opening.
- A failed deferred progress write is logged and leaves the latest snapshot eligible for the next flush; it must not block the reader.
- A stale WebView callback after widget/provider disposal is ignored.
- A failed navigation command clears the in-flight guard so the reader remains usable.

## Verification

Automated coverage will include:

- widget layout at 360 logical pixels and 125% UI text scale, with no overflow and no multi-line constrained control labels;
- compact settings selector visibility and all section choices;
- library filters/view state surviving destination changes, reconstruction, and repository reload, including stale category/tag fallback;
- progress write coalescing, lifecycle/dispose flush, relocation deduplication, and in-flight navigation gating.

Manual Android verification uses a representative EPUB and consecutive chapter changes. Capture the diagnostic timing markers and compare command-to-first-relocation latency and memory behavior before and after the change. Local verification is limited to `flutter analyze lib test` and `flutter test`; Android artifact construction is performed by GitHub Actions after the branch is merged into `main` and pushed.

## Delivery

Implement on the current issue branch with focused commits. After local tests pass, merge the branch into `main`, push `main`, and use the GitHub Actions workflow as the Android build verification.
