import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ProjectEntry {
  final String name;
  final String path;
  final DateTime openedAt;

  ProjectEntry({
    required this.name,
    required this.path,
    required this.openedAt,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'openedAt': openedAt.toIso8601String(),
      };

  factory ProjectEntry.fromJson(Map<String, dynamic> json) {
    return ProjectEntry(
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
      openedAt: DateTime.tryParse(json['openedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class ProjectHistoryStore {
  static final ProjectHistoryStore _instance = ProjectHistoryStore._internal();
  factory ProjectHistoryStore() => _instance;
  ProjectHistoryStore._internal();

  static const _fileName = 'projects_history.json';
  static const _maxEntries = 200;

  Future<File> _historyFile() async {
    final dir = await getApplicationSupportDirectory();
    final historyDir = Directory(p.join(dir.path, 'history'));
    if (!historyDir.existsSync()) {
      historyDir.createSync(recursive: true);
    }
    final file = File(p.join(historyDir.path, _fileName));
    if (!file.existsSync()) {
      file.createSync();
      file.writeAsStringSync('[]');
    }
    return file;
  }

  Future<List<ProjectEntry>> load() async {
    try {
      final file = await _historyFile();
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];
      final decoded = jsonDecode(content);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(ProjectEntry.fromJson)
          .toList()
        ..sort((a, b) => b.openedAt.compareTo(a.openedAt));
    } catch (_) {
      return [];
    }
  }

  Future<void> add(ProjectEntry entry) async {
    final file = await _historyFile();
    final existing = await load();
    final filtered =
        existing.where((e) => e.path != entry.path).toList(growable: true);
    filtered.insert(0, entry);
    if (filtered.length > _maxEntries) {
      filtered.length = _maxEntries;
    }
    final encoded = jsonEncode(filtered.map((e) => e.toJson()).toList());
    await file.writeAsString(encoded);
  }
}
