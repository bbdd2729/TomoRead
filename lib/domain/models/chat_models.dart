enum ChatScope { general, book }

enum ChatRole { system, user, assistant }

enum ChatMessageStatus { complete, streaming, failed, cancelled }

class AiProviderProfile {
  const AiProviderProfile({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.modelId,
    required this.secretKeyId,
    required this.temperature,
    required this.maxOutputTokens,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String modelId;
  final String secretKeyId;
  final double temperature;
  final int maxOutputTokens;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class ChatThread {
  const ChatThread({
    required this.id,
    required this.scope,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.bookId,
  });

  final String id;
  final ChatScope scope;
  final String? bookId;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  ChatThread copyWith({String? title, DateTime? updatedAt}) => ChatThread(
    id: id,
    scope: scope,
    bookId: bookId,
    title: title ?? this.title,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.threadId,
    required this.role,
    required this.content,
    required this.status,
    required this.createdAt,
    this.modelId,
    this.errorCode,
    this.completedAt,
    this.citations = const [],
  });

  final String id;
  final String threadId;
  final ChatRole role;
  final String content;
  final ChatMessageStatus status;
  final String? modelId;
  final String? errorCode;
  final DateTime createdAt;
  final DateTime? completedAt;
  final List<ChatCitation> citations;

  ChatMessage copyWith({
    String? content,
    ChatMessageStatus? status,
    String? errorCode,
    DateTime? completedAt,
    List<ChatCitation>? citations,
  }) => ChatMessage(
    id: id,
    threadId: threadId,
    role: role,
    content: content ?? this.content,
    status: status ?? this.status,
    modelId: modelId,
    errorCode: errorCode ?? this.errorCode,
    createdAt: createdAt,
    completedAt: completedAt ?? this.completedAt,
    citations: citations ?? this.citations,
  );
}

class ChatCitation {
  const ChatCitation({
    required this.id,
    required this.messageId,
    required this.ordinal,
    required this.bookId,
    required this.href,
    required this.locator,
    required this.quote,
    this.chapterIndex,
    this.chapterTitle,
  });

  final String id;
  final String messageId;
  final int ordinal;
  final String bookId;
  final String href;
  final String locator;
  final int? chapterIndex;
  final String? chapterTitle;
  final String quote;
}

class ChatContextAttachment {
  const ChatContextAttachment({
    required this.bookId,
    required this.bookTitle,
    required this.href,
    required this.locator,
    required this.quote,
    this.chapterIndex,
    this.chapterTitle,
  });

  final String bookId;
  final String bookTitle;
  final String href;
  final String locator;
  final int? chapterIndex;
  final String? chapterTitle;
  final String quote;
}
