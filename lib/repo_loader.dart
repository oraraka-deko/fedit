import 'dart:io';
import 'package:archive/archive.dart';
import 'package:fedit/models/git_models.dart';
import 'package:fedit/services/git_service.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class RepoUtils {
  static const GitService _gitService = GitService();

  /// Returns the internal app-private documents storage path.
  static Future<String> getInternalStoragePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  /// Returns the external storage path (or falls back to internal if unavailable).
  static Future<String> getExternalStoragePath() async {
    if (Platform.isAndroid) {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        return ext.path;
      }
    }
    return getInternalStoragePath();
  }

  /// Transforms a GitHub URL into a ZIP download URL
  /// e.g. https://github.com/user/repo -> https://github.com/user/repo/archive/refs/heads/main.zip
  static String? getZipUrl(String originalUrl, {String branch = 'main'}) {
    if (!originalUrl.contains('github.com')) return null;

    String cleanUrl = originalUrl.endsWith('.git')
        ? originalUrl.substring(0, originalUrl.length - 4)
        : originalUrl;

    return '$cleanUrl/archive/refs/heads/$branch.zip';
  }

  /// Clones a repository using the background-isolated [GitService].
  static Future<String> cloneRepo({
    required String repoUrl,
    required String targetDirPath,
    String? branch,
    String? tag,
    AuthSpec? authSpec,
    GitAuthor? author,
    void Function(double progress, String? status)? onProgress,
  }) async {
    await _gitService.cloneRepository(
      url: repoUrl,
      localPath: targetDirPath,
      branch: branch,
      tag: tag,
      authSpec: authSpec,
      author: author,
      onProgress: onProgress,
    );
    return targetDirPath;
  }

  /// Clones or downloads a remote repository to [targetDirPath] (or default app documents).
  ///
  /// Uses the new background [GitService] as primary flow with support for
  /// branch, tag, username, token, and live progress reporting.
  /// Falls back to HTTP archive extraction only if Git clone is unavailable.
  static Future<String> downloadAndExtract(
    String repoUrl, {
    String? targetDirPath,
    String? folderName,
    String? branch,
    String? tag,
    AuthSpec? authSpec,
    GitAuthor? author,
    bool overwriteExisting = true,
    void Function(double progress, String? status)? onProgress,
  }) async {
    final baseDir = targetDirPath != null
        ? Directory(targetDirPath)
        : await getApplicationDocumentsDirectory();

    if (!baseDir.existsSync()) {
      baseDir.createSync(recursive: true);
    }

    final repoName = folderName ?? deriveRepoName(repoUrl);
    final destination = Directory(p.join(baseDir.path, repoName));

    if (destination.existsSync()) {
      if (overwriteExisting) {
        destination.deleteSync(recursive: true);
      } else {
        throw FileSystemException(
          'Destination already exists',
          destination.path,
        );
      }
    }

    onProgress?.call(0.05, 'Starting background clone...');

    try {
      await _gitService.cloneRepository(
        url: repoUrl,
        localPath: destination.path,
        branch: (branch != null && branch.trim().isNotEmpty) ? branch.trim() : null,
        tag: (tag != null && tag.trim().isNotEmpty) ? tag.trim() : null,
        authSpec: authSpec,
        author: author,
        onProgress: onProgress,
      );

      onProgress?.call(1.0, 'Repository cloned successfully');
      return destination.path;
    } catch (gitError) {
      // Clean up any failed or partial clone artifacts in destination
      if (destination.existsSync()) {
        try {
          destination.deleteSync(recursive: true);
        } catch (_) {}
      }

      // If git clone fails (e.g. invalid git protocol, corporate firewall, etc.)
      // and this is a public GitHub repository without custom auth, attempt zip archive fallback.
      if (authSpec != null && authSpec.mode != AuthMode.none) {
        rethrow;
      }

      final zipUrl = getZipUrl(repoUrl, branch: branch ?? 'main');
      if (zipUrl == null) {
        rethrow;
      }

      onProgress?.call(0.2, 'Git clone encountered an issue. Falling back to ZIP snapshot...');

      final response = await http.get(Uri.parse(zipUrl));
      if (response.statusCode != 200) {
        if (zipUrl.endsWith('main.zip')) {
          return downloadAndExtract(
            repoUrl,
            targetDirPath: targetDirPath,
            folderName: folderName,
            branch: 'master',
            overwriteExisting: overwriteExisting,
            onProgress: onProgress,
          );
        }
        throw Exception(
          'Failed to clone repository: $gitError (HTTP zip status: ${response.statusCode})',
        );
      }

      final archive = ZipDecoder().decodeBytes(response.bodyBytes);
      if (!destination.existsSync()) {
        destination.createSync(recursive: true);
      }

      // Detect if all archive entries share a top-level root folder (e.g. <repo>-<branch>/)
      String? commonPrefix;
      if (archive.isNotEmpty) {
        final firstPath = archive.first.name.replaceAll(r'\', '/');
        final slashIndex = firstPath.indexOf('/');
        if (slashIndex != -1) {
          final prefixCandidate = firstPath.substring(0, slashIndex + 1);
          final allMatch = archive.every(
            (f) => f.name.replaceAll(r'\', '/').startsWith(prefixCandidate),
          );
          if (allMatch) {
            commonPrefix = prefixCandidate;
          }
        }
      }

      for (var i = 0; i < archive.length; i++) {
        final file = archive[i];
        var filename = file.name.replaceAll(r'\', '/');

        if (commonPrefix != null) {
          if (filename == commonPrefix || filename == commonPrefix.substring(0, commonPrefix.length - 1)) {
            continue; // Skip root folder entry itself
          }
          if (filename.startsWith(commonPrefix)) {
            filename = filename.substring(commonPrefix.length);
          }
        }

        if (filename.isEmpty) continue;

        final targetPath = p.join(destination.path, filename);
        if (file.isFile) {
          final data = file.content as List<int>;
          final targetFile = File(targetPath);
          targetFile.createSync(recursive: true);
          targetFile.writeAsBytesSync(data);
        } else {
          Directory(targetPath).createSync(recursive: true);
        }

        final progress = 0.3 + ((i + 1) / archive.length) * 0.6;
        onProgress?.call(progress.clamp(0.0, 1.0), 'Extracting archive: $filename');
      }

      // Initialize local Git repository with origin pointing to remote
      try {
        await _gitService.initRepository(
          path: destination.path,
          initialHead: branch ?? 'main',
          author: author,
        );
        await _gitService.addRemote(
          destination.path,
          name: 'origin',
          url: repoUrl,
        );
      } catch (_) {
        // Non-critical; workspace remains valid with extracted files
      }

      onProgress?.call(1.0, 'Repository cloned successfully');
      return destination.path;
    }
  }

  /// Extracts repository name from a git or web URL.
  static String deriveRepoName(String url) {
    final cleaned = url.endsWith('.git') ? url.substring(0, url.length - 4) : url;
    final normalized = cleaned.replaceAll(r'\', '/');
    final parts = normalized.split('/').where((p) => p.isNotEmpty).toList();
    return parts.isNotEmpty ? parts.last : 'repository';
  }
}
