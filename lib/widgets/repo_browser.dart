import 'dart:io';
import 'drawershell.dart';
import 'package:flutter/material.dart';
import '../main.dart';
import 'package:path/path.dart' as p;

import 'code_forge.dart';
import '../utils/colors.dart';
import '../tglogs.dart';
import 'repo_browser_scaffold.dart';

class RepoBrowser extends StatefulWidget {
  final String path;
  final Widget Function() aiSidebarBuilder;
  const RepoBrowser({
    super.key,
    required this.aiSidebarBuilder,
    required this.path,
  });

  @override
  State<RepoBrowser> createState() => _RepoBrowserState();
}

class _RepoBrowserState extends State<RepoBrowser> {
  List<FileSystemEntity> _files = [];

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  void _loadFiles() {
    final dir = Directory(widget.path);
    try {
      final List<FileSystemEntity> entities = dir.listSync();
      entities.sort((a, b) {
        if (a is Directory && b is! Directory) return -1;
        if (a is! Directory && b is Directory) return 1;
        return a.path.toLowerCase().compareTo(b.path.toLowerCase());
      });

      setState(() {
        _files = entities
            .where((e) => !p.basename(e.path).startsWith('.'))
            .toList();
      });
    } catch (e) {
      sendTelegramLog("Error loading files: $e");
    }
  }

  void _navigateTo(FileSystemEntity entity) {
    if (entity is Directory) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RepoBrowserScaffold(
            path: entity.path,
            title: p.basename(entity.path),
          ),
        ),
      ).then(
        (_) => setState(() {}),
      ); // Re-build on return to refresh checkboxes
    } else if (entity is File) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EditorWithExplorerShell(
            projectRoot: Directory(widget.path),
            initialFile: entity,
            editorBuilder: (file, {tabId, isActive}) => AdvancedCodeEditor(
              file: file,
              tabId: tabId,
              isActive: isActive,
            ),
            aisidebar: widget.aiSidebarBuilder(),
          ),
        ),
      );
    }}

  void _toggleSelection(String path) {
    setState(() {
      if (selectedPaths.contains(path)) {
        selectedPaths.remove(path);
      } else {
        selectedPaths.add(path);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_files.isEmpty) {
      return const Center(
        child: Text(
          "Empty directory",
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _files.length,
      itemBuilder: (context, index) {
        final entity = _files[index];
        final isDir = entity is Directory;
        final name = p.basename(entity.path);
        final isSelected = selectedPaths.contains(entity.path);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: InkWell(
            onTap: () => _navigateTo(entity),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected
                      ? AppColors.accent.withValues(alpha: 0.5)
                      : AppColors.border,
                ),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.only(left: 8, right: 16),
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: isSelected,
                      activeColor: AppColors.accent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      onChanged: (_) => _toggleSelection(entity.path),
                    ),
                    Icon(
                      isDir ? Icons.folder_rounded : Icons.description_outlined,
                      color: isDir ? AppColors.folder : AppColors.file,
                      size: 28,
                    ),
                  ],
                ),
                title: Text(
                  name,
                  style: TextStyle(
                    color: isSelected
                        ? AppColors.accent
                        : AppColors.textPrimary,
                    fontWeight: isDir ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 15,
                  ),
                ),
                trailing: isDir
                    ? const Icon(
                        Icons.chevron_right,
                        color: AppColors.textSecondary,
                        size: 20,
                      )
                    : Text(
                        "${(File(entity.path).lengthSync() / 1024).toStringAsFixed(1)} KB",
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}
