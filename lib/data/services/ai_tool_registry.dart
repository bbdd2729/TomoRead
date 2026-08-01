import 'dart:convert';

import '../../domain/models/ai_agent_models.dart';
import '../../domain/models/chat_models.dart';
import '../repositories/annotation_repository.dart';
import '../repositories/book_repository.dart';
import '../repositories/skill_repository.dart';
import 'epub_content_service.dart';

class AiToolContext {
  const AiToolContext({this.bookId, this.attachment});

  final String? bookId;
  final ChatContextAttachment? attachment;
}

class AiToolSet {
  AiToolSet(this._tools);

  final Map<String, AiRegisteredTool> _tools;

  List<AiToolDeclaration> get declarations =>
      _tools.values.map((tool) => tool.declaration).toList();

  AiToolDeclaration? find(String name) => _tools[name]?.declaration;

  Future<AiToolExecutionResult> execute(
    String name,
    String argumentsJson,
  ) async {
    final tool = _tools[name];
    if (tool == null) {
      throw AiToolException('tool_not_found', '工具 $name 未注册或当前不可用。');
    }
    Map<String, Object?> arguments;
    try {
      final decoded = jsonDecode(
        argumentsJson.trim().isEmpty ? '{}' : argumentsJson,
      );
      if (decoded is! Map<String, Object?>) {
        throw const FormatException();
      }
      arguments = decoded;
    } on FormatException {
      throw const AiToolException(
        'tool_arguments_invalid',
        '工具参数不是有效的 JSON 对象。',
      );
    }
    return tool
        .execute(arguments)
        .timeout(
          const Duration(seconds: 20),
          onTimeout: () =>
              throw const AiToolException('tool_timeout', '工具执行超时。'),
        );
  }
}

class AiRegisteredTool {
  const AiRegisteredTool({required this.declaration, required this.execute});

  final AiToolDeclaration declaration;
  final Future<AiToolExecutionResult> Function(Map<String, Object?>) execute;
}

class AiToolException implements Exception {
  const AiToolException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

class AiToolRegistry {
  AiToolRegistry(
    this._books,
    this._annotations,
    this._skills,
    this._epubContent,
  );

  final BookRepository _books;
  final AnnotationRepository _annotations;
  final SkillRepository _skills;
  final EpubContentService _epubContent;

  Future<AiToolSet> createToolSet(AiToolContext context) async {
    final tools = <String, AiRegisteredTool>{};
    final bookId = context.bookId;
    if (bookId != null) {
      _registerBookTools(tools, bookId);
    }
    for (final skill in await _skills.listEnabled()) {
      final name = _skillToolName(skill.id);
      tools[name] = AiRegisteredTool(
        declaration: AiToolDeclaration(
          name: name,
          displayName: skill.name,
          description: '${skill.description} 仅在用户问题适合该阅读技能时调用。',
          kind: AiToolKind.skill,
          skillId: skill.id,
          inputSchema: const {
            'type': 'object',
            'properties': {
              'focus': {'type': 'string', 'description': '本次技能要重点处理的问题或概念'},
            },
            'additionalProperties': false,
          },
        ),
        execute: (arguments) async {
          final output = <String, Object?>{
            'skill': skill.name,
            'instruction': skill.promptTemplate,
            'focus': arguments['focus'],
          };
          final attachment = context.attachment;
          if (attachment != null) {
            output['selectedText'] = attachment.quote;
            output['chapterTitle'] = attachment.chapterTitle;
          }
          return AiToolExecutionResult(output: jsonEncode(output));
        },
      );
    }
    return AiToolSet(tools);
  }

