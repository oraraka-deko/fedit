// lib/utils/regex_utils.dart


/// Helper to convert wildcard patterns (like glob syntax) to RegExp.
List<RegExp> parsePatternsToRegex(String patternsInput) {
  if (patternsInput.trim().isEmpty) return [];
  return patternsInput
      .split(',')
      .map((pattern) {
        pattern = pattern.trim();
        if (pattern.isEmpty) return null;

        String regexString = RegExp.escape(pattern);

        // Replace escaped '*' with '.*' for wildcard purposes
        regexString = regexString.replaceAll('\\*', '.*');

        // Handle path separators if required (e.g., path starting with /)
        if (pattern.startsWith('/')) {
          regexString = '^$regexString';
        }
        if (pattern.endsWith('/')) {
          regexString = '$regexString\$';
        }

        // Case-insensitive matching is generally safer for file paths/names
        return RegExp(regexString, caseSensitive: false);
      })
      .whereType<RegExp>()
      .toList();
}