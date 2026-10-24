// drawershell.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'fileexplorerpanel.dart';
import 'dynamic_code_editor_tab_bar.dart';
import 'editor_session_manager.dart';
import 'session_scope.dart';

typedef EditorWidgetBuilder = Widget Function(
  File file, {
  String? tabId,
  bool? isActive,
});

class EditorWithExplorerShell extends StatefulWidget {
  final Directory projectRoot;
  final Function editorBuilder;
  final Widget aisidebar;
  final File? initialFile;

  const EditorWithExplorerShell({
    super.key,
    required this.projectRoot,
    required this.editorBuilder,
    required this.aisidebar,
    this.initialFile,
  });

  @override
  State<EditorWithExplorerShell> createState() => _EditorWithExplorerShellState();
}

class _EditorWithExplorerShellState extends State<EditorWithExplorerShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final EditorSessionManager _session;

  // Sidebar width states
  double _sidebarWidth = 280;
  double _aiSidebarWidth = 360;
  bool _showAiSidebar = true;

  @override
  void initState() {
    super.initState();
    _session = EditorSessionManager();
    if (widget.initialFile != null) {
      _session.openFile(widget.initialFile!);
    }
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  Widget _buildEditor(File file, {String? tabId, bool? isActive}) {
    if (widget.editorBuilder is Widget Function(File, {String? tabId, bool? isActive})) {
      return (widget.editorBuilder as Widget Function(File, {String? tabId, bool? isActive}))(
        file,
        tabId: tabId,
        isActive: isActive,
      );
    } else if (widget.editorBuilder is Widget Function(File)) {
      return (widget.editorBuilder as Widget Function(File))(file);
    }
    try {
      return (widget.editorBuilder as dynamic)(file, tabId: tabId, isActive: isActive) as Widget;
    } catch (_) {
      return (widget.editorBuilder as dynamic)(file) as Widget;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SessionScope(
      session: _session,
      child: ListenableBuilder(
        listenable: _session,
        builder: (context, _) {
          final session = SessionScope.of(context);
          final activeTab = session.activeDocument?.tab;

          final activeIndex = session.documents
              .indexWhere((d) => d.tab.id == session.activeTabId);
          final safeIndex = activeIndex == -1 ? 0 : activeIndex;

          final Widget editorBody = session.documents.isEmpty
              ? const Center(
                  child: Text(
                    "No file selected\nOpen a file or create a new tab",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : IndexedStack(
                  index: safeIndex,
                  children: [
                    for (final doc in session.documents)
                      KeyedSubtree(
                        key: ValueKey(doc.tab.id),
                        child: doc.file == null
                            ? const Center(
                                child: Text(
                                  "No file selected\nOpen a file or create a new tab",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.white54),
                                ),
                              )
                            : _buildEditor(
                                doc.file!,
                                tabId: doc.tab.id,
                                isActive: doc.tab.id == session.activeTabId,
                              ),
                      ),
                  ],
                );

          final mainEditorPane = Column(
            children: [
              if (session.tabs.isNotEmpty)
                CodeForgeTabBar(
                  tabs: session.tabs,
                  activeTabId: session.activeTabId,
                  onTabSelected: session.selectTab,
                  onTabClosed: session.closeTab,
                  onTabsReordered: session.reorderTabs,
                  onNewTab: session.openNewEmptyTab,
                ),
              Expanded(child: editorBody),
            ],
          );

          return LayoutBuilder(
            builder: (context, c) {
              final isSmall = c.maxWidth < 900;
              final explorer = FileExplorerPanel(
                root: widget.projectRoot,
                sidebarWidth: isSmall ? 280 : _sidebarWidth,
                onOpenFile: (file) {
                  session.openFile(file);
                  if (isSmall) Navigator.of(context).maybePop();
                },
              );

              if (isSmall) {
                return Scaffold(
                  key: _scaffoldKey,
                  appBar: AppBar(
                    title: Text(activeTab?.title ?? 'Editor'),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.chat_bubble_outline),
                        onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                      ),
                    ],
                  ),
                  drawer: Drawer(child: SafeArea(child: explorer)),
                  endDrawer: Drawer(child: SafeArea(child: widget.aisidebar)),
                  body: mainEditorPane,
                );
              }

              final minW = 220.0;
              final maxW = (c.maxWidth * 0.55).clamp(260.0, 520.0);
              final aiMinW = 280.0;
              final aiMaxW = (c.maxWidth * 0.45).clamp(320.0, 640.0);

              return Scaffold(
                body: SafeArea(
                  child: Column(
                    children: [
                      Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        color: const Color(0xFF151A1E),
                        child: Row(
                          children: [
                            Text(
                              activeTab?.title ?? 'Editor',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: Icon(
                                _showAiSidebar ? Icons.close : Icons.open_in_new,
                                size: 18,
                              ),
                              onPressed: () => setState(() => _showAiSidebar = !_showAiSidebar),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            SizedBox(
                              width: _sidebarWidth.clamp(minW, maxW),
                              child: explorer,
                            ),
                            _ResizeHandle(
                              onDrag: (dx) => setState(() {
                                _sidebarWidth = (_sidebarWidth + dx).clamp(minW, maxW);
                              }),
                            ),
                            const VerticalDivider(width: 1, thickness: 1),
                            Expanded(child: mainEditorPane),
                            if (_showAiSidebar) ...[
                              const VerticalDivider(width: 1, thickness: 1),
                              _ResizeHandle(
                                onDrag: (dx) => setState(() {
                                  _aiSidebarWidth = (_aiSidebarWidth - dx).clamp(aiMinW, aiMaxW);
                                }),
                              ),
                              SizedBox(
                                width: _aiSidebarWidth.clamp(aiMinW, aiMaxW),
                                child: widget.aisidebar,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ResizeHandle extends StatelessWidget {
  final void Function(double dx) onDrag;
  const _ResizeHandle({required this.onDrag});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: SizedBox(
          width: 10,
          child: Center(
            child: Container(
              width: 2,
              height: 28,
              color: Colors.white24,
            ),
          ),
        ),
      ),
    );
  }
}

