# Android Volume-Key Page Turning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow Android readers to turn backward and forward with hardware volume keys when a persisted global setting is enabled.

**Architecture:** A global `ReadingSettings.volumeKeyTurnsPage` preference is stored only with `reading_defaults`. A Kotlin plugin consumes Android volume keys while Flutter enables it and sends `up`/`down` events over an event channel. A Flutter lifecycle object maps events to existing reader navigation callbacks.

**Tech Stack:** Flutter/Dart, Riverpod, flutter_test, Kotlin, Android MethodChannel/EventChannel.

---

### Task 1: Add global preference and persistence

**Files:**
- Modify: `lib/domain/models/reading_settings.dart:24-77`
- Modify: `lib/data/repositories/settings_repository.dart:185-228`
- Modify: `test/data/repositories/settings_repository_test.dart:24-104`
- Create: `test/domain/models/reading_settings_test.dart`

- [ ] **Step 1: Write failing model and persistence tests**

    test('defaults volume-key page turning to disabled and copies the setting', () {
      const settings = ReadingSettings();
      expect(settings.volumeKeyTurnsPage, isFalse);
      expect(settings.copyWith(volumeKeyTurnsPage: true).volumeKeyTurnsPage, isTrue);
    });

    test('persists the global preference but not a book override', () async {
      await settings.saveReadingSettings(
        const ReadingSettings(volumeKeyTurnsPage: true),
      );
      await settings.saveBookOverride(
        const BookReadingOverride(bookId: 'book-a', settings: ReadingSettings()),
      );
      expect((await settings.load()).readingSettings.volumeKeyTurnsPage, isTrue);
      expect((await settings.loadBookOverride('book-a'))!.settings.volumeKeyTurnsPage,
          isFalse);
    });

- [ ] **Step 2: Run the tests and confirm red**

Run: `flutter test test/domain/models/reading_settings_test.dart test/data/repositories/settings_repository_test.dart`

Expected: compilation fails because `volumeKeyTurnsPage` is undefined.

- [ ] **Step 3: Add the field and serialize only global defaults**

    // ReadingSettings constructor, field, and copyWith
    this.volumeKeyTurnsPage = false,
    final bool volumeKeyTurnsPage;
    bool? volumeKeyTurnsPage,
    volumeKeyTurnsPage: volumeKeyTurnsPage ?? this.volumeKeyTurnsPage,

    // SettingsRepository._readingFromMap
    volumeKeyTurnsPage: value['volume_key_turns_page'] == true ||
        value['volume_key_turns_page'] == 1,

    // SettingsRepository._readingToMap only
    'volume_key_turns_page': settings.volumeKeyTurnsPage,

Do not add the field to `_readingOverrideToMap`; legacy JSON and book overrides load it as false. In both reader workspaces preserve the global setting when resolving an override:

    final effectiveSettings = (override?.settings ?? readingSettings).copyWith(
      volumeKeyTurnsPage: readingSettings.volumeKeyTurnsPage,
    );

- [ ] **Step 4: Run tests and commit**

Run: `flutter test test/domain/models/reading_settings_test.dart test/data/repositories/settings_repository_test.dart`

Expected: PASS.

    git add lib/domain/models/reading_settings.dart lib/data/repositories/settings_repository.dart test/domain/models/reading_settings_test.dart test/data/repositories/settings_repository_test.dart
    git commit -m "feat(reader): persist Android volume key preference"

### Task 2: Add Lumina-style native Android interception

**Files:**
- Create: `android/app/src/main/kotlin/com/tomoread/reader/tomoread/VolumeControlPlugin.kt`
- Modify: `android/app/src/main/kotlin/com/tomoread/reader/tomoread/MainActivity.kt:1-48`

