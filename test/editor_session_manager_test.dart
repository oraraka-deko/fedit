import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fedit/widgets/editor_session_manager.dart';

void main() {
  group('EditorSessionManager tab states and line tracking', () {
    late EditorSessionManager manager;
    late Directory tempDir;
    late File fileA;
    late File fileB;

    setUp(() {
      manager = EditorSessionManager();
      tempDir = Directory.systemTemp.createTempSync('editor_session_test');
      fileA = File('${tempDir.path}/file_a.dart')..writeAsStringSync('line 1\nline 2\nline 3\n');
      fileB = File('${tempDir.path}/file_b.dart')..writeAsStringSync('line B1\nline B2\n');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('openFile adds document without closing existing opened tabs', () {
      manager.openFile(fileA);
      expect(manager.documents.length, 1);
      final tabAId = manager.activeTabId;

      manager.openFile(fileB);
      expect(manager.documents.length, 2);
      expect(manager.activeTabId, isNot(tabAId));

      // Both tabs remain open
      expect(manager.documents.any((d) => d.tab.id == tabAId), isTrue);
    });

    test('saves and retrieves last active line per tab and file path', () {
      manager.openFile(fileA);
      final tabAId = manager.activeTabId;

      manager.saveLastActiveLine(tabAId, 42);
      expect(manager.getLastActiveLine(tabAId), 42);
      expect(manager.getLastActiveLineForFile(fileA.path), 42);

      manager.openFile(fileB);
      final tabBId = manager.activeTabId;
      manager.saveLastActiveLine(tabBId, 15);

      // Tab A's line is preserved when navigating to Tab B
      expect(manager.getLastActiveLine(tabAId), 42);
      expect(manager.getLastActiveLine(tabBId), 15);
    });

    test('closing tab preserves last active line for file when reopened', () {
      manager.openFile(fileA);
      final tabAId = manager.activeTabId;
      manager.saveLastActiveLine(tabAId, 88);

      // Close Tab A
      manager.closeTab(tabAId);
      expect(manager.documents.isEmpty, isTrue);

      // Re-opening the same file restores the saved last active line
      manager.openFile(fileA);
      final newTabAId = manager.activeTabId;
      expect(manager.getLastActiveLine(newTabAId), 88);
      expect(manager.getLastActiveLineForFile(fileA.path), 88);
    });

    test('selectTab switches activeTabId without destroying or altering other tab lines', () {
      manager.openFile(fileA);
      final tabAId = manager.activeTabId;
      manager.saveLastActiveLine(tabAId, 10);

      manager.openFile(fileB);
      final tabBId = manager.activeTabId;
      manager.saveLastActiveLine(tabBId, 20);

      // Navigate back to Tab A
      manager.selectTab(tabAId);
      expect(manager.activeTabId, tabAId);
      expect(manager.getLastActiveLine(tabAId), 10);
      expect(manager.getLastActiveLine(tabBId), 20);
    });
  });
}

