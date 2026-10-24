// code_forge.dart
import 'dart:async';
import 'dart:io';
import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';

import 'codeforge_virtual_keyboard_accessory_bar.dart';
import 'session_scope.dart';

class AdvancedCodeEditor extends StatefulWidget {
  final File file;
  final String? tabId;
  final bool? isActive;
  final int? initialLine;
  final VoidCallback? onContentChanged;

  const AdvancedCodeEditor({
    required this.file,
    this.tabId,
    this.isActive,
    this.initialLine,
    this.onContentChanged,
    super.key,
  });

  @override
  State<AdvancedCodeEditor> createState() => _AdvancedCodeEditorState();
}

class _AdvancedCodeEditorState extends State<AdvancedCodeEditor> {
  late final UndoRedoController _undoController;
  late final CodeForgeController _codeForgeController;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _vScroll = ScrollController();

  int _lastRecordedLine = 0;
  bool _wasActive = false;

  @override
  void initState() {
    super.initState();
    _undoController = UndoRedoController();
    _codeForgeController = CodeForgeController();
    _lastRecordedLine = widget.initialLine ?? 0;

    _codeForgeController.addListener(_onEditorChanged);
    _vScroll.addListener(_onScrollChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreLastActiveLine();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      final session = SessionScope.of(context);
      final isCurrentlyActive = widget.isActive ??
          ((widget.tabId != null && session.activeTabId == widget.tabId) ||
              (session.activeDocument?.file?.path == widget.file.path));

      if (isCurrentlyActive && !_wasActive) {
        _wasActive = true;
        _restoreLastActiveLine();
      } else if (!isCurrentlyActive && _wasActive) {
        _saveCurrentLine();
        _wasActive = false;
      }
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant AdvancedCodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasActive = oldWidget.isActive ?? true;
    final isNowActive = widget.isActive ?? true;

    if (!wasActive && isNowActive) {
      _wasActive = true;
      _restoreLastActiveLine();
    } else if (wasActive && !isNowActive) {
      _saveCurrentLine();
      _wasActive = false;
    }
  }

  void _onEditorChanged() {
    _saveCurrentLine();
    widget.onContentChanged?.call();
  }

  void _onScrollChanged() {
    _saveCurrentLine();
  }

  int _computeCurrentLine() {
    try {
      final sel = _codeForgeController.selection;
      if (sel.isValid && sel.extentOffset >= 0 && _codeForgeController.lineCount > 0) {
        final line = _codeForgeController.getLineAtOffset(sel.extentOffset);
        if (line >= 0 && line < _codeForgeController.lineCount) {
          return line;
        }
      }
    } catch (_) {}

    if (_vScroll.hasClients && _vScroll.offset > 0) {
      const lineHeight = 21.0;
      final line = (_vScroll.offset / lineHeight).round();
      if (_codeForgeController.lineCount > 0) {
        return line.clamp(0, _codeForgeController.lineCount - 1);
      }
      return line;
    }
    return _lastRecordedLine;
  }

  void _saveCurrentLine() {
    if (!mounted) return;
    final line = _computeCurrentLine();
    _lastRecordedLine = line;

    try {
      final session = SessionScope.of(context);
      if (widget.tabId != null) {
        session.saveLastActiveLine(widget.tabId!, line);
      }
      session.saveLastActiveLineForFile(widget.file.path, line);
    } catch (_) {}
  }

  void _restoreLastActiveLine() {
    if (!mounted) return;
    int targetLine = widget.initialLine ?? _lastRecordedLine;

    try {
      final session = SessionScope.of(context);
      if (widget.tabId != null) {
        final saved = session.getLastActiveLine(widget.tabId!);
        if (saved > 0) targetLine = saved;
      } else {
        final saved = session.getLastActiveLineForFile(widget.file.path);
        if (saved > 0) targetLine = saved;
      }
    } catch (_) {}

    if (targetLine > 0) {
      _scrollToLineSafely(targetLine);
    }
  }

  void _scrollToLineSafely(int line) {
    if (!mounted || line < 0) return;

    void performScroll() {
      if (!mounted) return;
      try {
        final count = _codeForgeController.lineCount;
        if (count > 0) {
          final targetLine = line.clamp(0, count - 1);
          _codeForgeController.scrollToLine(targetLine);
        }
      } catch (_) {}
    }

    try {
      if (_codeForgeController.lineCount > 0) {
        final targetLine = line.clamp(0, _codeForgeController.lineCount - 1);
        _codeForgeController.scrollToLine(targetLine);
        return;
      }
    } catch (_) {}

    WidgetsBinding.instance.addPostFrameCallback((_) {
      performScroll();
      Future.delayed(const Duration(milliseconds: 120), () {
        performScroll();
      });
    });
  }

  @override
  void dispose() {
    _saveCurrentLine();
    _codeForgeController.removeListener(_onEditorChanged);
    _vScroll.removeListener(_onScrollChanged);
    _focusNode.dispose();
    _vScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _codeForgeController.setUndoController(_undoController);
  
    final absFilePath = widget.file.path;
    final baseTextStyle = GoogleFonts.jetBrainsMono(
      fontSize: 14,
      height: 1.5,
      fontWeight: FontWeight.w400,
    );

    return Scaffold(
      backgroundColor: const Color(0xFF282C34),
      body: SafeArea(
        child: Column(
          children: [
            // Editor Body
            Expanded(
              child: CodeForge(
                controller: _codeForgeController,
                undoController: _undoController,
                focusNode: _focusNode,
                verticalScrollController: _vScroll,
                filePath: absFilePath,
                language: langDart,
                editorTheme: atomOneDarkTheme,
                textStyle: baseTextStyle,
                enableFolding: true,
                enableGuideLines: true,
                readOnly: false,
                lineWrap: false,
                innerPadding: const EdgeInsets.only(top: 10),
                selectionStyle: CodeSelectionStyle(
                  cursorColor: Colors.amberAccent,
                  selectionColor: const Color(0xFF3E4451),
                  cursorBubbleColor: Colors.amberAccent,
                ),
                gutterStyle: GutterStyle(
                  backgroundColor: const Color(0xFF21252B),
                  gutterWidth: 55,
                  lineNumberStyle: baseTextStyle.copyWith(fontSize: 12),
                  activeLineNumberColor: Colors.white,
                  inactiveLineNumberColor: const Color(0xFF4B5263),
                  errorLineNumberColor: const Color(0xFFE53935),
                  warningLineNumberColor: const Color(0xFFFFA726),
                  foldedIcon: Icons.arrow_right_rounded,
                  unfoldedIcon: Icons.arrow_drop_down_rounded,
                  foldingIconSize: 20,
                  foldedIconColor: Colors.blueAccent,
                  unfoldedIconColor: Colors.white54,
                  foldedLineHighlightColor: Colors.blue.withValues(alpha: 0.1),
                ),
                suggestionStyle: SuggestionStyle(
                  elevation: 12,
                  backgroundColor: const Color(0xFF21252B),
                  focusColor: const Color(0xFF2C313A),
                  hoverColor: const Color(0xFF3E4451),
                  splashColor: Colors.blue.withValues(alpha: 0.2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: Color(0xFF181A1F), width: 1),
                  ),
                  textStyle: baseTextStyle.copyWith(
                    fontSize: 13,
                    color: Colors.white,
                  ),
                ),
                hoverDetailsStyle: HoverDetailsStyle(
                  elevation: 10,
                  backgroundColor: const Color(0xFF21252B),
                  focusColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  splashColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                    side: const BorderSide(color: Colors.blueAccent, width: 0.5),
                  ),
                  textStyle: baseTextStyle.copyWith(
                    fontSize: 12,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            // Keyboard Accessory Toolbar (Pinned cleanly above system IME)
            CodeForgeVirtualKeyboardBar(
              controller: _codeForgeController,
              undoRedoController: _undoController,
              onSearchRequested: () {
                
              },
            ),
          ],
        ),
      ),
    );
  }
}

