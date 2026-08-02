import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../domain/models/visual_artifact.dart';
import 'word_cloud_layout_service.dart';

enum VisualArtifactExportFormat { json, markdown, svg, png }

extension VisualArtifactExportFormatLabel on VisualArtifactExportFormat {
  String get label => switch (this) {
    VisualArtifactExportFormat.json => 'JSON 数据',
    VisualArtifactExportFormat.markdown => 'Markdown 大纲',
    VisualArtifactExportFormat.svg => 'SVG 图片',
    VisualArtifactExportFormat.png => 'PNG 图片',
  };

  String get extension => switch (this) {
    VisualArtifactExportFormat.json => 'json',
    VisualArtifactExportFormat.markdown => 'md',
    VisualArtifactExportFormat.svg => 'svg',
    VisualArtifactExportFormat.png => 'png',
  };
}

class VisualArtifactExportService {
  const VisualArtifactExportService();

  Uint8List jsonBytes(VisualArtifact artifact) => Uint8List.fromList(
    utf8.encode(
      const JsonEncoder.withIndent('  ').convert({
        'id': artifact.id,
        'bookId': artifact.bookId,
        'kind': artifact.kind.name,
        'scope': artifact.scope.name,
        'title': artifact.title,
        'contentHash': artifact.contentHash,
        'createdAt': artifact.createdAt.toIso8601String(),
        'payload': jsonDecode(artifact.payloadJson),
      }),
    ),
  );

  Future<Uint8List> bytesFor(
    VisualArtifact artifact,
    VisualArtifactExportFormat format,
  ) => switch (format) {
    VisualArtifactExportFormat.json => Future.value(jsonBytes(artifact)),
    VisualArtifactExportFormat.markdown => Future.value(
      markdownBytes(artifact),
    ),
    VisualArtifactExportFormat.svg => Future.value(svgBytes(artifact)),
    VisualArtifactExportFormat.png => pngBytes(artifact),
  };

  Future<String?> saveWithPicker(
    VisualArtifact artifact,
    VisualArtifactExportFormat format,
  ) async {
    if (format == VisualArtifactExportFormat.markdown &&
        artifact.kind != VisualArtifactKind.mindMap) {
      throw const FormatException('只有思维导图支持 Markdown 导出。');
    }
    final bytes = await bytesFor(artifact, format);
    final fileName = '${_safeFileName(artifact.title)}.${format.extension}';
    final mobile = Platform.isAndroid || Platform.isIOS;
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '导出${artifact.kind == VisualArtifactKind.wordCloud ? '词云' : '思维导图'}',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: [format.extension],
      bytes: mobile ? bytes : null,
    );
    if (path == null) return null;
    if (!mobile) await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  Uint8List markdownBytes(VisualArtifact artifact) {
    if (artifact.kind != VisualArtifactKind.mindMap) {
      throw const FormatException('只有思维导图支持 Markdown 导出。');
    }
    final payload = MindMapPayload.fromJson(
      jsonDecode(artifact.payloadJson) as Map<String, Object?>,
    );
    final output = StringBuffer('# ${payload.title}\n\n');
    void append(MindMapNode node, int depth) {
      final indent = List.filled(depth, '  ').join();
      output.writeln('$indent- ${node.label}');
      for (final citation in node.citations) {
        final citationIndent = List.filled(depth + 1, '  ').join();
        output.writeln(
          '$citationIndent- 引用：${citation.chapterTitle} '
          '`${citation.locator}`',
        );
      }
      for (final child in node.children) append(child, depth + 1);
    }
    for (final node in payload.nodes) append(node, 0);
    return Uint8List.fromList(utf8.encode(output.toString()));
  }

  Uint8List svgBytes(
    VisualArtifact artifact, {
    double width = 1400,
    double height = 900,
  }) {
    final body = switch (artifact.kind) {
      VisualArtifactKind.wordCloud => _wordCloudSvg(
        WordCloudPayload.fromJson(
          jsonDecode(artifact.payloadJson) as Map<String, Object?>,
        ),
        width,
        height,
      ),
      VisualArtifactKind.mindMap => _mindMapSvg(
        MindMapPayload.fromJson(
          jsonDecode(artifact.payloadJson) as Map<String, Object?>,
        ),
        width,
        height,
      ),
    };
    return Uint8List.fromList(
      utf8.encode(
        '<svg xmlns="http://www.w3.org/2000/svg" width="$width" '
        'height="$height" viewBox="0 0 $width $height">'
        '<rect width="100%" height="100%" fill="#FAF8F2"/>$body</svg>',
      ),
    );
  }

