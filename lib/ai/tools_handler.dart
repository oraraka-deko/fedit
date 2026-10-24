import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'models.dart';
import 'file_filters.dart';

class ToolsHandler {
  final String rootPath;

  ToolsHandler(this.rootPath);


  // Define the JSON Schema for the AI
  List<Tool> getToolDefinitions() {
    return [
      Tool(
        function: {
          "name": "list_files",
          "description":
              "Returns a recursive list of all file paths in the workspace. Use this first to find where files are.",
          "parameters": {
            "type": "object",
            "properties": {}, // No params needed, scans root
          },
        },
      ),
      Tool(
        function: {
          "name": "read_file",
          "description":
              "Reads a file and returns content with line numbers (e.g. '1 | code').",
          "parameters": {
            "type": "object",
            "properties": {
              "path": {"type": "string"},
            },
            "required": ["path"],
          },
        },
      ),
      Tool(
        function: {
          "name": "patch_file",
          "description":
              "Edits a file using line-based patches. Syntax: 'N--' (delete), 'N++ content' (replace), '0++' (prepend), '00++' (append).",
          "parameters": {
            "type": "object",
            "properties": {
              "path": {"type": "string"},
              "patch": {
                "type": "string",
                "description": "The patch string e.g. '26++ new code'",
              },
            },
            "required": ["path", "patch"],
          },
        },
      ),
      Tool(
        function: {
          "name": "find_and_replace",
          "description":
              "Find and replace text in one file or across a directory. Supports regex, suffix-only matches, case sensitivity, include/exclude globs, and dry runs.",
          "parameters": {
            "type": "object",
            "properties": {
              "target": {
                "type": "string",
                "description": "Relative file or directory to search.",
              },
              "find": {
                "type": "string",
                "description": "The text or pattern to match.",
              },
              "replace": {
                "type": "string",
                "description":
                    "Replacement text; use empty string to delete matches.",
              },
              "match_type": {
                "type": "string",
                "enum": ["plain", "regex", "suffix"],
                "description":
                    "plain for literal match (default), regex for patterns, suffix to match text at line ends.",
              },
              "case_sensitive": {
                "type": "boolean",
                "description": "Set true to respect case. Default false.",
              },
              "include": {
                "type": "array",
                "items": {"type": "string"},
                "description":
                    "Optional glob patterns to include (relative paths).",
              },
              "exclude": {
                "type": "array",
                "items": {"type": "string"},
                "description":
                    "Optional glob patterns to skip (relative paths).",
              },
              "dry_run": {
                "type": "boolean",
                "description":
                    "If true, report matches without writing changes.",
              },
            },
            "required": ["target", "find", "replace"],
          },
        },
      ),
      Tool(
        function: {
          "name": "file_action",
          "description":
              "Create, delete, copy, move, or duplicate a file/directory inside the workspace. Provide action, path, and target for move/copy when needed (use trailing slash in path to create a directory).",
          "parameters": {
            "type": "object",
            "properties": {
              "action": {
                "type": "string",
                "enum": ["create", "delete", "copy", "move", "duplicate"],
                "description": "The operation to perform.",
              },
              "path": {
                "type": "string",
                "description": "Relative source path inside the workspace.",
              },
              "target": {
                "type": "string",
                "description":
                    "Relative destination path for copy/move/duplicate. Optional for duplicate (auto suffix).",
              },
            },
            "required": ["action", "path"],
          },
        },
      ),
    ];
  }

  Future<String> execute(String name, Map<String, dynamic> args) async {
    try {
      switch (name) {
        case "list_files":
          return await _listFiles();
        case "read_file":
          return await _readFileWithLines(args['path']);
        case "patch_file":
          return await _applyFilePatch(args['path'], args['patch']);
        case "find_and_replace":
          return await _findAndReplace(args);
        case "file_action":
          return await _fileAction(args);
        default:
          return "Error: Unknown tool $name";
      }
    } catch (e) {
      return "Error executing $name: $e";
    }
  }

  // --- Implementations ---

