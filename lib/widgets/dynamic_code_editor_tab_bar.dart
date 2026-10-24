import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Model representing an open editor tab.
class EditorTabItem {
  final String id;
  String title;
  String? filePath;
  IconData? icon;
  bool isDirty; // Modified indicator dot
  bool isPinned;

  EditorTabItem({
    required this.id,
    required this.title,
    this.filePath,
    this.icon,
    this.isDirty = false,
    this.isPinned = false,
  });

  EditorTabItem copyWith({
    String? id,
    String? title,
    String? filePath,
    IconData? icon,
    bool? isDirty,
    bool? isPinned,
  }) {
    return EditorTabItem(
      id: id ?? this.id,
      title: title ?? this.title,
      filePath: filePath ?? this.filePath,
      icon: icon ?? this.icon,
      isDirty: isDirty ?? this.isDirty,
      isPinned: isPinned ?? this.isPinned,
    );
  }
}

/// A touch-optimized, dynamic-width, draggable reorderable TabBar tailored for
/// Android screens and mobile code editors.
class CodeForgeTabBar extends StatefulWidget {
  final List<EditorTabItem> tabs;
  final String activeTabId;
  final ValueChanged<String> onTabSelected;
  final ValueChanged<String> onTabClosed;
  final VoidCallback onNewTab;
  final void Function(int oldIndex, int newIndex)? onTabsReordered;
  final ValueChanged<String>? onTabPinned;

  const CodeForgeTabBar({
    super.key,
    required this.tabs,
    required this.activeTabId,
    required this.onTabSelected,
    required this.onTabClosed,
    required this.onNewTab,
    this.onTabsReordered,
    this.onTabPinned,
  });

  @override
  State<CodeForgeTabBar> createState() => _CodeForgeTabBarState();
}

class _CodeForgeTabBarState extends State<CodeForgeTabBar> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _tabKeys = {};

  @override
  void didUpdateWidget(covariant CodeForgeTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeTabId != oldWidget.activeTabId) {
      _scrollToActiveTab();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToActiveTab() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final activeKey = _tabKeys[widget.activeTabId];
      if (activeKey != null && activeKey.currentContext != null) {
        Scrollable.ensureVisible(
          activeKey.currentContext!,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOutCubic,
          alignment: 0.5, // Center the active tab in view
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final barBackground = isDark ? const Color(0xFF18181D) : const Color(0xFFE9ECEF);
    final borderColor = isDark ? const Color(0xFF282832) : const Color(0xFFCED4DA);

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: barBackground,
        border: Border(
          bottom: BorderSide(color: borderColor, width: 1.0),
        ),
      ),
      child: Row(
        children: [
          // Scrollable and Reorderable Tabs section
          Expanded(
            child: Theme(
              // Remove the default reorder ghost shadow canvas color
              data: theme.copyWith(
                canvasColor: Colors.transparent,
                shadowColor: Colors.transparent,
              ),
              child: ReorderableListView.builder(
                scrollController: _scrollController,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: widget.tabs.length,
                onReorder: (oldIndex, newIndex) {
                  HapticFeedback.mediumImpact();
                  if (widget.onTabsReordered != null) {
                    widget.onTabsReordered!(oldIndex, newIndex);
                  }
                },
                proxyDecorator: (child, index, animation) {
                  return AnimatedBuilder(
                    animation: animation,
                    builder: (context, _) {
                      final double elevation = (animation.value * 8.0);
                      return Material(
                        elevation: elevation,
                        shadowColor: Colors.black45,
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.transparent,
                        child: child,
                      );
                    },
                  );
                },
                itemBuilder: (context, index) {
                  final tab = widget.tabs[index];
                  _tabKeys.putIfAbsent(tab.id, () => GlobalKey());

                  return ReorderableDelayedDragStartListener(
                    key: ValueKey(tab.id),
                    index: index,
                    enabled: true, // Long-press to initiate drag on mobile
                    child: _TabItemWidget(
                      key: _tabKeys[tab.id],
                      tab: tab,
                      isActive: tab.id == widget.activeTabId,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        widget.onTabSelected(tab.id);
                      },
                      onClose: () {
                        HapticFeedback.lightImpact();
                        widget.onTabClosed(tab.id);
                      },
                    ),
                  );
                },
              ),
            ),
          ),

          // Action button: Add new tab (+)
          _buildAddTabButton(isDark),
        ],
      ),
    );
  }

  Widget _buildAddTabButton(bool isDark) {
    return Container(
      width: 42,
      height: double.infinity,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: isDark ? const Color(0xFF282832) : const Color(0xFFCED4DA),
            width: 0.8,
          ),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            widget.onNewTab();
            _scrollToActiveTab();
          },
          child: Tooltip(
            message: 'New Tab',
            child: Icon(
              Icons.add_rounded,
              size: 20,
              color: isDark ? Colors.grey[400] : Colors.grey[700],
            ),
          ),
        ),
      ),
    );
  }
}

/// Single Tab widget with dynamic width, indicator for unsaved edits, and close button.
class _TabItemWidget extends StatelessWidget {
  final EditorTabItem tab;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _TabItemWidget({
    super.key,
    required this.tab,
    required this.isActive,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Theme color palette
    final activeBg = isDark ? const Color(0xFF1E1E24) : Colors.white;
    final inactiveBg = Colors.transparent;
    final activeIndicatorColor = theme.colorScheme.primary;

    final primaryTextColor = isDark ? Colors.white : const Color(0xFF212529);
    final inactiveTextColor = isDark ? const Color(0xFFA0A0AB) : const Color(0xFF6C757D);
    final borderColor = isDark ? const Color(0xFF2E2E38) : const Color(0xFFDEE2E6);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: isActive ? activeBg : inactiveBg,
        border: Border(
          right: BorderSide(color: borderColor, width: 0.8),
          top: isActive
              ? BorderSide(color: activeIndicatorColor, width: 2.5)
              : BorderSide.none,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(
              minWidth: 90,
              maxWidth: 220, // Avoid super wide tab stretching
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // File/Language icon (or fallback code icon)
                Icon(
                  tab.icon ?? _resolveFileIcon(tab.title),
                  size: 15,
                  color: isActive
                      ? activeIndicatorColor
                      : (isDark ? Colors.grey[500] : Colors.grey[600]),
                ),
                const SizedBox(width: 7),

                // File Name
                Flexible(
                  child: Text(
                    tab.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                      color: isActive ? primaryTextColor : inactiveTextColor,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Trailing Widget: Dirty (Unsaved) Dot or Close Button
                _buildTrailingAction(isDark),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrailingAction(bool isDark) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onClose,
      child: Container(
        padding: const EdgeInsets.all(3),
        child: tab.isDirty
            ? Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                  shape: BoxShape.circle,
                ),
              )
            : Icon(
                Icons.close_rounded,
                size: 15,
                color: isDark ? Colors.grey[500] : Colors.grey[600],
              ),
      ),
    );
  }

  IconData _resolveFileIcon(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.dart')) return Icons.flutter_dash;
    if (lower.endsWith('.js') || lower.endsWith('.ts')) return Icons.javascript;
    if (lower.endsWith('.json')) return Icons.data_object;
    if (lower.endsWith('.html') || lower.endsWith('.xml')) return Icons.html;
    if (lower.endsWith('.css')) return Icons.style;
    if (lower.endsWith('.md')) return Icons.notes;
    return Icons.insert_drive_file_outlined;
  }
}