- [ ] **Step 1: Write `VolumeControlPlugin`**

    class VolumeControlPlugin : FlutterPlugin, MethodChannel.MethodCallHandler,
        EventChannel.StreamHandler {
        private var eventSink: EventChannel.EventSink? = null
        private var isIntercepting = false

        override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
            MethodChannel(binding.binaryMessenger, "dev.tomoread/volume_control")
                .also { it.setMethodCallHandler(this) }
            EventChannel(binding.binaryMessenger, "dev.tomoread/volume_events")
                .also { it.setStreamHandler(this) }
        }

        fun processKeyDown(keyCode: Int): Boolean = isIntercepting && when (keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> { eventSink?.success("up"); true }
            KeyEvent.KEYCODE_VOLUME_DOWN -> { eventSink?.success("down"); true }
            else -> false
        }
    }

Implement `onMethodCall` for `enableInterception` and `disableInterception`; implement `onListen`, `onCancel`, and `onDetachedFromEngine` to manage the event sink and clear handlers. Interception remains consumed without a listener.

- [ ] **Step 2: Register and delegate in `MainActivity`**

    private val volumeControlPlugin = VolumeControlPlugin()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(volumeControlPlugin)
        // Preserve the existing import and wake-lock channel initialization.
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean =
        if (volumeControlPlugin.processKeyDown(keyCode)) true
        else super.onKeyDown(keyCode, event)

- [ ] **Step 3: Compile and commit**

Run: `flutter build apk --debug`

Expected: build produces `build\app\outputs\flutter-apk\app-debug.apk`.

    git add android/app/src/main/kotlin/com/tomoread/reader/tomoread/MainActivity.kt android/app/src/main/kotlin/com/tomoread/reader/tomoread/VolumeControlPlugin.kt
    git commit -m "feat(android): bridge volume key events to Flutter"

### Task 3: Add a testable Flutter event mapper

**Files:**
- Create: `lib/features/reader/volume_control_service.dart`
- Create: `lib/features/reader/volume_key_page_turner.dart`
- Create: `test/features/reader/volume_key_page_turner_test.dart`

- [ ] **Step 1: Write the failing mapping test**

    test('maps volume up/down and disables control on disposal', () async {
      final events = StreamController<VolumeKeyEvent>();
      final control = _FakeVolumeControl(events.stream);
      final turner = VolumeKeyPageTurner(control: control);
      var previous = 0;
      var next = 0;

      await turner.configure(
        enabled: true, onPrevious: () => previous++, onNext: () => next++,
      );
      events..add(VolumeKeyEvent.up)..add(VolumeKeyEvent.down);
      await Future<void>.delayed(Duration.zero);
      await turner.dispose();

      expect((previous, next), (1, 1));
      expect((control.enableCalls, control.disableCalls), (1, 1));
    });

- [ ] **Step 2: Run test and confirm red**

Run: `flutter test test/features/reader/volume_key_page_turner_test.dart`

Expected: compilation fails because `VolumeKeyPageTurner` is undefined.

- [ ] **Step 3: Implement the channel adapter and lifecycle mapper**

    enum VolumeKeyEvent { up, down }

    abstract interface class VolumeKeyControl {
      Stream<VolumeKeyEvent> get events;
      Future<void> enable();
      Future<void> disable();
    }

    class VolumeKeyPageTurner {
      VolumeKeyPageTurner({required this.control});
      final VolumeKeyControl control;
      StreamSubscription<VolumeKeyEvent>? _subscription;
      VoidCallback? _onPrevious;
      VoidCallback? _onNext;

      Future<void> configure({
        required bool enabled,
        required VoidCallback onPrevious,
        required VoidCallback onNext,
      }) async {
        _onPrevious = onPrevious;
        _onNext = onNext;
        if (!enabled) return control.disable();
        await control.enable();
        _subscription ??= control.events.listen((event) => switch (event) {
          VolumeKeyEvent.up => _onPrevious?.call(),
          VolumeKeyEvent.down => _onNext?.call(),
        });
      }

      Future<void> dispose() async {
        await _subscription?.cancel();
        await control.disable();
      }
    }

`VolumeControlService` implements `VolumeKeyControl` using `dev.tomoread/volume_control` and `dev.tomoread/volume_events`. It returns an empty stream outside Android/web, maps only `up` and `down`, and catches `PlatformException` while enabling or disabling.

- [ ] **Step 4: Run test and commit**

