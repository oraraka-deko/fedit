import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'dynamic_code_editor_tab_bar.dart';

class OpenDocument {
  final EditorTabItem tab;
  final File? file;

  const OpenDocument({
    required this.tab,
    this.file,
  });
}

class EditorSessionManager extends ChangeNotifier {
  final List<OpenDocument> _documents = [];
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

    _documents.add(OpenDocument(tab: tab, file: file));
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
