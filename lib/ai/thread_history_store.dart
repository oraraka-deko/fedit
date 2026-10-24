import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models.dart';

class ThreadHistoryData {
  final List<ChatThread> threads;
  final String? activeThreadId;

  ThreadHistoryData({
    required this.threads,
    required this.activeThreadId,
  });
}

class ThreadHistoryStore {
  static const _fileName = 'chat_threads.json';

  Future<File> _historyFile() async {
    final dir = await getApplicationSupportDirectory();
    final historyDir = Directory(p.join(dir.path, 'history'));
    if (!historyDir.existsSync()) {
      historyDir.createSync(recursive: true);
    }
    final file = File(p.join(historyDir.path, _fileName));
    if (!file.existsSync()) {
      file.createSync();
      file.writeAsStringSync(
        jsonEncode({'active_thread_id': null, 'threads': []}),
      );
    }
    return file;
  }

  Future<ThreadHistoryData> load() async {
    try {
      final file = await _historyFile();
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        return ThreadHistoryData(threads: [], activeThreadId: null);
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return ThreadHistoryData(threads: [], activeThreadId: null);
      }
      final threads = ((decoded['threads'] as List?) ?? const [])
          .whereType<Map>()
          .map((t) => ChatThread.fromJson(Map<String, dynamic>.from(t)))
          .toList();
      return ThreadHistoryData(
        threads: threads,
        activeThreadId: decoded['active_thread_id']?.toString(),
      );
    } catch (_) {
      return ThreadHistoryData(threads: [], activeThreadId: null);
    }
  }

  Future<void> save({
    required List<ChatThread> threads,
    required String? activeThreadId,
  }) async {
    final file = await _historyFile();
    final payload = {
      'active_thread_id': activeThreadId,
      'threads': threads.map((t) => t.toJson()).toList(),
    };
    await file.writeAsString(jsonEncode(payload));
  }
}
