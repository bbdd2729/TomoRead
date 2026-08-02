import 'epub_manifest.dart';

const epubBridgeSchemaVersion = 1;

enum EpubInteractionKind {
  footnoteOpened,
  footnoteClosed,
  imageOpened,
  imageClosed,
  imageFailed,
  internalLink,
  internalBack,
  externalLinkRequested,
  blockedLink,
  interactionError,
}

class EpubInteractionLocator {
  const EpubInteractionLocator({
    required this.chapterIndex,
    required this.ratio,
    this.anchor,
    this.cfi,
  });

  final int chapterIndex;
  final double ratio;
  final String? anchor;
  final String? cfi;
}

class EpubInteraction {
  const EpubInteraction({
    required this.kind,
    required this.href,
    required this.locator,
    this.targetHref,
    this.resourceId,
    this.externalUri,
    this.message,
  });

  final EpubInteractionKind kind;
  final String href;
  final EpubInteractionLocator locator;
  final String? targetHref;
  final String? resourceId;
  final Uri? externalUri;
  final String? message;

  factory EpubInteraction.fromBridgeMessage(
    Map<Object?, Object?> json, {
    required EpubManifest manifest,
  }) {
    final version = json['bridgeVersion'];
    if (version is! num ||
        version.toInt() != epubBridgeSchemaVersion ||
        version != version.toInt()) {
      throw const FormatException('不支持的 EPUB 桥接协议版本。');
    }
    if (json['type'] != 'epubInteraction') {
      throw const FormatException('不是 EPUB 交互消息。');
    }

    final kind = _parseKind(_requiredString(json, 'action', maxLength: 64));
    final href = _requiredString(json, 'href', maxLength: 2048);
    final chapterIndex = epubSpineIndexForHref(manifest, href);
    if (chapterIndex == null) {
      throw const FormatException('EPUB 交互来源不在 spine 白名单中。');
    }
    final locator = _parseLocator(json['locator'], chapterIndex);
    final targetHref = _optionalString(json, 'targetHref', maxLength: 2048);
    if (targetHref != null &&
        epubSpineIndexForHref(manifest, targetHref) == null) {
      throw const FormatException('EPUB 交互目标不在 spine 白名单中。');
    }
    final resourceId = _optionalString(json, 'resourceId', maxLength: 2048);
    if (resourceId != null && !_isSafeResourceId(resourceId)) {
      throw const FormatException('EPUB resource ID 无效。');
    }
    final message = _optionalString(json, 'message', maxLength: 500);

    Uri? externalUri;
    if (kind == EpubInteractionKind.externalLinkRequested) {
      final value = _requiredString(json, 'externalUrl', maxLength: 4096);
      externalUri = Uri.tryParse(value);
      if (externalUri == null ||
          !const {'http', 'https'}.contains(externalUri.scheme) ||
          externalUri.host.isEmpty ||
          externalUri.userInfo.isNotEmpty) {
        throw const FormatException('外部链接协议或地址无效。');
      }
    }

    if (_requiresTargetHref(kind) && targetHref == null) {
      throw const FormatException('EPUB 交互缺少目标 href。');
    }
    if (_requiresResourceId(kind) && resourceId == null) {
      throw const FormatException('EPUB 交互缺少 resource ID。');
    }

    return EpubInteraction(
      kind: kind,
      href: href,
      locator: locator,
      targetHref: targetHref,
      resourceId: resourceId,
      externalUri: externalUri,
      message: message,
    );
  }

  static EpubInteractionKind _parseKind(String value) => switch (value) {
    'footnoteOpened' => EpubInteractionKind.footnoteOpened,
    'footnoteClosed' => EpubInteractionKind.footnoteClosed,
    'imageOpened' => EpubInteractionKind.imageOpened,
    'imageClosed' => EpubInteractionKind.imageClosed,
    'imageFailed' => EpubInteractionKind.imageFailed,
    'internalLink' => EpubInteractionKind.internalLink,
    'internalBack' => EpubInteractionKind.internalBack,
    'externalLinkRequested' => EpubInteractionKind.externalLinkRequested,
    'blockedLink' => EpubInteractionKind.blockedLink,
    'interactionError' => EpubInteractionKind.interactionError,
    _ => throw const FormatException('未知的 EPUB 交互类型。'),
  };

  static EpubInteractionLocator _parseLocator(
    Object? value,
    int expectedChapterIndex,
  ) {
    if (value is! Map) {
      throw const FormatException('EPUB 交互缺少 locator。');
    }
    final chapterIndex = value['chapterIndex'];
    final ratio = value['ratio'];
    if (chapterIndex is! num ||
        chapterIndex.toInt() != expectedChapterIndex ||
        chapterIndex != chapterIndex.toInt() ||
        ratio is! num ||
        !ratio.isFinite ||
        ratio < 0 ||
        ratio > 1) {
      throw const FormatException('EPUB 交互 locator 无效。');
    }
    return EpubInteractionLocator(
      chapterIndex: chapterIndex.toInt(),
      ratio: ratio.toDouble(),
      anchor: _optionalMapString(value, 'anchor', maxLength: 1024),
      cfi: _optionalMapString(value, 'cfi', maxLength: 4096),
    );
  }

  static bool _requiresTargetHref(EpubInteractionKind kind) => switch (kind) {
    EpubInteractionKind.footnoteOpened ||
    EpubInteractionKind.footnoteClosed ||
    EpubInteractionKind.internalLink ||
    EpubInteractionKind.internalBack => true,
    _ => false,
  };

  static bool _requiresResourceId(EpubInteractionKind kind) => switch (kind) {
    EpubInteractionKind.footnoteOpened ||
    EpubInteractionKind.footnoteClosed ||
    EpubInteractionKind.imageOpened ||
    EpubInteractionKind.imageClosed ||
    EpubInteractionKind.imageFailed => true,
    _ => false,
  };

  static bool _isSafeResourceId(String value) {
    if (value.trim() != value ||
        value.isEmpty ||
        value.codeUnits.any((unit) => unit < 0x20)) {
      return false;
    }
    final uri = Uri.tryParse(value.replaceAll('\\', '/'));
    if (uri == null || uri.hasScheme || uri.hasAuthority) return false;
    return !uri.pathSegments.contains('..');
  }

  static String _requiredString(
    Map<Object?, Object?> json,
    String key, {
    required int maxLength,
  }) {
    final value = json[key];
    if (value is! String ||
        value.isEmpty ||
        value.length > maxLength ||
        value.codeUnits.any((unit) => unit < 0x20)) {
      throw FormatException('EPUB 交互字段 $key 无效。');
    }
    return value;
  }

  static String? _optionalString(
    Map<Object?, Object?> json,
    String key, {
    required int maxLength,
  }) {
    final value = json[key];
    if (value == null) return null;
    if (value is! String ||
        value.isEmpty ||
        value.length > maxLength ||
        value.codeUnits.any((unit) => unit < 0x20)) {
      throw FormatException('EPUB 交互字段 $key 无效。');
    }
    return value;
  }

  static String? _optionalMapString(
    Map<Object?, Object?> json,
    String key, {
    required int maxLength,
  }) => _optionalString(json, key, maxLength: maxLength);
}
