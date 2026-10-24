import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'config.dart';
import 'models.dart';
import 'thread_history_store.dart';
import 'tools_handler.dart';

class ChatService extends ChangeNotifier {
  static const int _maxThreads = 100;
  static const int _maxMessagesPerThread = 500;

  final Config config;
  final ToolsHandler toolsHandler;
  final ThreadHistoryStore _historyStore = ThreadHistoryStore();

  List<ChatThread> _threads = [];
  String _activeThreadId = '';
  List<String> _availableModels = [];

  StreamPhase _streamPhase = StreamPhase.idle;
  String currentStreamingContent = '';
  String? modelFetchError;
  bool isFetchingModels = false;
  bool _isInitialized = false;

  ChatService(this.config, String rootPath)
      : toolsHandler = ToolsHandler(rootPath) {
    loadThreads();
    refreshAvailableModels();
  }

  List<ChatThreadMeta> get threads =>
      _threads.map((thread) => thread.toMeta()).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  String get activeThreadId => _activeThreadId;
  StreamPhase get streamPhase => _streamPhase;
  List<String> get availableModels => List.unmodifiable(_availableModels);
  bool get isThinking =>
      _streamPhase == StreamPhase.thinking ||
      _streamPhase == StreamPhase.executingTools;
  List<Message> get messages =>
      List.unmodifiable(_activeThreadOrNull?.messages ?? const []);
  List<Message> get visibleMessages =>
      messages.where((message) => message.role != 'system').toList();
  bool get isInitialized => _isInitialized;
  String get currentModel {
    final threadModel = _activeThreadOrNull?.modelId ?? '';
    if (threadModel.isNotEmpty) return threadModel;
    return config.currentModel;
  }

  ChatThread? get _activeThreadOrNull {
    for (final thread in _threads) {
      if (thread.id == _activeThreadId) return thread;
    }
    return null;
  }

