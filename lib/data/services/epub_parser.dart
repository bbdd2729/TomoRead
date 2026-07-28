import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as path;
import 'package:xml/xml.dart';

import '../../domain/models/epub_manifest.dart';

class EpubParseResult {
  const EpubParseResult({
    required this.title,
    required this.author,
    required this.description,
    required this.manifest,
    this.coverBytes,
    this.coverExtension,
  });

  final String title;
  final String author;
  final String? description;
  final EpubManifest manifest;
  final List<int>? coverBytes;
  final String? coverExtension;
}

class EpubParseException implements Exception {
  const EpubParseException(this.message);

  final String message;

  @override
  String toString() => 'EpubParseException: $message';
}

class EpubParser {
  const EpubParser();

  Future<EpubParseResult> parseFile(String filePath) async {
    final input = InputFileStream(filePath);
    try {
      final archive = ZipDecoder().decodeStream(input);
      return _parseArchive(
        archive,
        fallbackTitle: path.basenameWithoutExtension(filePath),
      );
    } on EpubParseException {
      rethrow;
    } catch (error) {
      throw EpubParseException('无法读取 EPUB 文件：$error');
    } finally {
      input.close();
    }
  }

  EpubParseResult parseBytes(
    List<int> bytes, {
    String fallbackTitle = '未命名书籍',
  }) {
    try {
      return _parseArchive(
        ZipDecoder().decodeBytes(bytes),
        fallbackTitle: fallbackTitle,
      );
    } on EpubParseException {
      rethrow;
    } catch (error) {
      throw EpubParseException('无法读取 EPUB 文件：$error');
    }
  }

  EpubParseResult _parseArchive(
    Archive archive, {
    required String fallbackTitle,
  }) {
    if (_findFile(archive, 'META-INF/encryption.xml') != null) {
      throw const EpubParseException('暂不支持受 DRM 保护的 EPUB 文件');
    }

    final opfPath = _findOpfPath(archive);
    final opfFile = _findFile(archive, opfPath);
    if (opfFile == null) {
      throw const EpubParseException('EPUB 中找不到 OPF 清单文件');
    }

    final document = _xml(opfFile);
    final package = document.rootElement;
    final metadata = _firstChild(package, 'metadata');
    final manifest = _firstChild(package, 'manifest');
    final spine = _firstChild(package, 'spine');
    if (metadata == null || manifest == null || spine == null) {
      throw const EpubParseException('EPUB 缺少 metadata、manifest 或 spine');
    }

    final opfDirectory = path.posix.dirname(opfPath);
    final manifestItems = <String, _ManifestItem>{};
    for (final item in _children(manifest, 'item')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id == null || href == null) continue;
      manifestItems[id] = _ManifestItem(
        href: _resolvePath(opfDirectory, href),
        properties: item.getAttribute('properties') ?? '',
        mediaType: item.getAttribute('media-type') ?? '',
      );
    }

    final spineItems = <EpubSpineItem>[];
    final spineIndexes = <String, int>{};
    for (final itemRef in _children(spine, 'itemref')) {
      final idRef = itemRef.getAttribute('idref');
      final item = idRef == null ? null : manifestItems[idRef];
      if (item == null) continue;
      final index = spineItems.length;
      spineItems.add(
        EpubSpineItem(
          id: idRef!,
          href: item.href,
          linear: itemRef.getAttribute('linear')?.toLowerCase() != 'no',
        ),
      );
      spineIndexes[item.href] = index;
    }
    if (spineItems.isEmpty) {
      throw const EpubParseException('EPUB 没有可阅读的章节');
    }

    final title = _firstText(metadata, 'title') ?? fallbackTitle;
    final author = _firstText(metadata, 'creator') ?? '';
    final description = _firstText(metadata, 'description');
    final coverPath = _findCoverPath(metadata, manifestItems);
    final coverFile = coverPath == null ? null : _findFile(archive, coverPath);

