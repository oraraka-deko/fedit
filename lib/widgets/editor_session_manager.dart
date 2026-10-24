import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'dynamic_code_editor_tab_bar.dart';

class OpenDocument {
  final EditorTabItem tab;
  final File? file;
  int lastActiveLine;

  OpenDocument({
    required this.tab,
    this.file,
    this.lastActiveLine = 0,
  });
}

class EditorSessionManager extends ChangeNotifier {
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
    final existingIndex = _documents.indexWhere((d) => d.file?.path == file.path);
    if (existingIndex != -1) {
      _activeTabId = _documents[existingIndex].tab.id;
      notifyListeners();
      return;
    }

    final tabId = DateTime.now().microsecondsSinceEpoch.toString();
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

  void openNewEmptyTab() {
    final tabId = DateTime.now().microsecondsSinceEpoch.toString();
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
    if (doc.file != null) {
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