  Future<void> loadThreads() async {
    final data = await _historyStore.load();
    _threads = data.threads;
    _activeThreadId = data.activeThreadId ?? '';

    if (_threads.isEmpty) {
      await createThread(title: 'New Thread');
      _isInitialized = true;
      return;
    }

    if (_activeThreadOrNull == null) {
      _threads.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      _activeThreadId = _threads.first.id;
    }

    for (final thread in _threads) {
      if (thread.modelId.isEmpty) {
        thread.modelId = config.currentModel;
      }
      thread.messages = thread.messages
          .where((m) => m.role == 'user' || m.role == 'assistant' || m.role == 'tool')
          .toList();
      _trimMessages(thread);
    }

    _trimThreads();
    await _persistThreads();
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> createThread({String? title}) async {
    final now = DateTime.now();
    final id = now.microsecondsSinceEpoch.toString();
    final defaultTitle = title?.trim().isNotEmpty == true
        ? title!.trim()
        : 'New Thread';
    final thread = ChatThread(
      id: id,
      title: defaultTitle,
      createdAt: now,
      updatedAt: now,
      modelId: currentModel,
      messages: [],
    );
    _threads.insert(0, thread);
    _activeThreadId = id;
    _trimThreads();
    await _persistThreads();
    notifyListeners();
  }

  Future<void> switchThread(String threadId) async {
    final exists = _threads.any((thread) => thread.id == threadId);
    if (!exists) return;
    _activeThreadId = threadId;
    await _persistThreads();
    notifyListeners();
  }

  Future<void> renameThread(String threadId, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    ChatThread? thread;
    for (final candidate in _threads) {
      if (candidate.id == threadId) {
        thread = candidate;
        break;
      }
    }
    if (thread == null) return;
    thread.title = trimmed;
    thread.updatedAt = DateTime.now();
    await _persistThreads();
    notifyListeners();
  }

  Future<void> deleteThread(String threadId) async {
    _threads.removeWhere((thread) => thread.id == threadId);
    if (_threads.isEmpty) {
      await createThread(title: 'New Thread');
      return;
    }
    if (_activeThreadId == threadId) {
      _threads.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      _activeThreadId = _threads.first.id;
    }
    await _persistThreads();
    notifyListeners();
  }

  Future<void> setCurrentModel(String modelId) async {
    final trimmed = modelId.trim();
    if (trimmed.isEmpty) return;
    final thread = _activeThreadOrNull;
    if (thread == null) return;

    thread.modelId = trimmed;
    thread.updatedAt = DateTime.now();
    config.currentModel = trimmed;
    await config.save();
    await _persistThreads();
    if (!_availableModels.contains(trimmed)) {
      _availableModels = [trimmed, ..._availableModels];
    }
    notifyListeners();
  }

  Future<void> refreshAvailableModels() async {
    final baseUrl = config.baseUrl.trim();
    final apiKey = config.apiKey.trim();
    final fallback = currentModel.trim();

    if (baseUrl.isEmpty || apiKey.isEmpty) {
      _availableModels = fallback.isEmpty ? [] : [fallback];
      modelFetchError = null;
      notifyListeners();
      return;
    }

    isFetchingModels = true;
    modelFetchError = null;
    notifyListeners();

    try {
      final uri = Uri.parse(baseUrl).resolve('v1/models');
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $apiKey'},
      );
      if (response.statusCode != 200) {
        throw Exception('Server responded with ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      final decodedMap =
          decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      final raw = (decodedMap['data'] as List<dynamic>?) ?? [];
      final ids = raw
          .map((entry) => entry is Map<String, dynamic> ? entry['id'] : entry)
          .whereType<String>()
          .where((id) => id.trim().isNotEmpty)
          .toList();

      if (fallback.isNotEmpty && !ids.contains(fallback)) {
        ids.insert(0, fallback);
      }
      _availableModels = ids;
      modelFetchError = null;
    } catch (e) {
      _availableModels = fallback.isEmpty ? [] : [fallback];
      modelFetchError = e.toString();
    } finally {
      isFetchingModels = false;
      notifyListeners();
    }
  }

  Future<void> clearActiveThread() async {
    final thread = _activeThreadOrNull;
    if (thread == null) return;
    thread.messages.clear();
    thread.updatedAt = DateTime.now();
    await _persistThreads();
    notifyListeners();
  }

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final thread = _activeThreadOrNull;
    if (thread == null) return;

    await _appendMessage(
      Message(role: 'user', content: trimmed),
      persist: true,
    );
    if (thread.title == 'New Thread') {
      thread.title = _autoTitle(trimmed);
      await _persistThreads();
    }
    notifyListeners();
    await _runLoop();
  }

  Future<void> _runLoop() async {
    bool keepGoing = true;

    while (keepGoing) {
      _setStreamPhase(StreamPhase.thinking);
      currentStreamingContent = '';
      notifyListeners();

      final pendingToolCalls = <int, ToolCall>{};

      try {
        final requestBody = {
          'model': currentModel,
          'messages': _buildRequestMessages().map((message) => message.toJson()).toList(),
          'stream': true,
          'tools': toolsHandler
              .getToolDefinitions()
              .map((tool) => tool.toJson())
              .toList(),
        };

        final request = http.Request(
          'POST',
          Uri.parse('${config.baseUrl}/chat/completions'),
        );
        request.headers['Authorization'] = 'Bearer ${config.apiKey}';
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(requestBody);

        final response = await http.Client().send(request);
        if (response.statusCode != 200) {
          final body = await response.stream.bytesToString();
          throw Exception('API Error ${response.statusCode}: $body');
        }

        await for (final line in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
          if (!line.startsWith('data: ')) continue;
          final jsonStr = line.substring(6).trim();
          if (jsonStr == '[DONE]') break;

          try {
            final chunk = jsonDecode(jsonStr);
            final delta = chunk['choices'][0]['delta'];

            final content = delta['content'];
            if (content != null) {
              if (_streamPhase != StreamPhase.streaming) {
                _setStreamPhase(StreamPhase.streaming);
              }
              currentStreamingContent += content.toString();
              notifyListeners();
            }

            if (delta['tool_calls'] != null) {
              for (final tc in delta['tool_calls']) {
                final idx = (tc['index'] as num).toInt();
                pendingToolCalls.putIfAbsent(
                  idx,
                  () => ToolCall(
                    id: tc['id']?.toString() ?? '',
                    type: 'function',
                    function: FunctionCall(name: '', arguments: ''),
                  ),
                );

                final call = pendingToolCalls[idx]!;
                if (tc['id'] != null) {
                  call.id = tc['id'].toString();
                }
                final fn = tc['function'] as Map?;
                if (fn != null) {
                  if (fn['name'] != null) {
                    call.function.name += fn['name'].toString();
                  }
                  if (fn['arguments'] != null) {
                    call.function.arguments += fn['arguments'].toString();
                  }
                }
              }
            }
          } catch (_) {}
        }

        final assistantMessage = Message(
          role: 'assistant',
          content: currentStreamingContent,
          toolCalls:
              pendingToolCalls.isEmpty ? null : pendingToolCalls.values.toList(),
        );
        if (assistantMessage.content.isNotEmpty ||
            (assistantMessage.toolCalls?.isNotEmpty ?? false)) {
          await _appendMessage(assistantMessage, persist: true);
        }
        currentStreamingContent = '';
        notifyListeners();

        if (pendingToolCalls.isEmpty) {
          keepGoing = false;
        } else {
          _setStreamPhase(StreamPhase.executingTools);
          for (final toolCall in pendingToolCalls.values) {
            Map<String, dynamic> args = {};
            try {
              args = jsonDecode(toolCall.function.arguments);
            } catch (_) {}

            final output = await toolsHandler.execute(toolCall.function.name, args);
            await _appendMessage(
              Message(role: 'tool', content: output, toolCallId: toolCall.id),
              persist: true,
            );
          }
        }
      } catch (e) {
        _setStreamPhase(StreamPhase.error);
        await _appendMessage(
          Message(role: 'assistant', content: 'Error: $e'),
          persist: true,
        );
        keepGoing = false;
      } finally {
        currentStreamingContent = '';
        notifyListeners();
      }
    }

    _setStreamPhase(StreamPhase.idle);
    notifyListeners();
  }

  List<Message> _buildRequestMessages() {
    final thread = _activeThreadOrNull;
    final history = thread?.messages ?? const <Message>[];
    return [
      Message(role: 'system', content: _systemPrompt),
      ...history.where(
        (message) =>
            message.role == 'user' ||
            message.role == 'assistant' ||
            message.role == 'tool',
      ),
    ];
  }

  Future<void> _appendMessage(Message message, {required bool persist}) async {
    final thread = _activeThreadOrNull;
    if (thread == null) return;
    thread.messages.add(message);
    thread.updatedAt = DateTime.now();
    _trimMessages(thread);
    if (persist) {
      await _persistThreads();
    }
  }

  void _trimMessages(ChatThread thread) {
    if (thread.messages.length > _maxMessagesPerThread) {
      final overflow = thread.messages.length - _maxMessagesPerThread;
      thread.messages.removeRange(0, overflow);
    }
  }

  void _trimThreads() {
    _threads.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (_threads.length > _maxThreads) {
      _threads = _threads.sublist(0, _maxThreads);
    }
  }

  Future<void> _persistThreads() async {
    _trimThreads();
    await _historyStore.save(threads: _threads, activeThreadId: _activeThreadId);
  }

  void _setStreamPhase(StreamPhase phase) {
    _streamPhase = phase;
  }

  String _autoTitle(String text) {
    final trimmed = text.trim().replaceAll('\n', ' ');
    if (trimmed.length <= 40) return trimmed;
    return '${trimmed.substring(0, 40)}...';
  }

  String get _systemPrompt => '''
You are an advanced coding assistant.
Tools:
- Use 'list_files' to explore the workspace tree first.
- Use 'read_file' to inspect code with line numbers before editing.
- Use 'patch_file' for precise line edits. Syntax: 'N++ code', 'N--', '0++' (prepend), '00++' (append).
- Use 'find_and_replace' for bulk or regex edits (supports case sensitivity, suffix-only matches, include/exclude globs, dry runs). Prefer a dry run when unsure.
- Use 'file_action' to create/delete/move/copy/duplicate files or directories (paths must stay inside the workspace; provide target for move/copy; trailing slash creates a directory).
Error handling: if a tool call fails (e.g., invalid path/regex), inspect the error, adjust arguments, and retry automatically instead of stopping. Continue looping until tasks are complete.
Formatting:
- Use markdown when it improves readability: headings/lists/tables for structured explanation.
- Use fenced code blocks for code, diffs, file content, commands, and long tool outputs.
- Keep short confirmations plain text.
Be concise.
''';
}
