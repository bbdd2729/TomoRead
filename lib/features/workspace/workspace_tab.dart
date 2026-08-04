import 'package:flutter/material.dart';

enum AppDestination {
  library,
  chat,
  notes,
  skills,
  statistics,
  settings,
  reader,
}

class WorkspaceTab {
  const WorkspaceTab({
    required this.id,
    required this.title,
    required this.destination,
    this.bookId,
    this.bookFormat,
    this.closable = false,
  });

  final String id;
  final String title;
  final AppDestination destination;
  final String? bookId;
  final String? bookFormat;
  final bool closable;
}

const navigationDestinations = [
  AppDestination.library,
  AppDestination.chat,
  AppDestination.notes,
  AppDestination.skills,
  AppDestination.statistics,
];

const mobileNavigationDestinations = [
  AppDestination.library,
  AppDestination.chat,
  AppDestination.notes,
  AppDestination.statistics,
  AppDestination.settings,
];

String destinationLabel(AppDestination destination) => switch (destination) {
  AppDestination.library => '书库',
  AppDestination.chat => '对话',
  AppDestination.notes => '笔记',
  AppDestination.skills => '技能',
  AppDestination.statistics => '阅读统计',
  AppDestination.settings => '设置',
  AppDestination.reader => '阅读器',
};

IconData destinationIcon(AppDestination destination) => switch (destination) {
  AppDestination.library => Icons.local_library,
  AppDestination.chat => Icons.forum,
  AppDestination.notes => Icons.sticky_note_2,
  AppDestination.skills => Icons.extension,
  AppDestination.statistics => Icons.bar_chart,
  AppDestination.settings => Icons.settings,
  AppDestination.reader => Icons.menu_book,
};
