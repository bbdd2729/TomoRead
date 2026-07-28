import 'package:flutter/material.dart';

import '../features/workspace/app_shell.dart';
import 'appearance.dart';

class TomoReadApp extends StatefulWidget {
  const TomoReadApp({super.key});

  @override
  State<TomoReadApp> createState() => _TomoReadAppState();
}

class _TomoReadAppState extends State<TomoReadApp> {
  AppAppearance _appearance = const AppAppearance();

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: _appearance.seed.color),
      useMaterial3: true,
    );
    final darkTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: _appearance.seed.color,
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    );

    return MaterialApp(
      title: 'TomoRead',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: darkTheme,
      themeMode: _appearance.mode,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(_appearance.textScale)),
        child: child ?? const SizedBox.shrink(),
      ),
      home: AppShell(
        appearance: _appearance,
        onAppearanceChanged: (appearance) {
          setState(() => _appearance = appearance);
        },
      ),
    );
  }
}