    final toc =
        _parseNav(archive, manifestItems, spineIndexes) ??
        _parseNcx(archive, spine, manifestItems, spineIndexes) ??
        spineItems
            .asMap()
            .entries
            .map(
              (entry) => EpubTocItem(
                title: '第 ${entry.key + 1} 章',
                href: entry.value.href,
                spineIndex: entry.key,
              ),
            )
            .toList();

    final direction = spine.getAttribute('page-progression-direction') == 'rtl'
        ? ReadingDirection.rtl
        : ReadingDirection.ltr;
    return EpubParseResult(
      title: title,
      author: author,
      description: description,
      manifest: EpubManifest(
        opfPath: opfPath,
        version: package.getAttribute('version') ?? '2.0',
        direction: direction,
        spine: spineItems,
        toc: toc,
      ),
      coverBytes: coverFile == null ? null : _bytes(coverFile),
      coverExtension: coverPath == null ? null : path.extension(coverPath),
    );
  }

  String _findOpfPath(Archive archive) {
    final container = _findFile(archive, 'META-INF/container.xml');
    if (container != null) {
      final rootFile = _xml(container).descendants
          .whereType<XmlElement>()
          .where((element) => element.name.local == 'rootfile')
          .firstOrNull;
      final opfPath = rootFile?.getAttribute('full-path');
      if (opfPath != null && _findFile(archive, opfPath) != null) {
        return opfPath;
      }
    }
    const commonPaths = [
      'content.opf',
      'OEBPS/content.opf',
      'OPS/content.opf',
      'EPUB/content.opf',
    ];
    for (final commonPath in commonPaths) {
      if (_findFile(archive, commonPath) != null) {
        return commonPath;
      }
    }
    for (final file in archive.files) {
      if (file.name.toLowerCase().endsWith('.opf')) {
        return file.name;
      }
    }
    throw const EpubParseException('EPUB 中找不到 OPF 清单文件');
  }

  List<EpubTocItem>? _parseNav(
    Archive archive,
    Map<String, _ManifestItem> manifestItems,
    Map<String, int> spineIndexes,
  ) {
    final navItem = manifestItems.values
        .where((item) => _propertyContains(item.properties, 'nav'))
        .firstOrNull;
    if (navItem == null) return null;
    final file = _findFile(archive, navItem.href);
    if (file == null) return null;
    try {
      final document = _xml(file);
      final nav = document.descendants
          .whereType<XmlElement>()
          .where((element) => element.name.local == 'nav')
          .where(
            (element) => element.attributes.any(
              (attribute) =>
                  attribute.name.local == 'type' &&
                  attribute.value.contains('toc'),
            ),
          )
          .firstOrNull;
      final list = nav == null ? null : _children(nav, 'ol').firstOrNull;
      if (list == null) return null;
      return _parseNavList(
        list,
        path.posix.dirname(navItem.href),
        spineIndexes,
      );
    } catch (_) {
      return null;
    }
  }

  List<EpubTocItem> _parseNavList(
    XmlElement list,
    String basePath,
    Map<String, int> spineIndexes,
  ) {
    final items = <EpubTocItem>[];
    for (final listItem in _children(list, 'li')) {
      final anchor = listItem.descendants
          .whereType<XmlElement>()
          .where((element) => element.name.local == 'a')
          .firstOrNull;
      final nestedList = _children(listItem, 'ol').firstOrNull;
      final href = anchor?.getAttribute('href');
      final resolvedHref = href == null ? '' : _resolvePath(basePath, href);
      final title = anchor?.innerText.trim();
      final children = nestedList == null
          ? const <EpubTocItem>[]
          : _parseNavList(nestedList, basePath, spineIndexes);
      if ((title == null || title.isEmpty) && children.isEmpty) continue;
      items.add(
        EpubTocItem(
          title: title != null && title.isNotEmpty ? title : '章节',
          href: resolvedHref,
          spineIndex: spineIndexes[_withoutFragment(resolvedHref)] ?? -1,
          children: children,
        ),
      );
    }
    return items;
  }

  List<EpubTocItem>? _parseNcx(
    Archive archive,
    XmlElement spine,
    Map<String, _ManifestItem> manifestItems,
    Map<String, int> spineIndexes,
  ) {
    final tocId = spine.getAttribute('toc');
    final ncxItem = tocId == null ? null : manifestItems[tocId];
    if (ncxItem == null) return null;
    final file = _findFile(archive, ncxItem.href);
    if (file == null) return null;
    try {
      final document = _xml(file);
      final navMap = document.descendants
          .whereType<XmlElement>()
          .where((element) => element.name.local == 'navMap')
          .firstOrNull;
      if (navMap == null) return null;
      return _parseNcxPoints(
        _children(navMap, 'navPoint'),
        path.posix.dirname(ncxItem.href),
        spineIndexes,
      );
    } catch (_) {
      return null;
    }
  }

  List<EpubTocItem> _parseNcxPoints(
    Iterable<XmlElement> points,
    String basePath,
    Map<String, int> spineIndexes,
  ) => points.map((point) {
    final label =
        point.descendants
            .whereType<XmlElement>()
            .where((element) => element.name.local == 'text')
            .firstOrNull
            ?.innerText
            .trim() ??
        '章节';
    final source =
        _children(point, 'content').firstOrNull?.getAttribute('src') ?? '';
    final href = _resolvePath(basePath, source);
    return EpubTocItem(
      title: label,
      href: href,
      spineIndex: spineIndexes[_withoutFragment(href)] ?? -1,
      children: _parseNcxPoints(
        _children(point, 'navPoint'),
        basePath,
        spineIndexes,
      ),
    );
  }).toList();

  String? _findCoverPath(
    XmlElement metadata,
    Map<String, _ManifestItem> items,
  ) {
    final coverId = metadata.descendants
        .whereType<XmlElement>()
        .where(
          (element) =>
              element.name.local == 'meta' &&
              element.getAttribute('name') == 'cover',
        )
        .firstOrNull
        ?.getAttribute('content');
    if (coverId != null) return items[coverId]?.href;
    final epub3Cover = items.values
        .where((item) => _propertyContains(item.properties, 'cover-image'))
        .firstOrNull;
    if (epub3Cover != null) return epub3Cover.href;
    return items.values
        .where(
          (item) =>
              item.mediaType.startsWith('image/') &&
              path.basename(item.href).toLowerCase().contains('cover'),
        )
        .firstOrNull
        ?.href;
  }

  ArchiveFile? _findFile(Archive archive, String fileName) =>
      archive.findFile(_withoutFragment(fileName));

  XmlDocument _xml(ArchiveFile file) =>
      XmlDocument.parse(utf8.decode(_bytes(file)));

  List<int> _bytes(ArchiveFile file) => file.content as List<int>;

  Iterable<XmlElement> _children(XmlElement element, String name) =>
      element.childElements.where((child) => child.name.local == name);

  XmlElement? _firstChild(XmlElement element, String name) =>
      _children(element, name).firstOrNull;

  String? _firstText(XmlElement element, String name) => element.descendants
      .whereType<XmlElement>()
      .where((child) => child.name.local == name)
      .map((child) => child.innerText.trim())
      .where((text) => text.isNotEmpty)
      .firstOrNull;

  String _resolvePath(String basePath, String href) {
    final rawPath = _withoutFragment(href).replaceAll('\\', '/');
    return path.posix.normalize(
      basePath == '.' ? rawPath : path.posix.join(basePath, rawPath),
    );
  }

  String _withoutFragment(String value) =>
      value.split('#').first.split('?').first;

  bool _propertyContains(String properties, String expected) =>
      properties.split(RegExp(r'\s+')).contains(expected);
}

class _ManifestItem {
  const _ManifestItem({
    required this.href,
    required this.properties,
    required this.mediaType,
  });

  final String href;
  final String properties;
  final String mediaType;
}
