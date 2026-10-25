import 'dart:io';
import 'package:path/path.dart' as p;

/// Model representing metadata for files, directories, or batch selections.
class ItemMetadata {
  final String path;
  final String name;
  final FileSystemEntityType type;
  final int sizeInBytes;
  final DateTime? modified;
  final DateTime? accessed;

  ItemMetadata({
    required this.path,
    required this.name,
    required this.type,
    required this.sizeInBytes,
    this.modified,
    this.accessed,
  });

  @override
  String toString() {
    return 'ItemMetadata(name: $name, type: $type, size: $sizeInBytes bytes, modified: $modified)';
  }
}

class FileManagerService {
  /// 1. Create an empty file
  Future<File> createEmptyFile({
    required String fileName,
    required String parentPath,
  }) async {
    final fullPath = p.join(parentPath, fileName);
    final file = File(fullPath);

    if (await file.exists()) {
      throw FileSystemException('File already exists', fullPath);
    }

    return await file.create(recursive: true);
  }

  /// 2. Create a folder / directory
  Future<Directory> createFolder(String folderPath) async {
    final dir = Directory(folderPath);
    if (await dir.exists()) {
      throw FileSystemException('Directory already exists', folderPath);
    }
    return await dir.create(recursive: true);
  }

  /// 3. Delete single file
  Future<void> deleteFile(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    } else {
      throw FileSystemException('File not found', filePath);
    }
  }

  /// 4. Delete multiple files or directories
  Future<void> deleteItems(List<String> paths) async {
    for (final path in paths) {
      final type = await FileSystemEntity.type(path);
      if (type == FileSystemEntityType.file) {
        await File(path).delete();
      } else if (type == FileSystemEntityType.directory) {
        await Directory(path).delete(recursive: true);
      } else if (type == FileSystemEntityType.link) {
        await Link(path).delete();
      }
    }
  }

  /// 5. Rename a file or directory
  Future<FileSystemEntity> renameItem({
    required String currentPath,
    required String newName,
  }) async {
    final parentDir = p.dirname(currentPath);
    final newPath = p.join(parentDir, newName);

    final type = await FileSystemEntity.type(currentPath);
    if (type == FileSystemEntityType.notFound) {
      throw FileSystemException('Entity not found', currentPath);
    }

    if (await FileSystemEntity.type(newPath) != FileSystemEntityType.notFound) {
      throw FileSystemException('An item with the new name already exists', newPath);
    }

    if (type == FileSystemEntityType.file) {
      return await File(currentPath).rename(newPath);
    } else if (type == FileSystemEntityType.directory) {
      return await Directory(currentPath).rename(newPath);
    } else {
      return await Link(currentPath).rename(newPath);
    }
  }

  /// 6. Duplicate a single file (e.g., "file.txt" -> "file_copy.txt")
  Future<File> duplicateFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('Source file not found', filePath);
    }

    final parent = p.dirname(filePath);
    final base = p.basenameWithoutExtension(filePath);
    final ext = p.extension(filePath);

    var copyName = '${base}_copy$ext';
    var destination = p.join(parent, copyName);

    var counter = 1;
    while (await File(destination).exists()) {
      copyName = '${base}_copy_$counter$ext';
      destination = p.join(parent, copyName);
      counter++;
    }

    return await file.copy(destination);
  }

  /// 7. Copy or Cut multiple files / directories / mixed to target directory
  Future<void> transferItems({
    required List<String> sourcePaths,
    required String targetDirectoryPath,
    required bool isCut,
  }) async {
    final targetDir = Directory(targetDirectoryPath);
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    for (final sourcePath in sourcePaths) {
      final name = p.basename(sourcePath);
      final destPath = p.join(targetDirectoryPath, name);
      final type = await FileSystemEntity.type(sourcePath);

      if (type == FileSystemEntityType.file) {
        final srcFile = File(sourcePath);
        if (isCut) {
          // Attempt atomic rename; fallback to copy + delete across mount boundaries
          try {
            await srcFile.rename(destPath);
          } catch (_) {
            await srcFile.copy(destPath);
            await srcFile.delete();
          }
        } else {
          await srcFile.copy(destPath);
        }
      } else if (type == FileSystemEntityType.directory) {
        if (isCut) {
          try {
            await Directory(sourcePath).rename(destPath);
          } catch (_) {
            await _copyDirectory(Directory(sourcePath), Directory(destPath));
            await Directory(sourcePath).delete(recursive: true);
          }
        } else {
          await _copyDirectory(Directory(sourcePath), Directory(destPath));
        }
      }
    }
  }

  /// 8. Get info for a file, folder, or a batch of files/folders
  Future<ItemMetadata> getItemInfo(dynamic target) async {
    // Case A: List of paths (batch selection info)
    if (target is List<String>) {
      int totalSize = 0;
      for (final path in target) {
        totalSize += await _calculateEntitySize(path);
      }
      return ItemMetadata(
        path: target.join(', '),
        name: '${target.length} selected items',
        type: FileSystemEntityType.notFound, // Representing a mixed batch
        sizeInBytes: totalSize,
        modified: null,
        accessed: null,
      );
    }

    // Case B: Single path (String, File, or Directory)
    final String path = target is FileSystemEntity ? target.path : target.toString();
    final type = await FileSystemEntity.type(path);

    if (type == FileSystemEntityType.notFound) {
      throw FileSystemException('Path does not exist', path);
    }

    final stat = await FileStat.stat(path);
    final size = await _calculateEntitySize(path);

    return ItemMetadata(
      path: path,
      name: p.basename(path),
      type: type,
      sizeInBytes: size,
      modified: stat.modified,
      accessed: stat.accessed,
    );
  }

  // --- Internal Helpers ---

  /// Recursively copies directory tree
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

  /// Calculates total size for either a file or recursively for a directory
  Future<int> _calculateEntitySize(String path) async {
    final type = await FileSystemEntity.type(path);

    if (type == FileSystemEntityType.file) {
      return (await File(path).stat()).size;
    } else if (type == FileSystemEntityType.directory) {
      int totalSize = 0;
      try {
        await for (final entity in Directory(path).list(recursive: true, followLinks: false)) {
          if (entity is File) {
            totalSize += await entity.length();
          }
        }
      } catch (_) {
        // Silently skip inaccessible or permission-restricted child files
      }
      return totalSize;
    }
    return 0;
  }
}