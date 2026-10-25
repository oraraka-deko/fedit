import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';

import '../models/git_models.dart';
import 'editor_session_manager.dart';

class CodeForgeDiffViewer extends StatefulWidget {
  final DiffDocumentInfo diffInfo;
  final VoidCallback? onClose;

  const CodeForgeDiffViewer({
    super.key,
    required this.diffInfo,
    this.onClose,
  });

  @override
  State<CodeForgeDiffViewer> createState() => _CodeForgeDiffViewerState();
}

class _CodeForgeDiffViewerState extends State<CodeForgeDiffViewer> {
  late final CodeForgeController _leftController;
  late final CodeForgeController _rightController;
  late final ScrollController _leftScroll;
  late final ScrollController _rightScroll;

  bool _isSyncingScroll = false;
  bool _isSideBySide = true;
  int _currentHunkIndex = 0;

  final List<int> _leftHunkStartLines = [];
  final List<int> _rightHunkStartLines = [];

  @override
  void initState() {
    super.initState();
    _leftController = CodeForgeController();
    _rightController = CodeForgeController();
    _leftController.text = widget.diffInfo.originalContent;
    _rightController.text = widget.diffInfo.modifiedContent;
    _leftScroll = ScrollController();
    _rightScroll = ScrollController();

    _leftScroll.addListener(_onLeftScroll);
    _rightScroll.addListener(_onRightScroll);

    _setupDiffs();
  }

  void _onLeftScroll() {
    if (_isSyncingScroll || !_rightScroll.hasClients) return;
    _isSyncingScroll = true;
    _rightScroll.jumpTo(_leftScroll.offset.clamp(0.0, _rightScroll.position.maxScrollExtent));
    _isSyncingScroll = false;
  }

  void _onRightScroll() {
    if (_isSyncingScroll || !_leftScroll.hasClients) return;
    _isSyncingScroll = true;
    _leftScroll.jumpTo(_rightScroll.offset.clamp(0.0, _leftScroll.position.maxScrollExtent));
    _isSyncingScroll = false;
  }

  void _setupDiffs() {
    final hunks = widget.diffInfo.fileDiff.hunks;
    final leftRemovedDecorations = <LineDecoration>[];
    final leftGutterDecorations = <GutterDecoration>[];
    final rightAddedDecorations = <LineDecoration>[];
    final rightGutterDecorations = <GutterDecoration>[];

    _leftHunkStartLines.clear();
    _rightHunkStartLines.clear();

    const removedColor = Color(0xFFE53935);
    const addedColor = Color(0xFF4CAF50);

    int idx = 0;
    for (final hunk in hunks) {
      if (hunk.oldLines > 0) {
        _leftHunkStartLines.add((hunk.oldStart - 1).clamp(0, 999999));
      }
      if (hunk.newLines > 0) {
        _rightHunkStartLines.add((hunk.newStart - 1).clamp(0, 999999));
      }

      for (final line in hunk.lines) {
        if (line.type == GitDiffLineType.deletion && line.oldLineNumber != null) {
          final lineIdx = (line.oldLineNumber! - 1).clamp(0, 999999);
          leftRemovedDecorations.add(LineDecoration(
            id: 'diff-del-$idx',
            startLine: lineIdx,
            endLine: lineIdx,
            type: LineDecorationType.background,
            color: removedColor.withValues(alpha: 0.2),
          ));
          leftGutterDecorations.add(GutterDecoration(
            id: 'diff-gutter-del-$idx',
            startLine: lineIdx,
            endLine: lineIdx,
            type: GutterDecorationType.colorBar,
            color: removedColor,
          ));
          idx++;
        } else if (line.type == GitDiffLineType.addition && line.newLineNumber != null) {
          final lineIdx = (line.newLineNumber! - 1).clamp(0, 999999);
          rightAddedDecorations.add(LineDecoration(
            id: 'diff-add-$idx',
            startLine: lineIdx,
            endLine: lineIdx,
            type: LineDecorationType.background,
            color: addedColor.withValues(alpha: 0.2),
          ));
          rightGutterDecorations.add(GutterDecoration(
            id: 'diff-gutter-add-$idx',
            startLine: lineIdx,
            endLine: lineIdx,
            type: GutterDecorationType.colorBar,
            color: addedColor,
          ));
          idx++;
        }
      }
    }

    // Apply decorations
    for (final d in leftRemovedDecorations) {
      _leftController.addLineDecoration(d);
    }
    for (final g in leftGutterDecorations) {
      _leftController.addGutterDecoration(g);
    }

    for (final d in rightAddedDecorations) {
      _rightController.addLineDecoration(d);
    }
    for (final g in rightGutterDecorations) {
      _rightController.addGutterDecoration(g);
    }
  }

  void _nextHunk() {
    if (_rightHunkStartLines.isEmpty) return;
    _currentHunkIndex = (_currentHunkIndex + 1) % _rightHunkStartLines.length;
    _scrollToHunk(_currentHunkIndex);
  }

  void _prevHunk() {
    if (_rightHunkStartLines.isEmpty) return;
    _currentHunkIndex = (_currentHunkIndex - 1 + _rightHunkStartLines.length) % _rightHunkStartLines.length;
    _scrollToHunk(_currentHunkIndex);
  }

