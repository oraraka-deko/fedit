class Message {
  String role;
  String content;
  List<ToolCall>? toolCalls;
  String? toolCallId;

  Message({
    required this.role, 
    this.content = "", 
    this.toolCalls, 
    this.toolCallId
  });

  Map<String, dynamic> toJson() => {
    'role': role,
    'content': content, // API expects content even if null/empty for some roles
    if (toolCalls != null) 'tool_calls': toolCalls!.map((e) => e.toJson()).toList(),
    if (toolCallId != null) 'tool_call_id': toolCallId,
  };
}

enum StreamPhase {
  idle,
  thinking,
  streaming,
  executingTools,
  error,
}

class ChatThread {
  String id;
  String title;
  DateTime createdAt;
  DateTime updatedAt;
  String modelId;
  List<Message> messages;

  ChatThread({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.modelId,
    required this.messages,
  });

  ChatThreadMeta toMeta() => ChatThreadMeta(
        id: id,
        title: title,
        createdAt: createdAt,
        updatedAt: updatedAt,
        modelId: modelId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'model_id': modelId,
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory ChatThread.fromJson(Map<String, dynamic> json) {
    final rawMessages = (json['messages'] as List?) ?? const [];
    return ChatThread(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? 'New Thread').toString(),
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.now(),
      updatedAt: DateTime.tryParse((json['updated_at'] ?? '').toString()) ??
          DateTime.now(),
      modelId: (json['model_id'] ?? '').toString(),
      messages: rawMessages
          .whereType<Map>()
          .map(
            (m) => Message(
              role: (m['role'] ?? '').toString(),
              content: (m['content'] ?? '').toString(),
              toolCalls: _toolCallsFromJson(m['tool_calls']),
              toolCallId: m['tool_call_id']?.toString(),
            ),
          )
          .toList(),
    );
  }

  static List<ToolCall>? _toolCallsFromJson(dynamic value) {
    if (value is! List) return null;
    final toolCalls = value
        .whereType<Map>()
        .map(
          (raw) => ToolCall(
            id: (raw['id'] ?? '').toString(),
            type: (raw['type'] ?? 'function').toString(),
            function: FunctionCall(
              name: (raw['function']?['name'] ?? '').toString(),
              arguments: (raw['function']?['arguments'] ?? '').toString(),
            ),
          ),
        )
        .toList();
    return toolCalls.isEmpty ? null : toolCalls;
  }
}

class ChatThreadMeta {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String modelId;

  ChatThreadMeta({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.modelId,
  });
}

class ToolCall {
  String id;
  String type;
  FunctionCall function;

  ToolCall({required this.id, required this.type, required this.function});

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'function': function.toJson(),
  };
}

class FunctionCall {
  String name;
  String arguments;

  FunctionCall({required this.name, required this.arguments});

  Map<String, dynamic> toJson() => {'name': name, 'arguments': arguments};
}

class Tool {
  final String type;
  final Map<String, dynamic> function;
  Tool({this.type = "function", required this.function});
  Map<String, dynamic> toJson() => {'type': type, 'function': function};
}