  Future<String> _listFiles() async {
    final dir = Directory(rootPath);
    if (!await dir.exists()) return "Error: Workspace not found.";

    final filter = await AiFileFilter.load();
    List<String> paths = [];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        // Return relative path for AI clarity
        String relative = p.relative(entity.path, from: rootPath);
        if (filter.isHidden(relative)) continue;
        paths.add(relative);
      }
    }
    return paths.join("\n");
  }

  Future<String> _readFileWithLines(String relPath) async {
    final file = File(p.join(rootPath, relPath));
    if (!await file.exists()) return "Error: File $relPath does not exist.";
    final filter = await AiFileFilter.load();
    if (filter.isHidden(relPath)) {
      return "Error: File $relPath is hidden by default filters.";
    }

    final lines = await file.readAsLines();
    final buffer = StringBuffer();
    for (var i = 0; i < lines.length; i++) {
      buffer.writeln("${i + 1} | ${lines[i]}");
    }
    return buffer.toString();
  }

  // Exact port of your Go ApplyFilePatch logic
  Future<String> _applyFilePatch(String relPath, String patchContent) async {
    final file = File(p.join(rootPath, relPath));
    if (!await file.exists()) return "Error: File not found.";

    List<String> originalLines = await file.readAsLines();

    // Regex: (\d+|00) followed by (++|--) then optional content
    final re = RegExp(r'^(\d+|00)(\+\+|--)\s?(.*)$');

    // Map of Target -> Operation
    final Map<String, _Op> ops = {};

    final patchLines = const LineSplitter().convert(patchContent);
    for (var line in patchLines) {
      if (line.trim().isEmpty) continue;
      final match = re.firstMatch(line);
      if (match == null) continue;

      String target = match.group(1)!;
      String operator = match.group(2)!;
      String text = match.group(3) ?? "";

      ops[target] = _Op(operator == "--" ? "delete" : "replace", text);
    }

    List<String> newLines = [];

    // 0++ (Prepend)
    if (ops.containsKey("0") && ops["0"]!.type != "delete") {
      newLines.add(ops["0"]!.content);
    }

    // Process Original
    for (var i = 0; i < originalLines.length; i++) {
      String lineNum = (i + 1).toString();
      if (ops.containsKey(lineNum)) {
        if (ops[lineNum]!.type == "replace") {
          newLines.add(ops[lineNum]!.content);
        }
        // if delete, do nothing (skip)
      } else {
        newLines.add(originalLines[i]);
      }
    }

    // 00++ (Append)
    if (ops.containsKey("00") && ops["00"]!.type != "delete") {
      newLines.add(ops["00"]!.content);
    }

    // Write back
    String finalContent = newLines.join("\n");
    if (finalContent.isNotEmpty && !finalContent.endsWith("\n")) {
      finalContent += "\n";
    }
    await file.writeAsString(finalContent);

    return "Successfully patched $relPath.";
  }

  Future<String> _findAndReplace(Map<String, dynamic> args) async {
    final String? target = args['target']?.toString();
    final String? find = args['find']?.toString();
    final String? replace = args['replace']?.toString();
    if (target == null || find == null || replace == null) {
      return "Error: target, find, and replace are required.";
    }

    if (find.isEmpty) {
      return "Error: find pattern cannot be empty.";
    }

    final String matchType = (args['match_type'] ?? "plain").toString();
    final bool caseSensitive = args['case_sensitive'] == true;
    final bool dryRun = args['dry_run'] == true;
    final List<String> include = _stringList(args['include']);
    final List<String> exclude = _stringList(args['exclude']);

    final String resolvedTarget = p.normalize(p.join(rootPath, target));
    if (!p.isWithin(rootPath, resolvedTarget) &&
        !p.equals(p.normalize(rootPath), resolvedTarget)) {
      return "Error: target must be within the workspace.";
    }

    final fileTarget = File(resolvedTarget);
    final dirTarget = Directory(resolvedTarget);
    List<File> files = [];

    if (await fileTarget.exists()) {
      final relativeFile = p.relative(fileTarget.path, from: rootPath);
      final normalizedFile = _normalizePath(relativeFile);
      final filter = await AiFileFilter.load();
      if (filter.isHidden(normalizedFile)) {
        return "Error: target file is excluded by default filters.";
      }
      if (exclude.isNotEmpty && _matchesAnyPattern(normalizedFile, exclude)) {
        return "Error: target file is excluded by filters.";
      }
      if (include.isNotEmpty && !_matchesAnyPattern(normalizedFile, include)) {
        return "Error: target file does not match include filters.";
      }
      files = [fileTarget];
    } else if (await dirTarget.exists()) {
      files = await _collectFiles(dirTarget, include, exclude);
    } else {
      return "Error: target not found.";
    }

    if (files.isEmpty) {
      return "Error: No files matched include/exclude filters.";
    }

    final RegExp? pattern = _buildPattern(find, matchType, caseSensitive);
    if (pattern == null) {
      return "Error: match_type must be plain, regex, or suffix.";
    }

    final summary = StringBuffer();
    int totalReplacements = 0;

    for (final file in files) {
      final original = await file.readAsString();
      int fileCount = 0;

      final updated = original.replaceAllMapped(pattern, (match) {
        fileCount++;
        if (matchType == "regex") {
          return _applyRegexReplacement(match, replace);
        }
        return replace;
      });

      if (fileCount > 0) {
        final relative = p.relative(file.path, from: rootPath);
        summary.writeln("$relative: $fileCount replacements");
        totalReplacements += fileCount;
        if (!dryRun && original != updated) {
          await file.writeAsString(updated);
        }
      }
    }

    if (totalReplacements == 0) return "No matches found.";
    final prefix = dryRun ? "Dry run:" : "Completed:";
    return "$prefix $totalReplacements replacements\n${summary.toString().trim()}";
  }

  Future<List<File>> _collectFiles(
    Directory base,
    List<String> include,
    List<String> exclude,
  ) async {
    final filter = await AiFileFilter.load();
    final List<File> files = [];
    await for (final entity in base.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: rootPath);
      if (filter.isHidden(relative)) continue;
      final normalized = _normalizePath(relative);
      if (exclude.isNotEmpty && _matchesAnyPattern(normalized, exclude)) {
        continue;
      }
      if (include.isNotEmpty && !_matchesAnyPattern(normalized, include)) {
        continue;
      }
      files.add(entity);
    }
    return files;
  }

  List<String> _stringList(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return [];
  }

  RegExp? _buildPattern(String find, String matchType, bool caseSensitive) {
    switch (matchType) {
      case "regex":
        try {
          return RegExp(find, caseSensitive: caseSensitive, multiLine: true);
        } catch (_) {
          return null;
        }
      case "suffix":
        return RegExp(
          "${RegExp.escape(find)}\$",
          caseSensitive: caseSensitive,
          multiLine: true,
        );
      case "plain":
      default:
        return RegExp(
          RegExp.escape(find),
          caseSensitive: caseSensitive,
          multiLine: true,
        );
    }
  }

  String _applyRegexReplacement(Match match, String replacement) {
    return replacement.replaceAllMapped(RegExp(r'\$(\d+)'), (m) {
      final idx = int.tryParse(m.group(1) ?? '');
      if (idx == null || idx > match.groupCount) return m.group(0) ?? '';
      if (idx == 0) return match.group(0) ?? '';
      return match.group(idx) ?? '';
    });
  }

  bool _matchesAnyPattern(String path, List<String> patterns) {
    final normalizedPath = _normalizePath(path);
    for (final pattern in patterns) {
      final regex = _globToRegExp(_normalizePath(pattern));
      if (regex.hasMatch(normalizedPath)) return true;
    }
    return false;
  }

  String _normalizePath(String input) => input.replaceAll('\\', '/');

  RegExp _globToRegExp(String pattern) {
    final buffer = StringBuffer('^');
    for (int i = 0; i < pattern.length; i++) {
      final char = pattern[i];
      if (char == '*') {
        final bool isDouble = (i + 1 < pattern.length) && pattern[i + 1] == '*';
        if (isDouble) {
          buffer.write('.*');
          i++;
        } else {
          buffer.write('[^/]*');
        }
      } else if (char == '?') {
        buffer.write('.');
      } else {
        buffer.write(RegExp.escape(char));
      }
    }
    buffer.write(r'$');
    return RegExp(buffer.toString());
  }

  Future<String> _fileAction(Map<String, dynamic> args) async {
    final String? actionRaw = args['action']?.toString();
    final String? pathRaw = args['path']?.toString();
    if (actionRaw == null || pathRaw == null) {
      return "Error: action and path are required.";
    }
    final String action = actionRaw.toLowerCase();
    final String resolvedSource = p.normalize(p.join(rootPath, pathRaw));
    if (!_isWithinWorkspace(resolvedSource)) {
      return "Error: path must be inside the workspace.";
    }

    switch (action) {
      case "create":
        final bool dirHint = pathRaw.endsWith('/') || pathRaw.endsWith('\\');
        return _createFileOrDir(resolvedSource, dirHint);
      case "delete":
        return _deleteFileOrDir(resolvedSource);
      case "copy":
      case "move":
      case "duplicate":
        final String? targetRaw = args['target']?.toString();
        final String resolvedTarget = _resolveTarget(
          action,
          resolvedSource,
          targetRaw,
        );
        if (resolvedTarget.isEmpty) {
          return "Error: target is required for copy/move, or failed to determine duplicate name.";
        }
        if (!_isWithinWorkspace(resolvedTarget)) {
          return "Error: target must be inside the workspace.";
        }
        if (p.equals(resolvedSource, resolvedTarget)) {
          return "Error: source and target paths are the same.";
        }
        return await _copyOrMove(action, resolvedSource, resolvedTarget);
      default:
        return "Error: unsupported action $action";
    }
  }

  bool _isWithinWorkspace(String path) {
    final normalizedRoot = p.normalize(rootPath);
    return p.equals(path, normalizedRoot) || p.isWithin(normalizedRoot, path);
  }

  String _resolveTarget(String action, String source, String? targetRaw) {
    if (action == "duplicate" && (targetRaw == null || targetRaw.isEmpty)) {
      final dir = p.dirname(source);
      final base = p.basename(source);
      final ext = p.extension(base);
      final nameOnly = ext.isEmpty
          ? base
          : base.substring(0, base.length - ext.length);
      String candidate(int i) =>
          p.join(dir, "${nameOnly}_copy${i == 1 ? "" : "_$i"}$ext");
      for (int i = 1; i < 1000; i++) {
        final path = p.normalize(candidate(i));
        if (!File(path).existsSync() && !Directory(path).existsSync()) {
          return path;
        }
      }
      return "";
    }
    if (targetRaw == null || targetRaw.isEmpty) return "";
    return p.normalize(p.join(rootPath, targetRaw));
  }

  Future<String> _createFileOrDir(String path, bool dirHint) async {
    final bool isDir = dirHint;
    final file = File(path);
    final dir = Directory(path);
    if (await file.exists() || await dir.exists()) {
      return "Error: path already exists.";
    }
    final parent = Directory(p.dirname(path));
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    if (isDir) {
      await dir.create(recursive: true);
      return "Created directory: ${p.relative(path, from: rootPath)}";
    } else {
      await file.create(recursive: true);
      return "Created file: ${p.relative(path, from: rootPath)}";
    }
  }

  Future<String> _deleteFileOrDir(String path) async {
    final entity = File(path);
    final dir = Directory(path);
    if (await entity.exists()) {
      await entity.delete();
      return "Deleted file: ${p.relative(path, from: rootPath)}";
    } else if (await dir.exists()) {
      await dir.delete(recursive: true);
      return "Deleted directory: ${p.relative(path, from: rootPath)}";
    }
    return "Error: path does not exist.";
  }

  Future<String> _copyOrMove(
    String action,
    String source,
    String target,
  ) async {
    final sourceFile = File(source);
    final sourceDir = Directory(source);
    if (!await sourceFile.exists() && !await sourceDir.exists()) {
      return "Error: source does not exist.";
    }
    if (await File(target).exists() || await Directory(target).exists()) {
      return "Error: target already exists.";
    }

    final targetParent = Directory(p.dirname(target));
    if (!await targetParent.exists()) {
      await targetParent.create(recursive: true);
    }

    if (action == "move") {
      try {
        await _renameEntity(sourceFile, sourceDir, target);
        return "Moved to ${p.relative(target, from: rootPath)}";
      } catch (_) {
        // Fallback to copy + delete if rename fails (e.g., cross-device)
        final copyResult = await _copyEntity(sourceFile, sourceDir, target);
        if (copyResult.startsWith("Error")) return copyResult;
        await _deleteFileOrDir(source);
        return "Moved to ${p.relative(target, from: rootPath)}";
      }
    }

    // copy or duplicate
    return await _copyEntity(sourceFile, sourceDir, target);
  }

  Future<String> _copyEntity(
    File sourceFile,
    Directory sourceDir,
    String target,
  ) async {
    if (await File(target).exists() || await Directory(target).exists()) {
      return "Error: target already exists.";
    }
    if (await sourceFile.exists()) {
      await File(target).writeAsBytes(await sourceFile.readAsBytes());
      return "Copied file to ${p.relative(target, from: rootPath)}";
    }
    if (await sourceDir.exists()) {
      await _copyDirectory(sourceDir, Directory(target));
      return "Copied directory to ${p.relative(target, from: rootPath)}";
    }
    return "Error: source missing.";
  }

  Future<void> _copyDirectory(Directory source, Directory dest) async {
    if (!await dest.exists()) {
      await dest.create(recursive: true);
    }
    await for (final entity in source.list(
      recursive: false,
      followLinks: false,
    )) {
      final newPath = p.join(dest.path, p.basename(entity.path));
      if (entity is File) {
        await File(newPath).writeAsBytes(await entity.readAsBytes());
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory(newPath));
      }
    }
  }

  Future<FileSystemEntity?> _renameEntity(
    File? sourceFile,
    Directory? sourceDir,
    String target,
  ) async {
    if (sourceFile == null && sourceDir == null) return null;
    if (sourceFile != null) {
      return sourceFile.rename(target);
    }
    if (sourceDir != null) {
      return sourceDir.rename(target);
    }
    if (sourceFile != null && sourceDir != null) {
      sourceDir.rename(target);
      return sourceFile.rename(target);
    }
    return null;
  }
}

class _Op {
  final String type;
  final String content;
  _Op(this.type, this.content);
}
