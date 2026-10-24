import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class FileExplorerPanel extends StatefulWidget {
  final Directory root;
  final double sidebarWidth;
  final ValueChanged<File> onOpenFile;

  const FileExplorerPanel({
    super.key,
    required this.root,
    required this.sidebarWidth,
    required this.onOpenFile,
  });

  @override
  State<FileExplorerPanel> createState() => _FileExplorerPanelState();
}

class _FileExplorerPanelState extends State<FileExplorerPanel> {
  late final FsNode _rootNode;

  @override
  void initState() {
    super.initState();
    _rootNode = FsNode.dir(widget.root.path)..isExpanded = true;
    _loadChildren(_rootNode);
  }

  Future<void> _loadChildren(FsNode node) async {
    if (!node.isDir || node.isLoading) return;
    if (node.children != null) return;

    setState(() => node.isLoading = true);

    try {
      final dir = Directory(node.path);
      final entities = await dir.list(followLinks: false).toList();

      entities.sort((a, b) {
        final ad = FileSystemEntity.isDirectorySync(a.path);
        final bd = FileSystemEntity.isDirectorySync(b.path);
        if (ad != bd) return ad ? -1 : 1; // dirs first
        return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
      });

      node.children = entities.map((e) {
        final isDir = FileSystemEntity.isDirectorySync(e.path);
        return isDir ? FsNode.dir(e.path) : FsNode.file(e.path);
      }).toList();
    } finally {
      if (mounted) setState(() => node.isLoading = false);
    }
  }

  List<_FlatRow> _flatten(FsNode node, int depth) {
    final rows = <_FlatRow>[];
    rows.add(_FlatRow(node: node, depth: depth));
    if (node.isDir && node.isExpanded && node.children != null) {
      for (final ch in node.children!) {
        rows.addAll(_flatten(ch, depth + 1));
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    // Scale all “spacing” based on width (so user resize affects density)
    final w = widget.sidebarWidth;
    final scale = (w / 280.0).clamp(0.85, 1.25);

    final rowH = 28.0 * scale;
    final fontSize = 12.5 * scale;
    final iconSize = 16.0 * scale;
    final indent = 14.0 * scale;
    final hPad = 8.0 * scale;
    final vPad = 6.0 * scale;

    final bg = const Color(0xFF1E1E1E);
    final fg = const Color(0xFFD4D4D4);
    final muted = const Color(0xFF9AA0A6);

    final rows = _flatten(_rootNode, 0);

    return Container(
      color: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header like VSCode "EXPLORER"
          Padding(
            padding: EdgeInsets.fromLTRB(hPad, vPad, hPad, vPad),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    p.basename(widget.root.path).isEmpty ? widget.root.path : p.basename(widget.root.path).toUpperCase(),
                    style: TextStyle(
                      color: fg,
                      fontSize: (12.0 * scale),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  iconSize: 18 * scale,
                  onPressed: () {
                    setState(() {
                      // force reload root
                      _rootNode.children = null;
                    });
                    _loadChildren(_rootNode);
                  },
                  icon: Icon(Icons.refresh, color: muted),
                )
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFF2A2A2A)),

          Expanded(
            child: ListView.builder(
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final row = rows[i];
                final node = row.node;

                final isRoot = identical(node, _rootNode);
                final name = isRoot ? p.basename(widget.root.path) : p.basename(node.path);

                return InkWell(
                  onTap: () async {
                    if (node.isDir) {
                      setState(() => node.isExpanded = !node.isExpanded);
                      if (node.isExpanded) await _loadChildren(node);
                      setState(() {}); // rebuild to show flattened children
                    } else {
                      widget.onOpenFile(File(node.path));
                    }
                  },
                  child: SizedBox(
                    height: rowH,
                    child: Padding(
                      padding: EdgeInsets.only(left: hPad + row.depth * indent, right: hPad),
                      child: Row(
                        children: [
                          // expand chevron for dirs
                          SizedBox(
                            width: iconSize + 6,
                            child: node.isDir
                                ? Icon(
                                    node.isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                                    size: iconSize,
                                    color: muted,
                                  )
                                : const SizedBox.shrink(),
                          ),

                          // icon
                          Icon(
                            node.isDir ? Icons.folder_outlined : Icons.insert_drive_file_outlined,
                            size: iconSize,
                            color: node.isDir ? const Color(0xFFC5A46D) : muted,
                          ),
                          SizedBox(width: 8 * scale),

                          // file/folder name
                          Expanded(
                            child: Text(
                              name,
                              style: TextStyle(
                                color: fg,
                                fontSize: fontSize,
                                height: (1.2 * scale),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),

                          // loading indicator when opening dir
                          if (node.isDir && node.isLoading)
                            SizedBox(
                              width: 14 * scale,
                              height: 14 * scale,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: muted,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const Divider(height: 1, thickness: 1, color: Color(0xFF2A2A2A)),
          // Bottom sections like VSCode (outline/timeline/deps) - placeholders
          _BottomSection(title: "OUTLINE", scale: scale),
          _BottomSection(title: "TIMELINE", scale: scale),
          _BottomSection(title: "DEPENDENCIES", scale: scale),
        ],
      ),
    );
  }
}

class _BottomSection extends StatelessWidget {
  final String title;
  final double scale;
  const _BottomSection({required this.title, required this.scale});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: (34 * scale),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 8.0 * scale),
        child: Row(
          children: [
            Icon(Icons.keyboard_arrow_right, size: 16 * scale, color: Colors.white54),
            SizedBox(width: 6 * scale),
            Text(
              title,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12 * scale,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlatRow {
  final FsNode node;
  final int depth;
  _FlatRow({required this.node, required this.depth});
}

class FsNode {
  final String path;
  final bool isDir;

  bool isExpanded = false;
  bool isLoading = false;
  List<FsNode>? children;

  FsNode._(this.path, this.isDir);

  factory FsNode.dir(String path) => FsNode._(path, true);
  factory FsNode.file(String path) => FsNode._(path, false);
}
