import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
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

  // Track clipboard state for Cut / Copy / Paste actions
  String? _clipboardPath;
  bool _isCut = false;

  @override
  void initState() {
    super.initState();
    _rootNode = FsNode.dir(widget.root.path)..isExpanded = true;
    _loadChildren(_rootNode);
  }

  Future<void> _loadChildren(FsNode node) async {
    if (!node.isDir || node.isLoading) return;

    setState(() => node.isLoading = true);

    try {
      final dir = Directory(node.path);
      if (!await dir.exists()) {
        node.children = [];
        return;
      }

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

  /// Reloads the entire hierarchy starting from root and triggers rebuild
  Future<void> _refreshTree() async {
    setState(() {
      _rootNode.children = null;
    });
    await _loadChildren(_rootNode);
    if (mounted) setState(() {});
  }

  // --- File System Operations ---

  Future<void> _createEntity(String parentDir, bool isDir) async {
    final controller = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF252526),
        title: Text(isDir ? 'New Folder' : 'New File', style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: isDir ? 'Folder name' : 'File name',
            hintStyle: const TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (created == true && controller.text.trim().isNotEmpty) {
      final targetPath = p.join(parentDir, controller.text.trim());
      if (isDir) {
        await Directory(targetPath).create(recursive: true);
      } else {
        await File(targetPath).create(recursive: true);
      }
      await _refreshTree();
    }
  }

  Future<void> _renameEntity(String currentPath) async {
    final oldName = p.basename(currentPath);
    final controller = TextEditingController(text: oldName);

    final renamed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF252526),
        title: const Text('Rename', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (renamed == true && controller.text.trim().isNotEmpty && controller.text.trim() != oldName) {
      final newPath = p.join(p.dirname(currentPath), controller.text.trim());
      final isDir = FileSystemEntity.isDirectorySync(currentPath);
      if (isDir) {
        await Directory(currentPath).rename(newPath);
      } else {
        await File(currentPath).rename(newPath);
      }
      await _refreshTree();
    }
  }

  Future<void> _deleteEntity(String currentPath) async {
    final isDir = FileSystemEntity.isDirectorySync(currentPath);
    if (isDir) {
      await Directory(currentPath).delete(recursive: true);
    } else {
      await File(currentPath).delete();
    }
    await _refreshTree();
  }

  Future<void> _pasteTo(String targetDir) async {
    if (_clipboardPath == null) return;

    final name = p.basename(_clipboardPath!);
    final destPath = p.join(targetDir, name);
    final isDir = FileSystemEntity.isDirectorySync(_clipboardPath!);

    if (_isCut) {
      if (isDir) {
        await Directory(_clipboardPath!).rename(destPath);
      } else {
        await File(_clipboardPath!).rename(destPath);
      }
      _clipboardPath = null;
      _isCut = false;
    } else {
      if (isDir) {
        await _copyDirectory(Directory(_clipboardPath!), Directory(destPath));
      } else {
        await File(_clipboardPath!).copy(destPath);
      }
    }
    await _refreshTree();
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(recursive: false)) {
      final newPath = p.join(destination.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(newPath));
      } else if (entity is File) {
        await entity.copy(newPath);
      }
    }
  }

  // --- Context Menu Definition ---

  ContextMenu _buildContextMenu(FsNode node, bool isRoot) {
    final parentDir = node.isDir ? node.path : p.dirname(node.path);

    final entries = <ContextMenuEntry>[
      MenuHeader(text: isRoot ? 'Root Directory' : p.basename(node.path)),
      
      // New File / Folder (available for directories)
      if (node.isDir) ...[
        MenuItem(
          label: const Text('New File'),
          icon: const Icon(Icons.note_add_outlined),
          onSelected: (_) => _createEntity(node.path, false),
        ),
        MenuItem(
          label: const Text('New Folder'),
          icon: const Icon(Icons.create_new_folder_outlined),
          onSelected: (_) => _createEntity(node.path, true),
        ),
        const MenuDivider(),
      ],

      // Copy / Cut actions (not applicable to workspace root)
      if (!isRoot) ...[
        MenuItem(
          label: const Text('Copy'),
          icon: const Icon(Icons.copy),
          onSelected: (_) {
            setState(() {
              _clipboardPath = node.path;
              _isCut = false;
            });
          },
        ),
        MenuItem(
          label: const Text('Cut'),
          icon: const Icon(Icons.cut),
          onSelected: (_) {
            setState(() {
              _clipboardPath = node.path;
              _isCut = true;
            });
          },
        ),
      ],

      // Paste action (only active when something is on the clipboard)
      MenuItem(
        enabled: _clipboardPath != null,
        label: const Text('Paste'),
        icon: const Icon(Icons.paste),
        onSelected: (_) => _pasteTo(parentDir),
      ),

      // Rename & Delete (not applicable to workspace root)
      if (!isRoot) ...[
        const MenuDivider(),
        MenuItem(
          label: const Text('Rename'),
          icon: const Icon(Icons.drive_file_rename_outline),
          onSelected: (_) => _renameEntity(node.path),
        ),
        MenuItem(
          label: const Text('Delete'),
          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
          onSelected: (_) => _deleteEntity(node.path),
        ),
      ],
    ];

    return ContextMenu(
      entries: entries,
      padding: const EdgeInsets.all(6.0),
    );
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
          // Header
          Padding(
            padding: EdgeInsets.fromLTRB(hPad, vPad, hPad, vPad),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    p.basename(widget.root.path).isEmpty
                        ? widget.root.path
                        : p.basename(widget.root.path).toUpperCase(),
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
                  onPressed: _refreshTree,
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

                return ContextMenuRegion(
                  contextMenu: _buildContextMenu(node, isRoot),
                  child: InkWell(
                    onTap: () async {
                      if (node.isDir) {
                        setState(() => node.isExpanded = !node.isExpanded);
                        if (node.isExpanded) await _loadChildren(node);
                        setState(() {});
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
                            Icon(
                              node.isDir ? Icons.folder_outlined : Icons.insert_drive_file_outlined,
                              size: iconSize,
                              color: node.isDir ? const Color(0xFFC5A46D) : muted,
                            ),
                            SizedBox(width: 8 * scale),
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
                  ),
                );
              },
            ),
          ),

          const Divider(height: 1, thickness: 1, color: Color(0xFF2A2A2A)),
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