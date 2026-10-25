import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/git_models.dart';
import 'dynamic_code_editor_tab_bar.dart';

/// Information needed to display a side-by-side or inline Git diff.
class DiffDocumentInfo {
  final String relativePath;
  final String fullPath;
  final bool isStaged;
  final String originalContent;
  final String modifiedContent;
  final GitFileDiff fileDiff;

  const DiffDocumentInfo({
    required this.relativePath,
    required this.fullPath,
    this.isStaged = false,
    required this.originalContent,
    required this.modifiedContent,
    required this.fileDiff,
  });
}

class OpenDocument {
  final EditorTabItem tab;
  final File? file;
  final DiffDocumentInfo? diff;
  int lastActiveLine;

  OpenDocument({
    required this.tab,
    this.file,
    this.diff,
    this.lastActiveLine = 0,
  });

  bool get isDiff => diff != null;
}

class EditorSessionManager extends ChangeNotifier {
  static int _tabCounter = 0;
  static String _generateTabId([String prefix = 'tab']) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_tabCounter++}';

  final List<OpenDocument> _documents = [];
  final Map<String, int> _lastActiveLinesByPath = {};
  String _activeTabId = '';

  List<OpenDocument> get documents => List.unmodifiable(_documents);
  List<EditorTabItem> get tabs => _documents.map((d) => d.tab).toList();
  String get activeTabId => _activeTabId;

  OpenDocument? get activeDocument {
    try {
      return _documents.firstWhere((doc) => doc.tab.id == _activeTabId);
    } catch (_) {
      return null;
    }
  }

  void saveLastActiveLine(String tabId, int line) {
    final index = _documents.indexWhere((doc) => doc.tab.id == tabId);
    if (index != -1) {
      _documents[index].lastActiveLine = line;
      final file = _documents[index].file;
      if (file != null) {
        _lastActiveLinesByPath[file.path] = line;
      }
    }
  }

  int getLastActiveLine(String tabId) {
    final index = _documents.indexWhere((doc) => doc.tab.id == tabId);
    if (index != -1) {
      return _documents[index].lastActiveLine;
    }
    return 0;
  }

  void saveLastActiveLineForFile(String filePath, int line) {
    _lastActiveLinesByPath[filePath] = line;
    final index = _documents.indexWhere((doc) => doc.file?.path == filePath);
    if (index != -1) {
      _documents[index].lastActiveLine = line;
    }
  }

  int getLastActiveLineForFile(String filePath) {
    return _lastActiveLinesByPath[filePath] ?? 0;
  }

  void openFile(File file) {
    final existingIndex = _documents.indexWhere((d) => !d.isDiff && d.file?.path == file.path);
    if (existingIndex != -1) {
      _activeTabId = _documents[existingIndex].tab.id;
      notifyListeners();
      return;
    }

    final tabId = _generateTabId('file');
    final tab = EditorTabItem(
      id: tabId,
      title: p.basename(file.path),
      filePath: file.path,
    );

    final savedLine = _lastActiveLinesByPath[file.path] ?? 0;
    _documents.add(OpenDocument(tab: tab, file: file, lastActiveLine: savedLine));
    _activeTabId = tabId;
    notifyListeners();
  }

  void openDiffView({
    required String relativePath,
    required String fullPath,
    required String originalContent,
    required String modifiedContent,
    required GitFileDiff fileDiff,
    bool isStaged = false,
  }) {
    final diffId = 'diff:${isStaged ? "staged" : "workdir"}:$relativePath';
    final existingIndex = _documents.indexWhere((d) => d.tab.id == diffId);
    if (existingIndex != -1) {
      _activeTabId = diffId;
      notifyListeners();
      return;
    }

    final filename = p.basename(relativePath);
    final statusSuffix = isStaged ? '(Index)' : '(Working Tree)';
    final tab = EditorTabItem(
      id: diffId,
      title: '$filename $statusSuffix',
      filePath: fullPath,
    );

    final diffInfo = DiffDocumentInfo(
      relativePath: relativePath,
      fullPath: fullPath,
      isStaged: isStaged,
      originalContent: originalContent,
      modifiedContent: modifiedContent,
      fileDiff: fileDiff,
    );

    _documents.add(OpenDocument(tab: tab, file: File(fullPath), diff: diffInfo));
    _activeTabId = diffId;
    notifyListeners();
  }

  void openNewEmptyTab() {
    final tabId = _generateTabId('file');
    final tab = EditorTabItem(
      id: tabId,
      title: 'Untitled-${_documents.length + 1}',
    );

    _documents.add(OpenDocument(tab: tab));
    _activeTabId = tabId;
    notifyListeners();
  }

  void selectTab(String tabId) {
    if (_activeTabId == tabId) return;
    _activeTabId = tabId;
    notifyListeners();
  }

  void closeTab(String tabId) {
    final index = _documents.indexWhere((doc) => doc.tab.id == tabId);
    if (index == -1) return;

    final doc = _documents[index];
    if (doc.file != null && !doc.isDiff) {
      _lastActiveLinesByPath[doc.file!.path] = doc.lastActiveLine;
    }

    _documents.removeAt(index);

    if (_activeTabId == tabId) {
      if (_documents.isNotEmpty) {
        final nextIndex = (index - 1).clamp(0, _documents.length - 1);
        _activeTabId = _documents[nextIndex].tab.id;
      } else {
        _activeTabId = '';
      }
    }

    notifyListeners();
  }

  void reorderTabs(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _documents.length) return;
    final adjusted = newIndex > oldIndex ? newIndex - 1 : newIndex;
    if (adjusted < 0 || adjusted >= _documents.length) return;

    final item = _documents.removeAt(oldIndex);
    _documents.insert(adjusted, item);
    notifyListeners();
  }
}
