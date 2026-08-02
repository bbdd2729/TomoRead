import 'dart:io';

import 'package:flutter/services.dart';

import '../../domain/models/reading_font.dart';

abstract interface class FontCatalogService {
  Future<List<SystemFontFamily>> listSystemFonts();
}

class PlatformFontCatalogService implements FontCatalogService {
  const PlatformFontCatalogService();

  static const _channel = MethodChannel('dev.tomoread/font_catalog');

  @override
  Future<List<SystemFontFamily>> listSystemFonts() async {
    if (Platform.isAndroid || Platform.isIOS) return _mobileFallbacks;
    try {
      final result = await _channel.invokeListMethod<Object?>('listFonts');
      final families = <String, Set<String>>{};
      for (final item in result ?? const []) {
        if (item is String) {
          final family = item.trim();
          if (family.isNotEmpty) families.putIfAbsent(family, () => {});
        } else if (item is Map) {
          final family = item['family']?.toString().trim() ?? '';
          if (family.isEmpty) continue;
          final styles = item['styles'];
          families.putIfAbsent(family, () => {}).addAll(
            styles is List
                ? styles.map((value) => value.toString())
                : const <String>[],
          );
        }
      }
      final resultFamilies = families.entries
          .map(
            (entry) => SystemFontFamily(
              family: entry.key,
              styles: entry.value.toList()..sort(),
            ),
          )
          .toList()
        ..sort(
          (left, right) => left.family.toLowerCase().compareTo(
            right.family.toLowerCase(),
          ),
        );
      return resultFamilies.isEmpty ? _desktopFallbacks : resultFamilies;
    } on MissingPluginException {
      return _desktopFallbacks;
    } on PlatformException {
      return _desktopFallbacks;
    }
  }

  static const _desktopFallbacks = <SystemFontFamily>[
    SystemFontFamily(family: 'Arial'),
    SystemFontFamily(family: 'Noto Sans'),
    SystemFontFamily(family: 'Noto Serif'),
  ];

  static const _mobileFallbacks = <SystemFontFamily>[
    SystemFontFamily(family: 'sans-serif'),
    SystemFontFamily(family: 'serif'),
    SystemFontFamily(family: 'monospace'),
  ];
}
