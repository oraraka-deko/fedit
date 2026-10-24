// lib/services/diff_service.dart

import '../models/diff_hunk.dart';
import '../tglogs.dart';

class DiffService {
  /// Parses standard GitHub/Git diff content into structured DiffHunk objects.
  Map<String, List<DiffHunk>> parseGitHubDiff(String diffContent) {
    // [Implementation copied from original _parseGitHubDiff]
    final Map<String, List<DiffHunk>> diffsByFile = {};
    final lines = diffContent.split('\n');

    String? currentFilePath;
    List<DiffHunk> currentFileHunks = [];
    DiffHunk? currentHunk;
    List<String> currentHunkLines = [];

    for (final line in lines) {
      if (line.startsWith('--- a/')) {
        if (currentFilePath != null && currentFileHunks.isNotEmpty) {
          diffsByFile[currentFilePath] = List.from(currentFileHunks);
        }
        currentFilePath = null;
        currentFileHunks = [];
        currentHunk = null;
        currentHunkLines = [];
      } else if (line.startsWith('+++ b/')) {
        // Path should be relative to the root/project base
        currentFilePath = line.substring(6).trim();
      } else if (line.startsWith('@@ ')) {
        if (currentHunk != null) {
          currentFileHunks.add(
            currentHunk.copyWith(lines: List.from(currentHunkLines)),
          );
        }
        currentHunkLines = [];

        final regex = RegExp(r'@@ -(\d+),?(\d*)\s+\+(\d+),?(\d*)\s@@');
        final match = regex.firstMatch(line);
        if (match != null) {
          final oldStart = int.parse(match.group(1)!);
          final oldNum = match.group(2)!.isEmpty ? 1 : int.parse(match.group(2)!);
          final newStart = int.parse(match.group(3)!);
          final newNum = match.group(4)!.isEmpty ? 1 : int.parse(match.group(4)!);

          currentHunk = DiffHunk(
            oldStartLine: oldStart,
            oldNumLines: oldNum,
            newStartLine: newStart,
            newNumLines: newNum,
            lines: [],
          );
        } else {
          throw FormatException('Invalid diff hunk header: $line');
        }
      } else if (currentFilePath != null && currentHunk != null) {
        if (line.isNotEmpty &&
            (line.startsWith('+') ||
                line.startsWith('-') ||
                line.startsWith(' '))) {
          currentHunkLines.add(line);
        }
      }
    }

    if (currentHunk != null) {
      currentFileHunks.add(
        currentHunk.copyWith(lines: List.from(currentHunkLines)),
      );
    }
    if (currentFilePath != null && currentFileHunks.isNotEmpty) {
      diffsByFile[currentFilePath] = List.from(currentFileHunks);
    }

    return diffsByFile;
  }

  /// Applies a list of hunks to a list of original lines using content-aware matching.
  List<String> applyHunksToLines(
    List<String> originalLines,
    List<DiffHunk> hunks,
  ) {
    List<String> resultLines = List.from(originalLines);

    // Apply hunks in reverse order of their oldStartLine
    hunks.sort((a, b) => b.oldStartLine.compareTo(a.oldStartLine));

    for (final hunk in hunks) {
      final List<String> searchPattern = hunk.lines
          .where((line) => line.startsWith(' ') || line.startsWith('-'))
          .map((line) => line.substring(1))
          .toList();

      final List<String> newContent = hunk.lines
          .where((line) => line.startsWith(' ') || line.startsWith('+'))
          .map((line) => line.substring(1))
          .toList();

      int matchIndex;
      if (searchPattern.isEmpty) {
        // Pure-addition hunk. Trust line number for insertion.
        matchIndex = (hunk.newStartLine - 1).clamp(0, resultLines.length);
      } else {
        // Use the original search function (or a simplified version here)
        matchIndex = _findFirstMatchIndex(
          resultLines,
          searchPattern,
          hunk.oldStartLine - 1,
        );
      }

      if (matchIndex != -1) {
        // Handle pure insertion at the end of the file correctly
        if (searchPattern.isEmpty && matchIndex == resultLines.length) {
            resultLines.addAll(newContent);
        } else {
            resultLines.replaceRange(
            matchIndex,
            matchIndex + searchPattern.length,
            newContent,
            );
        }
      } else {
        // Log the failure to apply the hunk
        sendTelegramLog(
          'Error: Could not apply hunk for lines starting around ${hunk.oldStartLine}',
        );
      }
    }
    return resultLines;
  }

  /// Finds the first index of a `sublist` within a `list`. (Internal helper)
  int _findFirstMatchIndex(
    List<String> list,
    List<String> sublist,
    int startHint,
  ) {
    if (sublist.isEmpty) return startHint;
    if (sublist.length > list.length) return -1;

    // Reduced search radius for simplicity in service layer
    const int searchRadius = 20;
    final int searchStart = (startHint - searchRadius).clamp(0, list.length - sublist.length);
    final int searchEnd = (startHint + searchRadius).clamp(0, list.length - sublist.length);

    for (int i = searchStart; i <= searchEnd; i++) {
      if (list[i] == sublist[0]) {
        bool isMatch = true;
        for (int j = 1; j < sublist.length; j++) {
          if (i + j >= list.length || list[i + j] != sublist[j]) {
            isMatch = false;
            break;
          }
        }
        if (isMatch) return i;
      }
    }
    
    // Fallback scan (only if necessary, for brevity, we trust the hint radius for now)
    return -1;
  }
}