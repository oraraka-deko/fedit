import 'package:code_forge/code_forge.dart';
import 'package:code_forge/code_forge/controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Represents the active functional group tab for quick category navigation.
enum KeyboardBarCategory {
  navigation('Nav', Icons.navigation_rounded),
  editing('Edit', Icons.edit_note_rounded),
  symbols('Code', Icons.code_rounded),
  lsp('LSP & AI', Icons.psychology_alt_rounded);

  final String label;
  final IconData icon;
  const KeyboardBarCategory(this.label, this.icon);
}

/// A compact, touch-optimized suggestion and utility keyboard accessory bar
/// tailored for mobile/Android code editors using [CodeForgeController].
class CodeForgeVirtualKeyboardBar extends StatefulWidget {
  final CodeForgeController controller;
  final UndoRedoController undoRedoController;
  final VoidCallback? onSearchRequested;
  final VoidCallback? onMultiCursorToggle;

  const CodeForgeVirtualKeyboardBar({
    super.key,
    required this.controller,
    required this.undoRedoController,
    this.onSearchRequested,
    this.onMultiCursorToggle,
  });

  @override
  State<CodeForgeVirtualKeyboardBar> createState() =>
      _CodeForgeVirtualKeyboardBarState();
}

class _CodeForgeVirtualKeyboardBarState
    extends State<CodeForgeVirtualKeyboardBar> {
  KeyboardBarCategory _activeCategory = KeyboardBarCategory.navigation;

  // Latchable modifier keys to emulate Ctrl, Shift, Alt combinations
  bool _isCtrlActive = false;
  bool _isShiftActive = false;
  bool _isAltActive = false;

  void _triggerHaptic() {
    HapticFeedback.selectionClick();
  }

  void _resetTransientModifiers() {
    // If shift was active for a single keystroke, auto-release or leave latched
    // Here we preserve explicit latching for user control.
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF1E1E24) : const Color(0xFFF1F3F5);
    final borderColor = isDark ? const Color(0xFF2E2E38) : const Color(0xFFDFE2E6);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          top: BorderSide(color: borderColor, width: 1.0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Row 1: Modifier bar (Ctrl, Shift, Alt) + Category quick selector
            _buildModifierAndCategoryRow(isDark),

            const Divider(height: 1, thickness: 0.5),

            // Row 2: Category dynamic actionable key strip
            SizedBox(
              height: 48,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _buildCategoryContent(isDark),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Top Row: Sticky Modifiers and Category Tabs
  Widget _buildModifierAndCategoryRow(bool isDark) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Row(
        children: [
          // Sticky Modifiers
          _buildModifierChip(
            label: 'CTRL',
            isActive: _isCtrlActive,
            onTap: () => setState(() => _isCtrlActive = !_isCtrlActive),
          ),
          const SizedBox(width: 4),
          _buildModifierChip(
            label: 'SHIFT',
            isActive: _isShiftActive,
            onTap: () => setState(() => _isShiftActive = !_isShiftActive),
          ),
          const SizedBox(width: 4),
          _buildModifierChip(
            label: 'ALT',
            isActive: _isAltActive,
            onTap: () => setState(() => _isAltActive = !_isAltActive),
          ),

          const VerticalDivider(width: 16, thickness: 1, indent: 4, endIndent: 4),

          // Scrollable category switches
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: KeyboardBarCategory.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 4),
              itemBuilder: (context, index) {
                final cat = KeyboardBarCategory.values[index];
                final isSelected = _activeCategory == cat;
                return ChoiceChip(
                  labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                  avatar: Icon(
                    cat.icon,
                    size: 14,
                    color: isSelected
                        ? Colors.white
                        : (isDark ? Colors.grey[400] : Colors.grey[700]),
                  ),
                  label: Text(
                    cat.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected
                          ? Colors.white
                          : (isDark ? Colors.grey[300] : Colors.black87),
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: Theme.of(context).colorScheme.primary,
                  backgroundColor: isDark ? const Color(0xFF282832) : Colors.white,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onSelected: (val) {
                    if (val) {
                      _triggerHaptic();
                      setState(() => _activeCategory = cat);
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Modifier chip with active state visual highlight
  Widget _buildModifierChip({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    final activeColor = Theme.of(context).colorScheme.secondary;
    return InkWell(
      onTap: () {
        _triggerHaptic();
        onTap();
      },
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isActive ? activeColor : Colors.grey.withOpacity(0.4),
            width: 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            color: isActive ? Colors.white : Colors.grey[500],
          ),
        ),
      ),
    );
  }

  /// Selects the toolstrip corresponding to the selected category
  Widget _buildCategoryContent(bool isDark) {
    switch (_activeCategory) {
      case KeyboardBarCategory.navigation:
        return _buildNavigationStrip();
      case KeyboardBarCategory.editing:
        return _buildEditingStrip();
      case KeyboardBarCategory.symbols:
        return _buildSymbolsStrip();
      case KeyboardBarCategory.lsp:
        return _buildLspStrip();
    }
  }

  /// Strip 1: Navigation keys (Arrows, Home, End, Word navigation)
  Widget _buildNavigationStrip() {
    return ListView(
      key: const ValueKey('nav_strip'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      children: [
        _buildActionKey(
          icon: Icons.keyboard_tab_rounded,
          label: 'Tab',
          onTap: () => widget.controller.insertAtCurrentCursor('  '),
        ),
        _buildActionKey(
          icon: Icons.arrow_back_rounded,
          label: 'Left',
          onTap: () {
            if (_isCtrlActive) {
              widget.controller.pressLetfArrowKey(isShiftPressed: _isShiftActive);
            } else {
              widget.controller.pressLetfArrowKey(isShiftPressed: _isShiftActive);
            }
          },
        ),
        _buildActionKey(
          icon: Icons.arrow_forward_rounded,
          label: 'Right',
          onTap: () {
            if (_isCtrlActive) {
              widget.controller.pressRightArrowKey(isShiftPressed: _isShiftActive);
            } else {
              widget.controller.pressRightArrowKey(isShiftPressed: _isShiftActive);
            }
          },
        ),
        _buildActionKey(
          icon: Icons.arrow_upward_rounded,
          label: 'Up',
          onTap: () {
            if (_isCtrlActive && _isShiftActive) {
              widget.controller.moveLineUp();
            } else {
              widget.controller.pressUpArrowKey(isShiftPressed: _isShiftActive);
            }
          },
        ),
        _buildActionKey(
          icon: Icons.arrow_downward_rounded,
          label: 'Down',
          onTap: () {
            if (_isCtrlActive && _isShiftActive) {
              widget.controller.moveLineDown();
            } else {
              widget.controller.pressDownArrowKey(isShiftPressed: _isShiftActive);
            }
          },
        ),
        _buildActionKey(
          icon: Icons.first_page_rounded,
          label: 'Home',
          onTap: () {
            if (_isCtrlActive) {
              widget.controller.pressDocumentHomeKey(isShiftPressed: _isShiftActive);
            } else {
              widget.controller.pressHomeKey(isShiftPressed: _isShiftActive);
            }
          },
        ),
        _buildActionKey(
          icon: Icons.last_page_rounded,
          label: 'End',
          onTap: () {
            if (_isCtrlActive) {
              widget.controller.pressDocumentEndKey(isShiftPressed: _isShiftActive);
            } else {
              widget.controller.pressEndKey(isShiftPressed: _isShiftActive);
            }
          },
        ),
      ],
    );
  }

  /// Strip 2: Clipboard & Editing (Copy, Paste, Cut, Duplicate, Select All, Undo/Redo)
  Widget _buildEditingStrip() {
    return ListView(
      key: const ValueKey('edit_strip'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      children: [if (widget.undoRedoController.canRedo)
          _buildActionKey(
          icon: Icons.redo,
          label: 'Redo',
          onTap: () { widget.undoRedoController.isUndoRedoInProgress?null:widget.undoRedoController.redo();setState(() {
            
          });
          }, 
        ),
        if (widget.undoRedoController.canUndo)
          _buildActionKey(
          icon: Icons.undo,
          label: 'Undo',
          onTap: () { widget.undoRedoController.isUndoRedoInProgress?null: widget.undoRedoController.undo(); setState(() {
            
          });
   } ),
        _buildActionKey(
          icon: Icons.select_all_rounded,
          label: 'Select All',
          onTap: () => widget.controller.selectAll(),
        ),
        _buildActionKey(
          icon: Icons.copy_rounded,
          label: 'Copy',
          onTap: () => widget.controller.copy(),
        ),
        _buildActionKey(
          icon: Icons.content_cut_rounded,
          label: 'Cut',
          onTap: () => widget.controller.cut(),
        ),
        _buildActionKey(
          icon: Icons.paste_rounded,
          label: 'Paste',
          onTap: () => widget.controller.paste(),
        ),
        _buildActionKey(
          icon: Icons.content_copy_rounded,
          label: 'Dup Line',
          onTap: () => widget.controller.duplicateLine(),
        ),
        _buildActionKey(
          icon: Icons.backspace_outlined,
          label: 'Backsp',
          onTap: () => widget.controller.backspace(),
        ),
        _buildActionKey(
          icon: Icons.delete_outline_rounded,
          label: 'Del',
          onTap: () => widget.controller.delete(),
        ),
        _buildActionKey(
          icon: Icons.search_rounded,
          label: 'Find',
          onTap: () {
            if (widget.onSearchRequested != null) {
              widget.onSearchRequested!();
            }
          },
        ),
      ],
    );
  }

  /// Strip 3: Code symbols with auto-closing pairs support
  Widget _buildSymbolsStrip() {
    final List<({String display, String insert})> symbols = [
      (display: '{}', insert: '{\n  \n}'),
      (display: '()', insert: '()'),
      (display: '[]', insert: '[]'),
      (display: '=>', insert: ' => '),
      (display: ';', insert: ';'),
      (display: '=', insert: ' = '),
      (display: '"', insert: '""'),
      (display: '\'', insert: '\'\''),
      (display: '<>', insert: '<>'),
      (display: ':', insert: ': '),
      (display: '&&', insert: ' && '),
      (display: '||', insert: ' || '),
      (display: '!', insert: '!'),
      (display: '?', insert: '?'),
      (display: '.', insert: '.'),
      (display: ',', insert: ', '),
    ];

    return ListView.builder(
      key: const ValueKey('symbols_strip'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      itemCount: symbols.length,
      itemBuilder: (context, index) {
        final item = symbols[index];
        return _buildTextKey(
          text: item.display,
          onTap: () => widget.controller.insertAtCurrentCursor(item.insert),
        );
      },
    );
  }

  /// Strip 4: LSP Actions, Inlay Hints, Code Actions & Multi-cursor
  Widget _buildLspStrip() {
    return ListView(
      key: const ValueKey('lsp_strip'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      children: [
        _buildActionKey(
          icon: Icons.lightbulb_outline_rounded,
          label: 'Quick Fix',
          onTap: () => widget.controller.getCodeAction(),
        ),
        _buildActionKey(
          icon: Icons.info_outline_rounded,
          label: 'Signature',
          onTap: () => widget.controller.callSignatureHelp(),
        ),
        _buildActionKey(
          icon: Icons.subtitles_outlined,
          label: 'Hints',
          onTap: () => widget.controller.showInlayHints(),
        ),
        _buildActionKey(
          icon: Icons.unfold_more_rounded,
          label: 'Unfold All',
          onTap: () => widget.controller.unfoldAll(),
        ),
        _buildActionKey(
          icon: Icons.unfold_less_rounded,
          label: 'Fold All',
          onTap: () => widget.controller.foldAll(),
        ),
        _buildActionKey(
          icon: Icons.control_point_duplicate_rounded,
          label: 'Clear Cursors',
          onTap: () => widget.controller.clearMultiCursors(),
        ),
        _buildActionKey(
          icon: Icons.save_outlined,
          label: 'Save',
          onTap: () => widget.controller.saveFile(),
        ),
      ],
    );
  }

  /// Reusable UI button for Icon + Label keys
  Widget _buildActionKey({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final btnBg = isDark ? const Color(0xFF2B2B36) : Colors.white;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: btnBg,
        elevation: 0.5,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            _triggerHaptic();
            onTap();
          },
          child: Container(
            constraints: const BoxConstraints(minWidth: 46),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Reusable UI button for pure text/code syntax keys
  Widget _buildTextKey({
    required String text,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final btnBg = isDark ? const Color(0xFF2B2B36) : Colors.white;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: btnBg,
        elevation: 0.5,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            _triggerHaptic();
            onTap();
          },
          child: Container(
            alignment: Alignment.center,
            constraints: const BoxConstraints(minWidth: 42),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              text,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}