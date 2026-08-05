import 'package:flutter/material.dart';

import '../../app/appearance.dart';
import '../../domain/models/library_book.dart';
import '../../domain/models/reading_settings.dart';
import '../chat/chat_page.dart';
import '../library/library_home_page.dart';
import '../notes/notes_page.dart';
import '../reader/pdf_reader_workspace.dart';
import '../reader/reader_workspace.dart';
import '../reader/text_reader_workspace.dart';
import '../settings/settings_page.dart';
import '../skills/skills_page.dart';
import '../statistics/statistics_page.dart';
import 'workspace_tab.dart';

class WorkspaceContent extends StatelessWidget {
  const WorkspaceContent({
    super.key,
    required this.destination,
    required this.appearance,
    required this.readingSettings,
    required this.readerBookId,
    required this.readerFormat,
    required this.readerTitle,
    required this.onExitReader,
    required this.onAppearanceChanged,
    required this.onReadingSettingsChanged,
    required this.onOpenBookDetails,
    required this.onOpenReader,
    required this.onOpenChat,
  });

  final AppDestination destination;
  final AppAppearance appearance;
  final ReadingSettings readingSettings;
  final String? readerBookId;
  final String? readerFormat;
  final String readerTitle;
  final VoidCallback onExitReader;
  final ValueChanged<AppAppearance> onAppearanceChanged;
  final ValueChanged<ReadingSettings> onReadingSettingsChanged;
  final ValueChanged<LibraryBook> onOpenBookDetails;
  final ValueChanged<LibraryBook> onOpenReader;
  final VoidCallback onOpenChat;

  @override
  Widget build(BuildContext context) {
    return switch (destination) {
      AppDestination.library => LibraryHomePage(
        onOpenBookDetails: onOpenBookDetails,
        onOpenReader: onOpenReader,
      ),
      AppDestination.reader =>
        readerFormat == 'pdf'
            ? PdfReaderWorkspace(
                key: ValueKey(readerBookId),
                bookId: readerBookId ?? '',
                title: readerTitle,
                readingSettings: readingSettings,
                onExitReader: onExitReader,
                onOpenChat: onOpenChat,
              )
            : readerFormat == 'txt' || readerFormat == 'markdown'
            ? TextReaderWorkspace(
                key: ValueKey(readerBookId),
                bookId: readerBookId ?? '',
                title: readerTitle,
                readingSettings: readingSettings,
                onExitReader: onExitReader,
                onOpenChat: onOpenChat,
              )
            : ReaderWorkspace(
                bookId: readerBookId ?? 'demo-reading-art',
                title: readerTitle,
                readingSettings: readingSettings,
                onExitReader: onExitReader,
                onOpenChat: onOpenChat,
              ),
      AppDestination.chat => ChatPage(onOpenReader: onOpenReader),
      AppDestination.notes => NotesPage(onOpenReader: onOpenReader),
      AppDestination.skills => SkillsPage(onOpenChat: onOpenChat),
      AppDestination.statistics => StatisticsPage(onOpenReader: onOpenReader),
      AppDestination.settings => SettingsPage(
        appearance: appearance,
        readingSettings: readingSettings,
        onAppearanceChanged: onAppearanceChanged,
        onReadingSettingsChanged: onReadingSettingsChanged,
      ),
    };
  }
}
