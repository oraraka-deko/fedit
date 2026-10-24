import 'dart:io';
import 'package:archive/archive.dart';
import 'package:git2dart/git2dart.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class RepoUtils {
  /// Transforms a GitHub URL into a ZIP download URL
  /// e.g. https://github.com/user/repo -> https://github.com/user/repo/archive/refs/heads/main.zip
  static String? getZipUrl(String originalUrl, {String branch = "main"}) {
    if (!originalUrl.contains("github.com")) return null; // Basic validation

    // Clean the URL (remove .git if present)
    String cleanUrl = originalUrl.endsWith(".git")
        ? originalUrl.substring(0, originalUrl.length - 4)
        : originalUrl;

    // GitHub standard archive format
    return "$cleanUrl/archive/refs/heads/$branch.zip";
  }

  static Future<Repository> cloneRepo(String repoUrl, String targetDirPath) async {
    return Repository.clone(
      url: repoUrl,
      localPath: targetDirPath,
    );
  }

  static Future<String> downloadAndExtract(
    String repoUrl, {
    String? targetDirPath,
    String? folderName,
    bool overwriteExisting = true,
    void Function(double progress)? onProgress,
  }) async {
    try {
      final dir = targetDirPath != null
          ? Directory(targetDirPath)
          : await getApplicationDocumentsDirectory();
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      final repoName =
          folderName ?? repoUrl.split("/").last.replaceAll(".git", "");
      final destination = Directory(p.join(dir.path, repoName));

      if (await destination.exists()) {
        if (overwriteExisting) {
          await destination.delete(recursive: true);
        } else {
          throw FileSystemException(
            "Destination already exists",
            destination.path,
          );
        }
      }

      await destination.create(recursive: true);
      onProgress?.call(0.1);

      final repo = await cloneRepo(repoUrl, destination.path);
      onProgress?.call(1.0);
      return repo.workdir;
    } catch (_) {
      final zipUrl = getZipUrl(repoUrl);
      if (zipUrl == null) throw Exception("Invalid GitHub URL");

      final response = await http.get(Uri.parse(zipUrl));
      if (response.statusCode != 200) {
        if (zipUrl.endsWith("main.zip")) {
          return downloadAndExtract(
            repoUrl.replaceAll("main", "master"),
            targetDirPath: targetDirPath,
            folderName: folderName,
            overwriteExisting: overwriteExisting,
            onProgress: onProgress,
          );
        }
        throw Exception(
          "Failed to download repo. Status: ${response.statusCode}",
        );
      }

      final archive = ZipDecoder().decodeBytes(response.bodyBytes);
      final dir = targetDirPath != null
          ? Directory(targetDirPath)
          : await getApplicationDocumentsDirectory();
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      final repoName =
          folderName ?? repoUrl.split("/").last.replaceAll(".git", "");
      final destination = Directory(p.join(dir.path, repoName));

      if (await destination.exists()) {
        if (overwriteExisting) {
          await destination.delete(recursive: true);
        } else {
          throw FileSystemException(
            "Destination already exists",
            destination.path,
          );
        }
      }
      await destination.create(recursive: true);
      onProgress?.call(0.25);

      for (var i = 0; i < archive.length; i++) {
        final file = archive[i];
        final filename = file.name;
        if (file.isFile) {
          final data = file.content as List<int>;
          final targetFile = File(p.join(destination.path, filename));
          targetFile.createSync(recursive: true);
          targetFile.writeAsBytesSync(data);
        } else {
          Directory(p.join(destination.path, filename)).createSync(recursive: true);
        }

        final progress = 0.25 + ((i + 1) / archive.length) * 0.7;
        onProgress?.call(progress.clamp(0.0, 1.0));
      }

      final entities = destination.listSync();
      if (entities.length == 1 && entities.first is Directory) {
        onProgress?.call(1.0);
        return (entities.first as Directory).path;
      }

      onProgress?.call(1.0);
      return destination.path;
    }
  }
}