  void _registerBookTools(Map<String, AiRegisteredTool> tools, String bookId) {
    tools['get_book_metadata'] = AiRegisteredTool(
      declaration: const AiToolDeclaration(
        name: 'get_book_metadata',
        displayName: '读取书籍信息',
        description: '读取当前书籍的标题、作者、简介、阅读进度和章节数量。',
        kind: AiToolKind.read,
        inputSchema: {
          'type': 'object',
          'properties': <String, Object?>{},
          'additionalProperties': false,
        },
      ),
      execute: (_) async {
        final book = await _books.findById(bookId);
        if (book == null) {
          throw const AiToolException('book_not_found', '当前书籍已不存在。');
        }
        return AiToolExecutionResult(
          output: jsonEncode({
            'title': book.title,
            'author': book.author,
            'description': book.description,
            'format': book.format,
            'chapterCount': book.chapterCount,
            'currentChapterIndex': book.chapterIndex,
            'readingProgress': book.progress,
            'tags': book.tags,
          }),
        );
      },
    );
    tools['get_table_of_contents'] = AiRegisteredTool(
      declaration: const AiToolDeclaration(
        name: 'get_table_of_contents',
        displayName: '读取目录',
        description: '读取当前 EPUB 书籍的目录和对应章节序号。',
        kind: AiToolKind.read,
        inputSchema: {
          'type': 'object',
          'properties': <String, Object?>{},
          'additionalProperties': false,
        },
      ),
      execute: (_) async {
        final manifest = await _books.loadManifest(bookId);
        if (manifest == null) {
          throw const AiToolException('toc_unavailable', '当前书籍没有可用的 EPUB 目录。');
        }
        final entries = <Map<String, Object?>>[];
        void append(List<dynamic> items, int depth) {
          for (final item in items) {
            if (entries.length >= 120) return;
            entries.add({
              'title': item.title,
              'chapterIndex': item.spineIndex,
              'href': item.href,
              'depth': depth,
            });
            append(item.children, depth + 1);
          }
        }

        append(manifest.toc, 0);
        return AiToolExecutionResult(output: jsonEncode(entries));
      },
    );
    tools['get_annotations'] = AiRegisteredTool(
      declaration: const AiToolDeclaration(
        name: 'get_annotations',
        displayName: '读取标注与笔记',
        description: '读取当前书籍最近的高亮、笔记和对应章节。',
        kind: AiToolKind.read,
        inputSchema: {
          'type': 'object',
          'properties': {
            'limit': {
              'type': 'integer',
              'minimum': 1,
              'maximum': 30,
              'description': '最多返回多少条，默认 12',
            },
          },
          'additionalProperties': false,
        },
      ),
      execute: (arguments) async {
        final requested = arguments['limit'];
        final limit = requested is num ? requested.toInt().clamp(1, 30) : 12;
        final annotations = await _annotations.listForBook(bookId);
        return AiToolExecutionResult(
          output: jsonEncode(
            annotations
                .take(limit)
                .map(
                  (annotation) => {
                    'selectedText': annotation.selectedText,
                    'note': annotation.note,
                    'chapterIndex': annotation.chapterIndex,
                    'chapterTitle': annotation.chapterTitle,
                    'tags': annotation.tags,
                  },
                )
                .toList(),
          ),
        );
      },
    );
    tools['search_book_text'] = AiRegisteredTool(
      declaration: const AiToolDeclaration(
        name: 'search_book_text',
        displayName: '搜索书中原文',
        description: '在当前 EPUB 全文中搜索关键词，返回少量带章节位置的原文片段。',
        kind: AiToolKind.read,
        inputSchema: {
          'type': 'object',
          'properties': {
            'query': {'type': 'string', 'description': '要在书中查找的关键词或短语'},
            'limit': {'type': 'integer', 'minimum': 1, 'maximum': 8},
          },
          'required': ['query'],
          'additionalProperties': false,
        },
      ),
      execute: (arguments) async {
        final query = arguments['query'] as String?;
        if (query == null || query.trim().isEmpty) {
          throw const AiToolException('tool_arguments_invalid', '搜索关键词不能为空。');
        }
        final requested = arguments['limit'];
        final limit = requested is num ? requested.toInt().clamp(1, 8) : 5;
        final book = await _books.findById(bookId);
        final manifest = await _books.loadManifest(bookId);
        if (book == null || manifest == null || book.format != 'epub') {
          throw const AiToolException(
            'search_unavailable',
            '当前书籍不支持 EPUB 原文搜索。',
          );
        }
        final results = await _epubContent.search(
          book: book,
          manifest: manifest,
          query: query,
          maxResults: limit,
        );
        final citations = results
            .map(
              (result) => AiCitationSource(
                bookId: bookId,
                href: result.href,
                locator: 'ratio:${result.chapterRatio.toStringAsFixed(6)}',
                quote: result.excerpt,
                chapterIndex: result.chapterIndex,
                chapterTitle: result.chapterTitle,
              ),
            )
            .toList();
        return AiToolExecutionResult(
          output: jsonEncode({
            'query': query,
            'matches': results
                .map(
                  (result) => {
                    'chapterIndex': result.chapterIndex,
                    'chapterTitle': result.chapterTitle,
                    'excerpt': result.excerpt,
                  },
                )
                .toList(),
          }),
          citations: citations,
        );
      },
    );
  }

  String _skillToolName(String id) {
    final normalized = id
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9_]+'), '_')
        .replaceAll(RegExp('_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return 'skill_${normalized.isEmpty ? 'custom' : normalized}';
  }
}
