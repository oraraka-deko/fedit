import 'package:path/path.dart' as p;
import 'config.dart';

class AiFileFilter {
  final List<RegExp> _includeGlobs;
  final List<RegExp> _excludeGlobs;

  AiFileFilter._(this._includeGlobs, this._excludeGlobs);

  static AiFileFilter? _cached;
  static bool _listenerAttached = false;

  static Future<AiFileFilter> load() async {
    _ensureReloadListener();
    if (_cached != null) return _cached!;
    final config = await Config.load();
    final includeGlobs = _compileGlobs(config.hiddenIncludePatterns);
    final excludeGlobs = _compileGlobs(config.hiddenExcludePatterns);
    _cached = AiFileFilter._(includeGlobs, excludeGlobs);
    return _cached!;
  }

  static void invalidateCache() {
    _cached = null;
  }

  static void _ensureReloadListener() {
    if (_listenerAttached) return;
    Config.reloadNotifier.addListener(invalidateCache);
    _listenerAttached = true;
  }

  bool isHidden(String relativePath) {
    final normalized = _normalizePath(relativePath).toLowerCase();
    if (normalized.isEmpty) return false;

    if (_matchesAny(normalized, _includeGlobs)) return false;

    if (_matchesDefaults(normalized)) return true;
    if (_matchesAny(normalized, _excludeGlobs)) return true;

    return false;
  }

  static bool _matchesDefaults(String normalizedPath) {
    for (final prefix in _hiddenPathPrefixes) {
      if (normalizedPath == prefix || normalizedPath.startsWith('$prefix/')) {
        return true;
      }
    }

    final parts = normalizedPath.split('/');
    for (final part in parts) {
      if (_hiddenDirNames.contains(part)) return true;
      for (final suffix in _hiddenDirSuffixes) {
        if (part.endsWith(suffix)) return true;
      }
    }

    final base = parts.isNotEmpty ? parts.last : normalizedPath;
    if (_hiddenFileNames.contains(base)) return true;
    for (final suffix in _hiddenFileSuffixes) {
      if (base.endsWith(suffix)) return true;
    }

    if (base.startsWith('dockerfile.')) return true;
    if (base.startsWith('docker-compose.') &&
        (base.endsWith('.yml') || base.endsWith('.yaml'))) {
      return true;
    }

    return false;
  }

  static List<RegExp> _compileGlobs(List<String> patterns) {
    return patterns
        .map((pattern) => pattern.trim())
        .where((pattern) => pattern.isNotEmpty)
        .map((pattern) {
          var normalized = _normalizePath(pattern).toLowerCase();
          if (normalized.endsWith('/')) {
            normalized = '$normalized**';
          }
          return _globToRegExp(normalized);
        })
        .toList();
  }

  static bool _matchesAny(String normalizedPath, List<RegExp> patterns) {
    for (final regex in patterns) {
      if (regex.hasMatch(normalizedPath)) return true;
    }
    return false;
  }

  static String _normalizePath(String input) =>
      p.normalize(input).replaceAll('\\', '/');

  static RegExp _globToRegExp(String pattern) {
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

  static const Set<String> _hiddenDirNames = {
    '.git',
    '.svn',
    '.hg',
    '.dart_tool',
    'build',
    'dist',
    'out',
    'node_modules',
    '.npm',
    '.yarn',
    '.next',
    '.nuxt',
    '.cache',
    'coverage',
    '.nyc_output',
    '.parcel-cache',
    '.webpack',
    'target',
    '.gradle',
    '.idea',
    '.vscode',
    '.vs',
    'bin',
    'obj',
    'packages',
    'vendor',
    'pods',
    '.symlinks',
    '__pycache__',
    '.pytest_cache',
    'htmlcov',
    '.tox',
    '.hypothesis',
    'pip-wheel-metadata',
    '.mypy_cache',
    '.ruff_cache',
    '.bundle',
    'tmp',
    'temp',
    'log',
    'logs',
    'cmakefiles',
    '.mvn',
    'gradle',
    '_site',
    'public',
    '_book',
    'site',
    'readthedocs',
    '.history',
    '.trash',
    '.local',
    '.config',
    '.docker',
    'redis',
    'memcached',
    'dumps',
    'backups',
    'venv',
    '.venv',
    'env',
    '.env',
  };

  static const Set<String> _hiddenDirSuffixes = {
    '.egg-info',
  };

  static const Set<String> _hiddenFileNames = {
    '.dockerignore',
    '.gitlab-ci.yml',
    '.travis.yml',
    'circle.yml',
    '.coverage',
    'yarn.lock',
    'package-lock.json',
    'npm-debug.log',
    'yarn-error.log',
    '.yarnrc',
    'pubspec.lock',
    '.packages',
    'go.sum',
    'cargo.lock',
    'cmake_install.cmake',
    'makefile',
    'gnumakefile',
    'gradlew',
    'gradlew.bat',
    'mvnw',
    'mvnw.cmd',
    'cmakecache.txt',
    '.project',
    '.classpath',
    '.env',
    'desktop.ini',
    'thumbs.db',
    '.ds_store',
  };

  static const Set<String> _hiddenFileSuffixes = {
    '.pyc',
    '.pyo',
    '.pyd',
    '.class',
    '.jar',
    '.war',
    '.ear',
    '.apk',
    '.ipa',
    '.app',
    '.aab',
    '.rlib',
    '.dll',
    '.so',
    '.dylib',
    '.exe',
    '.test',
    '.prof',
    '.o',
    '.obj',
    '.a',
    '.log',
    '.db',
    '.sqlite',
    '.sqlite3',
    '.dump',
    '.backup',
    '.swp',
    '.swo',
    '~',
    '.csproj.user',
    '.suo',
    '.user',
  };

  static const Set<String> _hiddenPathPrefixes = {
    '.github/workflows',
    'ios/pods',
    'ios/.symlinks',
    'android/.gradle',
    'android/build',
    'android/app/build',
    'android/.idea',
    'storage/framework/cache',
    'storage/framework/sessions',
    'storage/framework/views',
    'bootstrap/cache',
  };
}
