# TomoRead

[![CI Build](https://github.com/bbdd2729/TomoRead/actions/workflows/ci.yml/badge.svg)](https://github.com/bbdd2729/TomoRead/actions/workflows/ci.yml)
[![Release](https://github.com/bbdd2729/TomoRead/actions/workflows/release.yml/badge.svg)](https://github.com/bbdd2729/TomoRead/actions/workflows/release.yml)

> Licensed under the [GNU General Public License v3.0 only](LICENSE).

> 中文版说明见 [docs/README.zh-CN.md](docs/README.zh-CN.md) / Read this in [Chinese](docs/README.zh-CN.md).

TomoRead is a cross-platform, local-first AI reader built with Flutter. It manages a personal library of EPUB/PDF/TXT/Markdown books, immersive reading, knowledge organization, and source-grounded AI conversations.

Books, reading positions, bookmarks, annotations, notes, conversations, and reading statistics are stored locally by default; model API keys are kept in system secure storage. When AI features are used, your input and any explicitly attached source text are sent to the configured model provider.

## Downloads

Grab the latest release from [GitHub Releases](https://github.com/bbdd2729/TomoRead/releases):

- Windows x64: download the ZIP, extract it, then run `tomoread.exe`
- Linux x64: download and extract the `tar.gz`, then run TomoRead from the bundle
- Android (experimental): APKs are split into `armeabi-v7a` (32-bit ARM) and `arm64-v8a` (64-bit ARM); an AAB is provided for store submission

> TomoRead is under active development. Before upgrading, consider keeping Markdown or JSON exports of your important notes.

## Current Capabilities

### Reader

- [x] Import local EPUB, PDF, TXT, and Markdown with file-hash deduplication and managed storage
- [x] EPUB metadata, cover art, table of contents, reading order, and chapter resource parsing
- [x] EPUB paginated and scrolling modes, single/double-column layouts, wheel and tap-to-turn navigation
- [x] Cross-format locator contracts so reopening or relayout returns to the same passage reliably
- [x] PDF rendering, outline navigation, and persistent reading positions
- [x] Immersive reading; toolbars and TOC/bookmark overlays never squeeze the content
- [x] Desktop resizable side panels; mobile drawers and bottom sheets
- [x] Global reading settings with per-book overrides
- [x] Fonts, font size, line height, margins, colors, reading direction, and page transitions
- [x] EPUB/TXT/Markdown text foreground coloring: English, digits, punctuation, quotes/parentheses, plus global and per-book custom terms
- [x] Bookmarks, highlights, colored annotations, notes, and a custom text-selection menu
- [x] PDF selection annotations, notes, and AI citations
- [x] Safe EPUB footnotes/image viewing, external-link policy, system TTS, and auto-scroll
- [x] Pomodoro focus sessions and reading statistics

### Library & Knowledge

- [x] Grid/list library, search, format filters, categories, tags, and favorites
- [x] Batch favorite, categorize, and delete
- [x] Book details with title, author, description, category, and tag editing
- [x] Global notes page: full-text search, book/color/tag filters, and sorting
- [x] Markdown note editing, preview, autosave, and jump back to the source
- [x] Export notes to Markdown or JSON
- [x] Reading statistics: day/week/month/year/all, reading time, active days, streaks, and book rankings

### AI Reading

- [x] OpenAI-compatible endpoint configuration and model switching
- [x] API keys kept in system secure storage, never in SQLite
- [x] General and per-book persistent conversations
- [x] Streaming replies, stop generation, Markdown rendering, and error recovery
- [x] Ask, explain, or summarize selected text with citations that link back to the source
- [x] Trusted content chunking, hybrid keyword/vector semantic search, and spoiler-safe reading context
- [x] Agent tool calls, thinking summaries, skills, and structured message parts
- [ ] Reading plans, study cards, and automatic note organization
- [ ] More model protocols and local model support

## Supported Platforms

| Platform | Status | Release artifacts |
| --- | --- | --- |
| Windows x64 | Primary support | ZIP |
| Linux x64 | Supported | `tar.gz` |
| Android | Experimental; builds and WebView performance are being improved | v7a APK, v8a APK, AAB (optional) |
| macOS | Planned | - |
| iOS | Planned | - |

Static analysis and tests run on every push and pull request, along with the configured platform builds. The manual `Release` workflow can build any combination of Windows, Linux, and Android.

## Architecture

The project uses Hooks Riverpod for state management, SQLite for structured business data, and system secure storage for model keys. Features are split by UI, domain model, and data-access responsibilities:

```text
lib/
├── app/                    # App entry, theme, global providers
├── domain/models/          # Books, locators, annotations, chat, reading activity models
├── data/
│   ├── database/           # SQLite schema and versioned migrations
│   ├── repositories/       # Library, annotations, chat, statistics data access
│   └── services/           # Import, EPUB, AI, export, reading-activity tracking
├── features/
│   ├── library/            # Library and book details
│   ├── reader/             # EPUB/PDF/TXT/Markdown reader workspaces
│   ├── chat/               # AI conversations
│   ├── notes/              # Global notes
│   ├── statistics/         # Reading statistics
│   ├── settings/           # App and reading settings
│   └── workspace/          # Responsive desktop/mobile navigation shell
└── shared/                 # Cross-feature reusable widgets
```

### Key Data Flows

1. The import service copies books into the app directory, hashes them, and parses EPUB/PDF metadata.
2. Repositories write library, reading positions, bookmarks, annotations, conversations, and reading sessions to SQLite.
3. Riverpod providers compose async repositories and services into page state; widgets handle presentation and interaction only.
4. EPUB renders with the bundled Foliate.js runtime inside a WebView; PDF uses `pdfrx`; renderers talk to Flutter through a unified locator model.
5. The reader records active reading activity into session tables, which the statistics service aggregates by date and book.
6. The AI gateway streams replies over an OpenAI-compatible SSE interface; conversations and citations are persisted independently.

More project documentation lives in [`docs/`](docs/):

- [Architecture](docs/architecture.md): the boundaries of local data, AI conversations, global notes, and reading statistics.
- [Reader capabilities and data boundaries](docs/reader-features.md): current format support, locators, annotations, display projection, and content-safety rules.
- [Product roadmap](docs/roadmap.md): priorities and delivery principles referenced against ColorTxt and ReadAny.

## Local Development

CI currently uses Flutter `3.44.8`. After preparing the Flutter native toolchain for your platform:

```bash
flutter pub get
flutter analyze lib test
flutter test
flutter run -d windows
```

Desktop builds:

```bash
flutter build windows --release
flutter build linux --release
```

Android is currently experimental:

```bash
flutter build apk --debug
```

## Release Process

1. Open **Actions > Release > Run workflow** in the repository.
2. Enter a version in `x.y.z` format, e.g. `0.2.0`, without a leading `v`.
3. Select the platforms to build. Android is off by default and does not affect desktop builds.
4. With `publish_release=false`, only Actions artifacts are produced; no tag or Release is created. Useful for testing a real build.
5. With `publish_release=true`, the workflow creates a Git tag like `v0.2.0` and a GitHub Release of the same name after a successful build, uploading all selected platform artifacts.
6. In publish mode, an existing tag is never overwritten; after fixing a failed release, re-run with the same version if the tag has not been created yet. Build-only mode may reuse any valid version number.

When Android is selected, configure these repository secrets:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Android produces:

- `TomoRead-x.y.z-android-armeabi-v7a.apk`
- `TomoRead-x.y.z-android-arm64-v8a.apk`
- `TomoRead-x.y.z-android.aab`

## Roadmap

### Done

- [x] Local EPUB/PDF library and book details
- [x] EPUB paginated/scrolling reading and PDF reading
- [x] Reading positions, bookmarks, annotations, notes, and settings persistence
- [x] Global notes, filtering, editing, export, and jump back to source
- [x] Reading-activity collection and multi-dimensional statistics
- [x] OpenAI-compatible AI chat with source citations, Agent tools, and secure key storage
- [x] EPUB/TXT token and custom-term foreground coloring (light/dark palettes, per-book overrides)
- [x] TXT/Markdown reading pipeline with safe display projection and coloring
- [x] System TTS, auto-scroll, PDF selection annotations, backup/restore, and storage diagnostics
- [x] Content chunking, hybrid keyword/vector semantic search, word clouds, and AI mind maps
- [x] Sync data model (revisions, tombstones, conflict) and a settings center
- [x] Windows/Linux builds and an optional platform Release workflow

### Near term

- [ ] Continue improving pagination, locators, and styling compatibility for complex EPUBs
- [ ] Polish Android builds, WebView rendering, and low-end device performance
- [ ] Add statistics export, reading goals, and richer trend analysis
- [ ] Improve AI context selection, conversation management, and error diagnostics

### Later

- [ ] WebDAV/cloud sync (the data contract is ready; the remote transport layer is missing)
- [ ] Whole-chapter/book search enhancement, reading guidance, and knowledge cards
- [ ] macOS and iOS support
- [ ] Extensible reading formats and AI provider interfaces