  Future<Uint8List> pngBytes(
    VisualArtifact artifact, {
    int width = 1400,
    int height = 900,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = const Color(0xfffaf8f2),
    );
    switch (artifact.kind) {
      case VisualArtifactKind.wordCloud:
        _paintWordCloud(
          canvas,
          WordCloudPayload.fromJson(
            jsonDecode(artifact.payloadJson) as Map<String, Object?>,
          ),
          Size(width.toDouble(), height.toDouble()),
        );
      case VisualArtifactKind.mindMap:
        _paintMindMap(
          canvas,
          MindMapPayload.fromJson(
            jsonDecode(artifact.payloadJson) as Map<String, Object?>,
          ),
          Size(width.toDouble(), height.toDouble()),
        );
    }
    final image = await recorder.endRecording().toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) throw const FormatException('无法编码 PNG。');
    return data.buffer.asUint8List();
  }

  String _wordCloudSvg(WordCloudPayload payload, double width, double height) {
    final positions = _wordPositions(payload, Size(width, height));
    return positions.map((item) {
      final color = _wordCloudColor(payload, item.$4);
      final colorHex = (color.toARGB32() & 0x00ffffff)
          .toRadixString(16)
          .padLeft(6, '0');
      return '<text x="${item.$2.toStringAsFixed(1)}" '
          'y="${(item.$3 + item.$5).toStringAsFixed(1)}" '
          'font-size="${item.$5.toStringAsFixed(1)}" '
          'font-family="sans-serif" fill="#$colorHex">'
          '${_xml(item.$1.term)}</text>';
    }).join();
  }

  String _mindMapSvg(MindMapPayload payload, double width, double height) {
    final entries = _mindEntries(payload, Size(width, height));
    final lines = entries
        .where((entry) => entry.$2 != null)
        .map((entry) {
          final parent = entries.firstWhere((item) => item.$1.id == entry.$2);
          return '<line x1="${parent.$3.dx}" y1="${parent.$3.dy}" '
              'x2="${entry.$3.dx}" y2="${entry.$3.dy}" '
              'stroke="#B8A98C" stroke-width="2"/>';
        })
        .join();
    final nodes = entries.map((entry) {
      return '<rect x="${entry.$3.dx - 90}" y="${entry.$3.dy - 22}" '
          'width="180" height="44" rx="10" fill="#FFFDF7" '
          'stroke="#6F5D42"/><text x="${entry.$3.dx}" '
          'y="${entry.$3.dy + 5}" text-anchor="middle" '
          'font-size="15" font-family="sans-serif" fill="#2D261D">'
          '${_xml(entry.$1.label)}</text>';
    }).join();
    return '$lines$nodes';
  }

  void _paintWordCloud(Canvas canvas, WordCloudPayload payload, Size size) {
    for (final item in _wordPositions(payload, size)) {
      final painter = TextPainter(
        text: TextSpan(
          text: item.$1.term,
          style: TextStyle(
            color: _wordCloudColor(payload, item.$4),
            fontSize: item.$5,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset(item.$2, item.$3));
    }
  }

  void _paintMindMap(Canvas canvas, MindMapPayload payload, Size size) {
    final entries = _mindEntries(payload, size);
    final linePaint = Paint()
      ..color = const Color(0xffb8a98c)
      ..strokeWidth = 2;
    for (final entry in entries.where((entry) => entry.$2 != null)) {
      final parent = entries.firstWhere((item) => item.$1.id == entry.$2);
      canvas.drawLine(parent.$3, entry.$3, linePaint);
    }
    for (final entry in entries) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: entry.$3, width: 180, height: 44),
        const Radius.circular(10),
      );
      canvas.drawRRect(rect, Paint()..color = const Color(0xfffffdf7));
      canvas.drawRRect(
        rect,
        Paint()
          ..color = const Color(0xff6f5d42)
          ..style = PaintingStyle.stroke,
      );
      final painter = TextPainter(
        text: TextSpan(
          text: entry.$1.label,
          style: const TextStyle(color: Color(0xff2d261d), fontSize: 15),
        ),
        maxLines: 1,
        ellipsis: '…',
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 160);
      painter.paint(
        canvas,
        entry.$3 - Offset(painter.width / 2, painter.height / 2),
      );
    }
  }

  List<(WordCloudTerm, double, double, int, double)> _wordPositions(
    WordCloudPayload payload,
    Size size,
  ) {
    final rows = computeWordCloudLayoutRows(<String, Object>{
      'terms': [
        for (final term in payload.terms)
          <String, Object>{
            'term': term.term,
            'frequency': term.frequency,
          },
      ],
      'seed': payload.layoutSeed,
      'width': size.width,
      'height': size.height,
    });
    return rows
        .map(
          (row) => (
            WordCloudTerm(
              term: row['term']! as String,
              frequency: row['frequency']! as int,
            ),
            (row['x']! as num).toDouble(),
            (row['y']! as num).toDouble(),
            row['colorIndex']! as int,
            (row['fontSize']! as num).toDouble(),
          ),
        )
        .toList();
  }

  List<(MindMapNode, String?, Offset)> _mindEntries(
    MindMapPayload payload,
    Size size,
  ) {
    final flat = <(MindMapNode, String?, int)>[];
    void append(MindMapNode node, String? parent, int depth) {
      flat.add((node, parent, depth));
      for (final child in node.children) append(child, node.id, depth + 1);
    }
    for (final node in payload.nodes) append(node, null, 0);
    final rowHeight = size.height / (flat.length + 1);
    return [
      for (var index = 0; index < flat.length; index++)
        (
          flat[index].$1,
          flat[index].$2,
          Offset(120 + flat[index].$3 * 230, rowHeight * (index + 1)),
        ),
    ];
  }

  String _xml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  Color _wordCloudColor(WordCloudPayload payload, int index) {
    final palette = payload.colorPalette.isEmpty
        ? defaultWordCloudPalette
        : payload.colorPalette;
    final encoded = palette[index % palette.length].replaceFirst('#', '');
    final value = int.tryParse(encoded, radix: 16);
    if (value == null) return const Color(0xff315b62);
    return Color(encoded.length <= 6 ? 0xff000000 | value : value);
  }

  String _safeFileName(String value) {
    final normalized = value
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
        .trim();
    if (normalized.isEmpty) return 'tomoread-artifact';
    return normalized.substring(0, normalized.length.clamp(0, 80).toInt());
  }
}
