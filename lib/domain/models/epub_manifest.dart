class EpubManifest {
  const EpubManifest({
    required this.opfPath,
    required this.version,
    required this.direction,
    required this.spine,
    required this.toc,
  });

  final String opfPath;
  final String version;
  final ReadingDirection direction;
  final List<EpubSpineItem> spine;
  final List<EpubTocItem> toc;

  int get chapterCount => spine.length;

  Map<String, Object> toJson() => {
    'opfPath': opfPath,
    'version': version,
    'direction': direction.name,
    'spine': spine.map((item) => item.toJson()).toList(),
    'toc': toc.map((item) => item.toJson()).toList(),
  };

  factory EpubManifest.fromJson(Map<String, Object?> json) => EpubManifest(
    opfPath: json['opfPath']! as String,
    version: json['version']! as String,
    direction: ReadingDirection.values.byName(json['direction']! as String),
    spine: (json['spine']! as List<Object?>)
        .map((item) => EpubSpineItem.fromJson(item! as Map<String, Object?>))
        .toList(),
    toc: (json['toc']! as List<Object?>)
        .map((item) => EpubTocItem.fromJson(item! as Map<String, Object?>))
        .toList(),
  );
}

int? epubSpineIndexForHref(EpubManifest manifest, String href) {
  final withoutFragment = href.split('#').first.split('?').first;
  final exactIndex = manifest.spine.indexWhere(
    (item) => item.href.split('#').first.split('?').first == withoutFragment,
  );
  if (exactIndex >= 0) return exactIndex;

  final targetPath = _normalizedEpubPath(href);
  final normalizedIndex = manifest.spine.indexWhere(
    (item) => _normalizedEpubPath(item.href) == targetPath,
  );
  return normalizedIndex < 0 ? null : normalizedIndex;
}

String _normalizedEpubPath(String href) {
  final uri = Uri.tryParse(href);
  final path = uri?.path.isNotEmpty == true
      ? uri!.path
      : href.split('#').first.split('?').first;
  return path.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '');
}

enum ReadingDirection { ltr, rtl }

class EpubSpineItem {
  const EpubSpineItem({
    required this.id,
    required this.href,
    required this.linear,
  });

  final String id;
  final String href;
  final bool linear;

  Map<String, Object> toJson() => {'id': id, 'href': href, 'linear': linear};

  factory EpubSpineItem.fromJson(Map<String, Object?> json) => EpubSpineItem(
    id: json['id']! as String,
    href: json['href']! as String,
    linear: json['linear']! as bool,
  );
}

class EpubTocItem {
  const EpubTocItem({
    required this.title,
    required this.href,
    required this.spineIndex,
    this.children = const [],
  });

  final String title;
  final String href;
  final int spineIndex;
  final List<EpubTocItem> children;

  Map<String, Object> toJson() => {
    'title': title,
    'href': href,
    'spineIndex': spineIndex,
    'children': children.map((item) => item.toJson()).toList(),
  };

  factory EpubTocItem.fromJson(Map<String, Object?> json) => EpubTocItem(
    title: json['title']! as String,
    href: json['href']! as String,
    spineIndex: json['spineIndex']! as int,
    children: (json['children']! as List<Object?>)
        .map((item) => EpubTocItem.fromJson(item! as Map<String, Object?>))
        .toList(),
  );
}
