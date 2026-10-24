import 'package:flutter/material.dart';
import 'ai_sidebar.dart';
import '../ai/chat_service.dart';
import '../ai/config.dart';
import 'repo_browser.dart';
class RepoBrowserScaffold extends StatefulWidget {
  final String path; // The Root Path downloaded
  final String title;

  const RepoBrowserScaffold({
    super.key,
    required this.path,
    required this.title,
  });

  @override
  State<RepoBrowserScaffold> createState() => _RepoBrowserScaffoldState();
}

class _RepoBrowserScaffoldState extends State<RepoBrowserScaffold> {       
  ChatService? _chatService;
  late final VoidCallback _configReloadListener;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  double _aiSidebarWidth = 360;
  bool _showAiSidebar = true;

  @override
  void initState() {
    super.initState();
    _configReloadListener = () => _initAI();
    Config.reloadNotifier.addListener(_configReloadListener);
    _initAI();
  }

  Future<void> _initAI() async {
    final cfg = await Config.load();
    if (!mounted) return;
    final newService = ChatService(cfg, widget.path);
    setState(() {
      _chatService?.dispose();
      _chatService = newService;
    });
  }

  @override
  void dispose() {
    Config.reloadNotifier.removeListener(_configReloadListener);
    _chatService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmall = constraints.maxWidth < 1100;
        Widget aiPanelBuilder() {
          if (_chatService == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return AiSidebar(chatService: _chatService!);
        }

        final sideWidget = aiPanelBuilder();
        final browser = RepoBrowser(
          path: widget.path,
          aiSidebarBuilder: aiPanelBuilder,
        );

        if (isSmall) {
          return Scaffold(
            key: _scaffoldKey,
            appBar: AppBar(
              actions: [
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline),
                  onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                ),
              ],
            ),
            body: browser,
            endDrawer: Drawer(child: SafeArea(child: sideWidget)),
          );
        }

        final minW = 280.0;
        final maxW = (constraints.maxWidth * 0.42).clamp(320.0, 640.0);

        return Scaffold(
          key: _scaffoldKey,
          appBar: AppBar(
            actions: [
              IconButton(
                icon: Icon(
                  _showAiSidebar ? Icons.close : Icons.open_in_new,
                ),
                onPressed: () {
                  setState(() {
                    _showAiSidebar = !_showAiSidebar;
                  });
                },
              ),
            ],
          ),
          body: Row(
            children: [
              Expanded(child: browser),
              if (_showAiSidebar) ...[
                _ResizeHandle(
                  onDrag: (dx) {
                    setState(() {
                      _aiSidebarWidth = (_aiSidebarWidth - dx).clamp(minW, maxW);
                    });
                  },
                ),
                SizedBox(
                  width: _aiSidebarWidth.clamp(minW, maxW),
                  child: sideWidget,
                ),
              ],
            ],
          ),
        );
      },
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
