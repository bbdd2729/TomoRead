enum VisualArtifactKind { wordCloud, mindMap }

enum VisualArtifactScope { currentChapter, readChapters, wholeBook }

class ArtifactCitation {
  const ArtifactCitation({
    required this.bookId,
    required this.href,
    required this.locator,
    required this.chapterIndex,
    required this.chapterTitle,
    required this.quote,
  });

  final String bookId;
  final String href;
  final String locator;
  final int chapterIndex;
  final String chapterTitle;
  final String quote;

  Map<String, Object?> toJson() => {
    'bookId': bookId,
    'href': href,
    'locator': locator,
    'chapterIndex': chapterIndex,
    'chapterTitle': chapterTitle,
    'quote': quote,
  };

  factory ArtifactCitation.fromJson(Map<String, Object?> value) =>
      ArtifactCitation(
        bookId: value['bookId'] as String? ?? '',
        href: value['href'] as String? ?? '',
        locator: value['locator'] as String? ?? '',
        chapterIndex: (value['chapterIndex'] as num?)?.toInt() ?? 0,
        chapterTitle: value['chapterTitle'] as String? ?? '',
        quote: value['quote'] as String? ?? '',
      );
}

class VisualArtifact {
  const VisualArtifact({
    required this.id,
    required this.bookId,
    required this.kind,
    required this.scope,
    required this.title,
    required this.contentHash,
    required this.payloadJson,
    required this.createdAt,
  });

  final String id;
  final String bookId;
  final VisualArtifactKind kind;
  final VisualArtifactScope scope;
  final String title;
  final String contentHash;
  final String payloadJson;
  final DateTime createdAt;
}

class WordCloudTerm {
  const WordCloudTerm({required this.term, required this.frequency});

  final String term;
  final int frequency;

  Map<String, Object> toJson() => {'term': term, 'frequency': frequency};

  factory WordCloudTerm.fromJson(Map<String, Object?> value) => WordCloudTerm(
    term: value['term']! as String,
    frequency: value['frequency']! as int,
  );
}

class WordCloudPayload {
  const WordCloudPayload({
    required this.terms,
    required this.scope,
    required this.layoutSeed,
    required this.contentHash,
    required this.tokenizerVersion,
    required this.stopwordVersion,
    required this.generatedAt,
    this.colorPalette = defaultWordCloudPalette,
  });

  final List<WordCloudTerm> terms;
  final VisualArtifactScope scope;
  final int layoutSeed;
  final String contentHash;
  final int tokenizerVersion;
  final int stopwordVersion;
  final DateTime generatedAt;
  final List<String> colorPalette;

  Map<String, Object?> toJson() => {
    'terms': terms.map((term) => term.toJson()).toList(),
    'scope': scope.name,
    'layoutSeed': layoutSeed,
    'contentHash': contentHash,
    'tokenizerVersion': tokenizerVersion,
    'stopwordVersion': stopwordVersion,
    'generatedAt': generatedAt.toIso8601String(),
    'colorPalette': colorPalette,
  };

  WordCloudPayload copyWith({int? layoutSeed, List<String>? colorPalette}) =>
      WordCloudPayload(
        terms: terms,
        scope: scope,
        layoutSeed: layoutSeed ?? this.layoutSeed,
        contentHash: contentHash,
        tokenizerVersion: tokenizerVersion,
        stopwordVersion: stopwordVersion,
        generatedAt: generatedAt,
        colorPalette: colorPalette ?? this.colorPalette,
      );

  factory WordCloudPayload.fromJson(Map<String, Object?> value) =>
      WordCloudPayload(
        terms: (value['terms']! as List<Object?>)
            .cast<Map<String, Object?>>()
            .map(WordCloudTerm.fromJson)
            .toList(),
        scope: VisualArtifactScope.values.byName(value['scope']! as String),
        layoutSeed: (value['layoutSeed'] as num?)?.toInt() ?? 1,
        contentHash: value['contentHash']! as String,
        tokenizerVersion: (value['tokenizerVersion'] as num?)?.toInt() ?? 1,
        stopwordVersion: (value['stopwordVersion'] as num?)?.toInt() ?? 1,
        generatedAt: DateTime.parse(value['generatedAt']! as String),
        colorPalette:
            ((value['colorPalette'] as List<Object?>?) ??
                    defaultWordCloudPalette)
                .whereType<String>()
                .toList(),
      );
}

class MindMapNode {
  const MindMapNode({
    required this.id,
    required this.label,
    this.children = const [],
    this.citations = const [],
  });

  final String id;
  final String label;
  final List<MindMapNode> children;
  final List<ArtifactCitation> citations;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'children': children.map((child) => child.toJson()).toList(),
    'citations': citations.map((citation) => citation.toJson()).toList(),
  };

  factory MindMapNode.fromJson(Map<String, Object?> value) => MindMapNode(
    id: value['id']! as String,
    label: value['label']! as String,
    children: ((value['children'] as List<Object?>?) ?? const [])
        .cast<Map<String, Object?>>()
        .map(MindMapNode.fromJson)
        .toList(),
    citations: ((value['citations'] as List<Object?>?) ?? const [])
        .cast<Map<String, Object?>>()
        .map(ArtifactCitation.fromJson)
        .toList(),
  );
}

class MindMapPayload {
  const MindMapPayload({
    required this.title,
    required this.nodes,
    required this.scope,
    required this.contentHash,
    required this.generatedAt,
  });

  final String title;
  final List<MindMapNode> nodes;
  final VisualArtifactScope scope;
  final String contentHash;
  final DateTime generatedAt;

  Map<String, Object?> toJson() => {
    'title': title,
    'nodes': nodes.map((node) => node.toJson()).toList(),
    'scope': scope.name,
    'contentHash': contentHash,
    'generatedAt': generatedAt.toIso8601String(),
  };

  factory MindMapPayload.fromJson(Map<String, Object?> value) => MindMapPayload(
    title: value['title']! as String,
    nodes: (value['nodes']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(MindMapNode.fromJson)
        .toList(),
    scope: VisualArtifactScope.values.byName(value['scope']! as String),
    contentHash: value['contentHash']! as String,
    generatedAt: DateTime.parse(value['generatedAt']! as String),
  );
}

extension VisualArtifactScopeLabel on VisualArtifactScope {
  String get label => switch (this) {
    VisualArtifactScope.currentChapter => '当前章节',
    VisualArtifactScope.readChapters => '已读章节',
    VisualArtifactScope.wholeBook => '整本书',
  };
}

const defaultWordCloudPalette = <String>[
  '#A14B36',
  '#315B62',
  '#7A6332',
  '#6E4A74',
  '#37643D',
];
