// lib/services/search_service.dart

import 'dart:io';
import 'package:path/path.dart' as path_pkg;
// For @required
import '../models/file_content.dart';
import '../utils/regex_utils.dart'; // Use the helper
import '../ai/file_filters.dart';

class SearchService {
  final Function(String message) logError;
  final Function(FileContent file) onFileFound;
  final Function() isSearchActive;

  SearchService({
    required this.logError,
    required this.onFileFound,
    required this.isSearchActive,
  });

  /// Recursive function to search for files matching criteria.
  Future<void> searchFiles({
    required String directoryPath,
    required List<String> allowedExtensions,
    required String includePathPatterns,
    required String excludePathPatterns,
    required String includeFileNamePatterns,
    required String excludeFileNamePatterns,
    required bool isPathFilteringEnabled,
    required bool isFileNameFilteringEnabled,
    AiFileFilter? filter,
    String? rootPath,
  }) async {
    final directory = Directory(directoryPath);

    if (!await directory.exists()) {
      return;
    }

    final List<RegExp> includePathRegexes = parsePatternsToRegex(
      includePathPatterns,
    );
    final List<RegExp> excludePathRegexes = parsePatternsToRegex(
      excludePathPatterns,
    );
    final List<RegExp> includeFileNameRegexes = parsePatternsToRegex(
      includeFileNamePatterns,
    );
    final List<RegExp> excludeFileNameRegexes = parsePatternsToRegex(
      excludeFileNamePatterns,
    );

    final AiFileFilter activeFilter = filter ?? await AiFileFilter.load();
    final String basePath = rootPath ?? directoryPath;

    try {
      await for (final entity in directory.list(recursive: false)) {
        if (!isSearchActive()) break; // Check for cancellation

        final String entityPath = entity.path;
        final String entityPathNormalized = path_pkg
            .normalize(entityPath)
            .replaceAll(r'\', '/');
        final String relativePath = path_pkg
            .relative(entityPath, from: basePath)
            .replaceAll(r'\', '/');

        if (activeFilter.isHidden(relativePath)) {
          continue;
        }

        // 1. Path Filtering
        if (isPathFilteringEnabled &&
            !_matchesPatternCriteria(
              entityPathNormalized,
              includePathRegexes,
              excludePathRegexes,
            )) {
          if (entity is Directory) continue;
          if (entity is File) continue;
        }

        if (entity is File) {
          final String fileName = path_pkg.basename(entity.path);
          final String fileExtension = path_pkg
              .extension(entity.path)
              .toLowerCase();

          // Check basic extension
          if (!allowedExtensions.contains(fileExtension)) {
            continue;
          }

          // 2. Filename Filtering
          if (isFileNameFilteringEnabled &&
              !_matchesPatternCriteria(
                fileName,
                includeFileNameRegexes,
                excludeFileNameRegexes,
              )) {
            continue;
          }

          try {
            final content = await entity.readAsString();
            final fileContent = FileContent(
              fileName: fileName,
              filePath: entity.path,
              content: content,
              fileExtension: fileExtension,
            );
            onFileFound(fileContent); // Callback to the stateful widget
          } catch (e) {
            logError('Error reading file ${entity.path}: $e');
          }
        } else if (entity is Directory) {
          await searchFiles(
            directoryPath: entity.path,
            allowedExtensions: allowedExtensions,
            includePathPatterns: includePathPatterns,
            excludePathPatterns: excludePathPatterns,
            includeFileNamePatterns: includeFileNamePatterns,
            excludeFileNamePatterns: excludeFileNamePatterns,
            isPathFilteringEnabled: isPathFilteringEnabled,
            isFileNameFilteringEnabled: isFileNameFilteringEnabled,
            filter: activeFilter,
            rootPath: basePath,
          );
        }
      }
    } catch (e) {
      logError('Error accessing directory $directoryPath: $e');
    }
  }

  /// Helper to check if a string matches the include/exclude regex criteria.
  bool _matchesPatternCriteria(
    String text,
    List<RegExp> includeRegexes,
    List<RegExp> excludeRegexes,
  ) {
    bool included = true;

    // If include patterns exist, at least one must match
    if (includeRegexes.isNotEmpty) {
      included = includeRegexes.any((regex) => regex.hasMatch(text));
    }

    // If exclude patterns exist, none must match if already included
    if (included && excludeRegexes.isNotEmpty) {
      included = !excludeRegexes.any((regex) => regex.hasMatch(text));
    }

    return included;
  }
}
