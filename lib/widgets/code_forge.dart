// code_forge.dart
import 'dart:io';
import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';

import 'codeforge_virtual_keyboard_accessory_bar.dart';

class AdvancedCodeEditor extends StatefulWidget {
  final File file;
  final VoidCallback? onContentChanged;

  const AdvancedCodeEditor({
    required this.file,
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

  @override
  void initState() {
    super.initState();
    _undoController = UndoRedoController();
    _codeForgeController = CodeForgeController();
  
  }

  @override
  void dispose() {
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