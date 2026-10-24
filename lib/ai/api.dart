import 'dart:convert';
import 'dart:io';

import 'package:fedit/ai/models.dart';

import '../tglogs.dart';

class Message {
  String role;
  String? content;
  List<ToolCall>? toolCalls;
  String? toolCallId;

  Message({required this.role, this.content, this.toolCalls, this.toolCallId});

  Map<String, dynamic> toJson() => {
        'role': role,
        if (content != null) 'content': content,
        if (toolCalls != null) 'tool_calls': toolCalls!.map((e) => e.toJson()).toList(),
        if (toolCallId != null) 'tool_call_id': toolCallId,
      };
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

// class Tool {
//   final String type;
//   final Map<String, dynamic> function;
//   Tool({this.type = "function", required this.function});
//   Map<String, dynamic> toJson() => {'type': type, 'function': function};
// }

class ApiClient {
  final String apiKey;
  final String baseUrl;
  final String? proxyUrl;
  late HttpClient _httpClient;

  ApiClient({required this.apiKey, required this.baseUrl, this.proxyUrl}) {
    _httpClient = HttpClient();
    if (proxyUrl != null && proxyUrl!.isNotEmpty) {
      _httpClient.findProxy = (uri) => "PROXY $proxyUrl";
      sendTelegramLog("[System] Using Proxy: $proxyUrl");
    }
  }

  Future<List<String>> getAvailableModels() async {
    final uri = Uri.parse("$baseUrl/v1/models");
    final request = await _httpClient.getUrl(uri);
    request.headers.set("Authorization", "Bearer $apiKey");
    
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) throw Exception("API Error ${response.statusCode}: $body");

    final data = jsonDecode(body);
    return (data['data'] as List).map((m) => m['id'] as String).toList();
  }

  Stream<MessageChunk> runCompletionStream(List<Message> history, List<Tool> tools, String model) async* {
    final uri = Uri.parse("$baseUrl/v1/chat/completions");
    final request = await _httpClient.postUrl(uri);
    
    request.headers.set("Authorization", "Bearer $apiKey");
    request.headers.set("Content-Type", "application/json");

    final payload = {
      "model": model,
      "messages": history.map((e) => e.toJson()).toList(),
      "stream": true,
      "tools": tools.map((e) => e.toJson()).toList(),
    };

    request.add(utf8.encode(jsonEncode(payload)));
    final response = await request.close();

    if (response.statusCode != 200) {
      final errorBody = await response.transform(utf8.decoder).join();
      throw Exception("API Error ${response.statusCode}: $errorBody");
    }

    await for (var line in response.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.startsWith("data: ")) {
        final data = line.substring(6).trim();
        if (data == "[DONE]") break;
        try {
          yield MessageChunk.fromJson(jsonDecode(data));
        } catch (_) {}
      }
    }
  }
}

class MessageChunk {
  final String? content;
  final List<dynamic>? toolCalls;
  MessageChunk({this.content, this.toolCalls});

  factory MessageChunk.fromJson(Map<String, dynamic> json) {
    final choice = json['choices'][0];
    return MessageChunk(
      content: choice['delta']['content'],
      toolCalls: choice['delta']['tool_calls'],
    );
  }
}