Run: `flutter test test/features/reader/volume_key_page_turner_test.dart`

Expected: PASS.

    git add lib/features/reader/volume_control_service.dart lib/features/reader/volume_key_page_turner.dart test/features/reader/volume_key_page_turner_test.dart
    git commit -m "feat(reader): map volume events to page navigation"

### Task 4: Expose Android setting and connect both readers

**Files:**
- Modify: `lib/features/settings/settings_page.dart:580-710`
- Modify: `lib/features/reader/reader_workspace.dart:150-220,1080-1120`
- Modify: `lib/features/reader/text_reader_workspace.dart:1200-1280`
- Modify: `test/widget_test.dart:24-80`

- [ ] **Step 1: Write failing Android-only visibility tests**

    testWidgets('shows volume-key page turning only on Android', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await pumpShell(tester);
      await tester.tap(find.byKey(const Key('settings-navigation')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('闃呰'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('volume-key-turns-page-setting')), findsOneWidget);
    });

Repeat using `TargetPlatform.windows` and `findsNothing`.

- [ ] **Step 2: Run test and confirm red**

Run: `flutter test test/widget_test.dart --plain-name "shows volume-key page turning only on Android"`

Expected: FAIL because the keyed switch is absent.

- [ ] **Step 3: Add switch and reader hooks**

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
      SwitchListTile(
        key: const Key('volume-key-turns-page-setting'),
        contentPadding: EdgeInsets.zero,
        value: settings.volumeKeyTurnsPage,
        onChanged: (value) =>
            onChanged(settings.copyWith(volumeKeyTurnsPage: value)),
        title: const Text('音量键翻页'),
        subtitle: const Text('开启后，音量上键上一页，音量下键下一页。'),
      ),

Create one hook-memoized `VolumeKeyPageTurner` in each reader, dispose it with `useEffect`, and configure it from the global setting:

    unawaited(volumeKeyTurner.configure(
      enabled: readingSettings.volumeKeyTurnsPage,
      onPrevious: goToPrevious,
      onNext: goToNext,
    ));

For the text reader, use its existing bounded `selectChapter(chapterIndex.value - 1)` and `selectChapter(chapterIndex.value + 1)` callbacks. Resolve visual settings with `override?.settings`, but retain `readingSettings.volumeKeyTurnsPage` so no per-book override can change the global behavior.

- [ ] **Step 4: Run focused tests and commit**

Run: `flutter test test/widget_test.dart test/features/reader/volume_key_page_turner_test.dart test/data/repositories/settings_repository_test.dart`

Expected: PASS.

    git add lib/features/settings/settings_page.dart lib/features/reader/reader_workspace.dart lib/features/reader/text_reader_workspace.dart test/widget_test.dart
    git commit -m "feat(reader): support Android volume key page turns"

### Task 5: Verify the complete feature

- [ ] **Step 1: Format changed Dart code**

Run: `dart format lib/domain/models/reading_settings.dart lib/data/repositories/settings_repository.dart lib/features/settings/settings_page.dart lib/features/reader/volume_control_service.dart lib/features/reader/volume_key_page_turner.dart lib/features/reader/reader_workspace.dart lib/features/reader/text_reader_workspace.dart test/domain/models/reading_settings_test.dart test/data/repositories/settings_repository_test.dart test/features/reader/volume_key_page_turner_test.dart test/widget_test.dart`

Expected: all listed files are formatted.

- [ ] **Step 2: Analyze, test, build, and inspect**

Run: `dart analyze; flutter test; flutter build apk --debug; git status --short`

Expected: no analyzer issues, all tests pass, the debug APK is generated, and the pre-existing Linux/Windows generated plugin edits remain unstaged.

## Plan Self-Review

- Task 1 covers defaults, persistence, legacy fallback, and global-only resolution.
- Task 2 mirrors Lumina's Android-native interception pattern.
- Tasks 3 and 4 cover safe cleanup, both reader types, and Android-only UI visibility.
- Task 5 verifies formatting, analysis, tests, and Android compilation. No iOS or desktop behavior is added.

