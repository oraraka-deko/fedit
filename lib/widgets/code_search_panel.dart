import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class SearchMatchResult {
  final File file;
  final int lineNumber; // 1-based
  final String lineText;
  final int matchStart;
  final int matchLength;

  const SearchMatchResult({
    required this.file,
    required this.lineNumber,
    required this.lineText,
    required this.matchStart,
    required this.matchLength,
  });
}

class CodeSearchPanel extends StatefulWidget {
  final Directory projectRoot;
  final void Function(File file, {int? line}) onOpenFile;

  const CodeSearchPanel({
    super.key,
    required this.projectRoot,
    required this.onOpenFile,
  });

  @override
  State<CodeSearchPanel> createState() => _CodeSearchPanelState();
}

class _CodeSearchPanelState extends State<CodeSearchPanel> {
  final TextEditingController _queryController = TextEditingController();
  final TextEditingController _replaceController = TextEditingController();

  bool _isReplaceExpanded = false;
  bool _matchCase = false;
  bool _matchWholeWord = false;
  bool _useRegex = false;

  bool _isSearching = false;
  Map<String, List<SearchMatchResult>> _resultsByFile = {};
  int _totalMatches = 0;

  @override
  void dispose() {
    _queryController.dispose();
    _replaceController.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    final query = _queryController.text;
    if (query.isEmpty) {
      setState(() {
        _resultsByFile = {};
        _totalMatches = 0;
      });
      return;
    }

    setState(() => _isSearching = true);

    final results = <String, List<SearchMatchResult>>{};
    int matchCount = 0;

    String patternStr = query;
    if (!_useRegex) {
      patternStr = RegExp.escape(patternStr);
    }
    if (_matchWholeWord) {
      patternStr = '\\b$patternStr\\b';
    }

    try {
      final regExp = RegExp(patternStr, caseSensitive: _matchCase);

      await for (final entity in widget.projectRoot.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;

        // Skip build, git and cache folders
        final normalized = entity.path.replaceAll(r'\', '/');
        if (normalized.contains('/.git/') ||
            normalized.contains('/.dart_tool/') ||
            normalized.contains('/build/')) {
          continue;
        }

        try {
          final lines = await entity.readAsLines();
          final fileMatches = <SearchMatchResult>[];

          for (int i = 0; i < lines.length; i++) {
            final line = lines[i];
            for (final m in regExp.allMatches(line)) {
              fileMatches.add(SearchMatchResult(
                file: entity,
                lineNumber: i + 1,
                lineText: line,
                matchStart: m.start,
                matchLength: m.end - m.start,
              ));
              matchCount++;
            }
          }

          if (fileMatches.isNotEmpty) {
            results[entity.path] = fileMatches;
          }
        } catch (_) {}
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _resultsByFile = results;
        _totalMatches = matchCount;
        _isSearching = false;
      });
    }
  }

  Future<void> _replaceAllInFiles() async {
    final query = _queryController.text;
    final replacement = _replaceController.text;
    if (query.isEmpty || _resultsByFile.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF252526),
        title: const Text('Replace all occurrences?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Replace $_totalMatches occurrences across ${_resultsByFile.keys.length} files?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0078D4)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Replace All'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    String patternStr = query;
    if (!_useRegex) {
      patternStr = RegExp.escape(patternStr);
    }
    if (_matchWholeWord) {
      patternStr = '\\b$patternStr\\b';
    }

    final regExp = RegExp(patternStr, caseSensitive: _matchCase);

    for (final filePath in _resultsByFile.keys) {
      try {
        final file = File(filePath);
        final content = await file.readAsString();
        final newContent = content.replaceAll(regExp, replacement);
        await file.writeAsString(newContent);
      } catch (_) {}
    }

    await _performSearch();
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF1E1E1E);
    const border = Color(0xFF282828);

    return Container(
      color: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                const Text(
                  'SEARCH',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(_isReplaceExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, size: 16),
                  color: Colors.white70,
                  tooltip: 'Toggle Replace',
                  splashRadius: 14,
                  onPressed: () => setState(() => _isReplaceExpanded = !_isReplaceExpanded),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 16),
                  color: Colors.white70,
                  tooltip: 'Refresh Search',
                  splashRadius: 14,
                  onPressed: _performSearch,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: border),

          // Inputs
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                // Search Input Box
                _buildSearchInputBox(),
                if (_isReplaceExpanded) ...[
                  const SizedBox(height: 6),
                  _buildReplaceInputBox(),
                ],
              ],
            ),
          ),

          // Search Progress or Summary
          if (_isSearching)
            const LinearProgressIndicator(minHeight: 2)
          else if (_queryController.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Text(
                '$_totalMatches results in ${_resultsByFile.length} files',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ),

          // Results Tree
          Expanded(
            child: _resultsByFile.isEmpty
                ? const Center(
                    child: Text('No results found', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  )
                : ListView.builder(
                    itemCount: _resultsByFile.keys.length,
                    itemBuilder: (context, index) {
                      final filePath = _resultsByFile.keys.elementAt(index);
                      final matches = _resultsByFile[filePath]!;
                      return _buildFileResultTile(filePath, matches);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchInputBox() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF252526),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF3C3C3C)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _queryController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              onSubmitted: (_) => _performSearch(),
              decoration: const InputDecoration(
                hintText: 'Search',
                hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
            ),
          ),
          _buildToggleOption(
            label: 'Aa',
            isActive: _matchCase,
            tooltip: 'Match Case (Alt+C)',
            onTap: () {
              setState(() => _matchCase = !_matchCase);
              _performSearch();
            },
          ),
          _buildToggleOption(
            label: r'\b',
            isActive: _matchWholeWord,
            tooltip: 'Match Whole Word (Alt+W)',
            onTap: () {
              setState(() => _matchWholeWord = !_matchWholeWord);
              _performSearch();
            },
          ),
          _buildToggleOption(
            label: '.*',
            isActive: _useRegex,
            tooltip: 'Use Regular Expression (Alt+R)',
            onTap: () {
              setState(() => _useRegex = !_useRegex);
              _performSearch();
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildReplaceInputBox() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF252526),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF3C3C3C)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _replaceController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Replace',
                hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.find_replace, size: 16),
            color: Colors.white70,
            tooltip: 'Replace All in Files',
            splashRadius: 14,
            onPressed: _replaceAllInFiles,
          ),
        ],
      ),
    );
  }

  Widget _buildToggleOption({
    required String label,
    required bool isActive,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF0078D4) : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFileResultTile(String filePath, List<SearchMatchResult> matches) {
    final fileName = p.basename(filePath);
    final relDir = p.dirname(p.relative(filePath, from: widget.projectRoot.path));

    return ExpansionTile(
      initiallyExpanded: true,
      tilePadding: const EdgeInsets.symmetric(horizontal: 10),
      childrenPadding: EdgeInsets.zero,
      dense: true,
      leading: const Icon(Icons.insert_drive_file_outlined, size: 14, color: Colors.white70),
      title: Row(
        children: [
          Text(fileName, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              relDir == '.' ? '' : relDir,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFF2D2D2D),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('${matches.length}', style: const TextStyle(color: Colors.white, fontSize: 10)),
          ),
        ],
      ),
      children: matches.map((m) {
        return InkWell(
          onTap: () => widget.onOpenFile(m.file, line: m.lineNumber),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            child: Row(
              children: [
                Text('${m.lineNumber}: ', style: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace')),
                Expanded(
                  child: Text(
                    m.lineText.trim(),
                    style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

