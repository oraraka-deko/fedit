// lib/models/diff_hunk.dart

class DiffHunk {
  final int oldStartLine;
  final int oldNumLines;
  final int newStartLine;
  final int newNumLines;
  final List<String> lines; // Each line includes its prefix ('+', '-', ' ')

  DiffHunk({
    required this.oldStartLine,
    required this.oldNumLines,
    required this.newStartLine,
    required this.newNumLines,
    required this.lines,
  });

  DiffHunk copyWith({List<String>? lines}) {
    return DiffHunk(
      oldStartLine: oldStartLine,
      oldNumLines: oldNumLines,
      newStartLine: newStartLine,
      newNumLines: newNumLines,
      lines: lines ?? this.lines,
    );
  }

  @override
  String toString() {
    return 'Hunk(old:$oldStartLine,$oldNumLines new:$newStartLine,$newNumLines lines:${lines.length})';
  }
}