  void _scrollToHunk(int index) {
    if (index >= 0 && index < _rightHunkStartLines.length) {
      final rightLine = _rightHunkStartLines[index];
      try {
        _rightController.scrollToLine(rightLine);
      } catch (_) {}
    }
    if (index >= 0 && index < _leftHunkStartLines.length) {
      final leftLine = _leftHunkStartLines[index];
      try {
        _leftController.scrollToLine(leftLine);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _leftScroll.removeListener(_onLeftScroll);
    _rightScroll.removeListener(_onRightScroll);
    _leftScroll.dispose();
    _rightScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.diffInfo;
    final totalChanges = info.fileDiff.insertions + info.fileDiff.deletions;

    final baseTextStyle = GoogleFonts.jetBrainsMono(
      fontSize: 13.5,
      height: 1.5,
      fontWeight: FontWeight.w400,
    );

    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      body: SafeArea(
        child: Column(
          children: [
            // Top Toolbar (Header)
            _buildDiffHeader(info, totalChanges),
            const Divider(height: 1, color: Color(0xFF282828)),

            // Diff Body
            Expanded(
              child: _isSideBySide
                  ? _buildSideBySideView(baseTextStyle)
                  : _buildInlineView(baseTextStyle),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiffHeader(DiffDocumentInfo info, int totalChanges) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: const Color(0xFF181818),
      child: Row(
        children: [
          // File title and change status badge
          Icon(Icons.difference_outlined, size: 16, color: Colors.blueAccent),
          const SizedBox(width: 8),
          Text(
            '${info.relativePath} ${info.isStaged ? "(Index)" : "(Working Tree)"}',
            style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              '$totalChanges, M',
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),

          const Spacer(),

          // Hunk Navigation
          IconButton(
            icon: const Icon(Icons.arrow_upward, size: 16),
            tooltip: 'Previous Change',
            color: Colors.white70,
            splashRadius: 14,
            onPressed: _prevHunk,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_downward, size: 16),
            tooltip: 'Next Change',
            color: Colors.white70,
            splashRadius: 14,
            onPressed: _nextHunk,
          ),

          // Toggle Side by Side vs Inline
          IconButton(
            icon: Icon(_isSideBySide ? Icons.splitscreen : Icons.view_headline, size: 16),
            tooltip: _isSideBySide ? 'Switch to Inline View' : 'Switch to Side by Side View',
            color: Colors.white70,
            splashRadius: 14,
            onPressed: () => setState(() => _isSideBySide = !_isSideBySide),
          ),

          if (widget.onClose != null)
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              tooltip: 'Close Diff',
              color: Colors.white70,
              splashRadius: 14,
              onPressed: widget.onClose,
            ),
        ],
      ),
    );
  }

  Widget _buildSideBySideView(TextStyle baseTextStyle) {
    return Row(
      children: [
        // Left Pane: Original / HEAD
        Expanded(
          child: Column(
            children: [
              Container(
                height: 24,
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                color: const Color(0xFF252526),
                child: const Text(
                  'Original (HEAD / Base)',
                  style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w500),
                ),
              ),
              Expanded(
                child: CodeForge(
                  controller: _leftController,
                  verticalScrollController: _leftScroll,
                  readOnly: true,
                  language: langDart,
                  editorTheme: atomOneDarkTheme,
                  textStyle: baseTextStyle,
                  gutterStyle: GutterStyle(
                    backgroundColor: const Color(0xFF1E1E1E),
                    gutterWidth: 50,
                    lineNumberStyle: baseTextStyle.copyWith(fontSize: 11, color: Colors.white38),
                  ),
                ),
              ),
            ],
          ),
        ),

        const VerticalDivider(width: 1, thickness: 1, color: Color(0xFF282828)),

        // Right Pane: Modified / Working Tree
        Expanded(
          child: Column(
            children: [
              Container(
                height: 24,
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                color: const Color(0xFF252526),
                child: Text(
                  widget.diffInfo.isStaged ? 'Staged (Index)' : 'Working Tree (Modified)',
                  style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w500),
                ),
              ),
              Expanded(
                child: CodeForge(
                  controller: _rightController,
                  verticalScrollController: _rightScroll,
                  readOnly: false,
                  language: langDart,
                  editorTheme: atomOneDarkTheme,
                  textStyle: baseTextStyle,
                  gutterStyle: GutterStyle(
                    backgroundColor: const Color(0xFF1E1E1E),
                    gutterWidth: 50,
                    lineNumberStyle: baseTextStyle.copyWith(fontSize: 11, color: Colors.white38),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInlineView(TextStyle baseTextStyle) {
    return CodeForge(
      controller: _rightController,
      verticalScrollController: _rightScroll,
      readOnly: false,
      language: langDart,
      editorTheme: atomOneDarkTheme,
      textStyle: baseTextStyle,
      gutterStyle: GutterStyle(
        backgroundColor: const Color(0xFF1E1E1E),
        gutterWidth: 50,
        lineNumberStyle: baseTextStyle.copyWith(fontSize: 11, color: Colors.white38),
      ),
    );
  }
}
