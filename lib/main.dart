import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:git2dart/git2dart.dart';

import 'entries.dart';
import 'models/git_models.dart';
import 'recent_projects_store.dart';
import 'repo_loader.dart';
import 'screens/git_screen.dart';
import 'screens/pkg_search_screen.dart';
import 'utils/colors.dart';
import 'widgets/repo_browser_scaffold.dart';

Future<void> main() async {    WidgetsFlutterBinding.ensureInitialized();
  await PlatformSpecific.initialize();


  // Optional: makes system UI match true-black style.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Color(0xFF000000),
    systemNavigationBarIconBrightness: Brightness.light,
    statusBarIconBrightness: Brightness.light,
  ));


  runApp(const GitLoaderApp());
}

// Global selection state to keep track of files across navigation
final Set<String> selectedPaths = {};

class GitLoaderApp extends StatelessWidget {
  const GitLoaderApp({super.key});

  @override
  Widget build(BuildContext context) {    const bg = Color(0xFF000000);
    const surface = Color(0xFF0B0B0F);
    const surface2 = Color(0xFF111118);
    const border = Color(0xFF24242C);
    const accent = Color(0xFF7C4DFF); // premium violet accent
    const accent2 = Color(0xFF00E5FF); // cyan hint (used subtly)
     final base = ThemeData(
     brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(
        surface: surface,
        surfaceContainerHighest: surface2,
        primary: accent,
        secondary: accent2,
        outline: border,
      ),
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: Colors.white,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF1C1C24),
        thickness: 1,
        space: 1,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: const TextStyle(color: Color(0xFF9A9AAA)),
        labelStyle: const TextStyle(color: Color(0xFFEDEDF5)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: accent, width: 1.4),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF111118),
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 0.2),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        bodyLarge: TextStyle(fontSize: 15, height: 1.35),
        bodyMedium: TextStyle(fontSize: 14, height: 1.35),
        labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );

    final textTheme = GoogleFonts.interTextTheme(base.textTheme).copyWith(
      titleLarge: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800, height: 1.15),
      titleMedium: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, height: 1.2),
      bodyLarge: GoogleFonts.inter(fontSize: 15.5, fontWeight: FontWeight.w500, height: 1.45),
      bodyMedium: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w500, height: 1.45),
      labelLarge: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.2),
      labelMedium: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.2),
    );

    final theme = base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        elevation: 0,
        titleTextStyle: textTheme.titleMedium?.copyWith(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border, width: 1),
        ),
      ),
    );
    

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: const RemoteLoaderPage(),
    );
  }
}

class RemoteLoaderPage extends StatefulWidget {
  const RemoteLoaderPage({super.key});

  @override
  State<RemoteLoaderPage> createState() => _RemoteLoaderPageState();       
}

class _RemoteLoaderPageState extends State<RemoteLoaderPage>
    with WidgetsBindingObserver {
  static const MethodChannel _storagePermissionChannel =
      MethodChannel('gitloader/storage_permission');

  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _branchController = TextEditingController();
  final TextEditingController _tagController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();

  bool _obscureToken = true;
  bool _showAdvancedOptions = false;
  bool _useExternalStorage = false;
  String? _customExternalPath;

  bool _isLoading = false;
  double _downloadProgress = 0.0;
  String? _statusMessage;
  bool _loadingRecents = true;
  List<ProjectEntry> _recentProjects = [];
  Completer<void>? _resumeCompleter;

  Future<void> _loadRecents() async {
    final items = await ProjectHistoryStore().load();
    if (!mounted) return;
    setState(() {
      _recentProjects = items;
      _loadingRecents = false;
    });
  }

  Future<void> _recordProject(String name, String path) async {
    await ProjectHistoryStore().add(
      ProjectEntry(name: name, path: path, openedAt: DateTime.now()),
    );
    await _loadRecents();
  }

  Future<void> _pickExternalFolder() async {
    try {
      final status = await Permission.manageExternalStorage.status;
      if (status.isDenied) {
        final req = await Permission.manageExternalStorage.request();
        if (!req.isGranted && mounted) {
          final ensured = await _ensureAndroidStorageAccess();
          if (!ensured) return;
        }
      }

      final path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select storage directory for Git repositories',
      );
      if (path != null && mounted) {
        setState(() {
          _customExternalPath = path;
          _useExternalStorage = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick directory: $e')),
        );
      }
    }
  }

  Future<_ConflictResolution?> _resolveConflict(
    String baseDir,
    String suggestedName,
  ) {
    final controller = TextEditingController(text: "${suggestedName}_copy");
    return showDialog<_ConflictResolution>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Folder already exists'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'A folder named "$suggestedName" already exists at\n$baseDir.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Rename to',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_ConflictResolution.cancel()),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_ConflictResolution.replace()),
            child: const Text('Replace'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx)
                .pop(_ConflictResolution.rename(controller.text.trim())),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  String _deriveRepoName(String url) {
    final cleaned = url.endsWith('.git') ? url.substring(0, url.length - 4) : url;
    final parts = cleaned.split('/');
    return parts.isNotEmpty ? parts.last : 'repository';
  }

  Future<void> _openProject(String path, {String? name}) async {
    final projectName = name ?? p.basename(path);
    if (!await Directory(path).exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Path does not exist: $path')),
        );
      }
      return;
    }
    await _recordProject(projectName, path);

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RepoBrowserScaffold(path: path, title: projectName),
      ),
    );
  }

  Widget _buildRecentProjectsSection() {
    if (_loadingRecents) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: LinearProgressIndicator(),
      );
    }
    if (_recentProjects.isEmpty) return const SizedBox.shrink();

    final items = _recentProjects.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Recent projects',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const Spacer(),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProjectsHistoryPage(
                      onOpen: (entry) =>
                          _openProject(entry.path, name: entry.name),
                    ),
                  ),
                );
              },
              child: const Text('View all'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...items.map(
          (entry) => Card(
            child: ListTile(
              title: Text(entry.name, overflow: TextOverflow.ellipsis),
              subtitle: Text(entry.path, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                icon: const Icon(Icons.open_in_new),
                onPressed: () =>
                    _openProject(entry.path, name: entry.name),
              ),
              onTap: () => _openProject(entry.path, name: entry.name),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadRecents();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resumeCompleter?.complete();
    _urlController.dispose();
    _branchController.dispose();
    _tagController.dispose();
    _usernameController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _resumeCompleter != null) {
      _resumeCompleter!.complete();
      _resumeCompleter = null;
    }
  }

  Future<void> _waitUntilResumed() async {
    final completer = Completer<void>();
    _resumeCompleter = completer;
    try {
      await completer.future.timeout(const Duration(minutes: 2));
    } catch (_) {
      // No-op: user may not come back from settings immediately.
    } finally {
      if (_resumeCompleter == completer) {
        _resumeCompleter = null;
      }
    }
  }

  Future<bool> _hasAllFilesAccess() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _storagePermissionChannel.invokeMethod<bool>(
            'isExternalStorageManager',
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _requiresAllFilesAccess(String targetPath) async {
    if (!Platform.isAndroid) return false;
    final docs = await getApplicationDocumentsDirectory();
    if (targetPath.startsWith(docs.path)) return false;
    final appExternal = await getExternalStorageDirectory();
    if (appExternal != null && targetPath.startsWith(appExternal.path)) {
      return false;
    }
    return true;
  }

  Future<bool> _ensureAndroidStorageAccess() async {
    if (!Platform.isAndroid) return true;
    if (await _hasAllFilesAccess()) return true;
    if (!mounted) return false;

    final openSettings = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Storage access required'),
            content: const Text(
              'This app needs "Manage all files" access on Android to read and '
              'write repositories in shared storage.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Open settings'),
              ),
            ],
          ),
        ) ??
        false;

    if (!openSettings) return false;

    try {
      await _storagePermissionChannel
          .invokeMethod('openManageAllFilesAccessSettings');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open Android settings')),
        );
      }
      return false;
    }

    await _waitUntilResumed();
    final granted = await _hasAllFilesAccess();
    if (!granted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Storage permission is still disabled. Enable it in settings to continue.',
          ),
        ),
      );
    }
    return granted;
  }

  void _loadRepo() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _statusMessage = "Please enter a valid Git repository URL");
      return;
    }

    String storagePath;
    if (_useExternalStorage) {
      if (_customExternalPath != null && _customExternalPath!.isNotEmpty) {
        storagePath = _customExternalPath!;
      } else {
        storagePath = await RepoUtils.getExternalStoragePath();
      }
    } else {
      storagePath = await RepoUtils.getInternalStoragePath();
    }

    final requiresAllFilesAccess =
        await _requiresAllFilesAccess(storagePath);
    if (requiresAllFilesAccess && !await _ensureAndroidStorageAccess()) {
      setState(() => _statusMessage = "Storage permission required");
      return;
    }

    String folderName = _deriveRepoName(url);
    String destinationPath = p.join(storagePath, folderName);
    while (await Directory(destinationPath).exists()) {
      final resolution = await _resolveConflict(storagePath, folderName);
      if (resolution == null || resolution.action == _ConflictAction.cancel) {
        setState(() => _statusMessage = "Clone cancelled");
        return;
      }
      if (resolution.action == _ConflictAction.replace) {
        await Directory(destinationPath).delete(recursive: true);
        break;
      }
      if (resolution.action == _ConflictAction.rename) {
        final newName = resolution.newName?.trim();
        if (newName == null || newName.isEmpty) continue;
        folderName = newName;
        destinationPath = p.join(storagePath, folderName);
      }
    }

    final branch = _branchController.text.trim().isNotEmpty
        ? _branchController.text.trim()
        : null;
    final tag = _tagController.text.trim().isNotEmpty
        ? _tagController.text.trim()
        : null;

    AuthSpec? authSpec;
    final username = _usernameController.text.trim();
    final token = _tokenController.text.trim();
    if (username.isNotEmpty || token.isNotEmpty) {
      authSpec = AuthSpec(
        mode: AuthMode.httpsUserPass,
        username: username.isNotEmpty ? username : 'git',
        password: token,
      );
    }

    setState(() {
      _isLoading = true;
      _downloadProgress = 0.0;
      _statusMessage = "Cloning repository in background...";
    });

    try {
      final localPath = await RepoUtils.downloadAndExtract(
        url,
        targetDirPath: storagePath,
        folderName: folderName,
        branch: branch,
        tag: tag,
        authSpec: authSpec,
        overwriteExisting: false,
        onProgress: (progress, status) {
          if (!mounted) return;
          setState(() {
            _downloadProgress = progress.clamp(0.0, 1.0);
            if (status != null && status.isNotEmpty) {
              _statusMessage = status;
            }
          });
        },
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _downloadProgress = 1.0;
          _statusMessage = null;
        });
        await _openProject(localPath, name: folderName);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _downloadProgress = 0.0;
          _statusMessage = "Error: $e";
        });
      }
    }
  }

  void _loadLocalRepo() async {
    setState(() {
      _isLoading = true;
      _statusMessage = "Selecting local repository...";
    });

    try {
      // Use file_picker to select a directory
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select Git Repository Folder',
      );

      if (selectedDirectory == null) {
        setState(() {
          _isLoading = false;
          _statusMessage = "No directory selected";
        });
        return;
      }

      final requiresAllFilesAccess =
          await _requiresAllFilesAccess(selectedDirectory);
      if (requiresAllFilesAccess && !await _ensureAndroidStorageAccess()) {
        setState(() {
          _isLoading = false;
          _statusMessage = "Storage permission required";
        });
        return;
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = null;
        });
        await _openProject(
          selectedDirectory,
          name: p.basename(selectedDirectory),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = "Error: $e";
      });
    }
  }

  Widget _buildStorageSelector() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.sd_storage_outlined, size: 18, color: AppColors.accent),
              SizedBox(width: 8),
              Text(
                'Storage Destination',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline, size: 14),
                      SizedBox(width: 6),
                      Text('Internal Storage'),
                    ],
                  ),
                  selected: !_useExternalStorage,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _useExternalStorage = false);
                    }
                  },
                  selectedColor: AppColors.accent.withValues(alpha: 0.2),
                  backgroundColor: AppColors.surface2,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    color: !_useExternalStorage
                        ? Colors.white
                        : AppColors.textSecondary,
                    fontWeight: !_useExternalStorage
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                  side: BorderSide(
                    color: !_useExternalStorage
                        ? AppColors.accent
                        : AppColors.border,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  label: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.folder_shared_outlined, size: 14),
                      SizedBox(width: 6),
                      Text('External Storage'),
                    ],
                  ),
                  selected: _useExternalStorage,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _useExternalStorage = true);
                      if (_customExternalPath == null) {
                        _pickExternalFolder();
                      }
                    }
                  },
                  selectedColor: AppColors.accent.withValues(alpha: 0.2),
                  backgroundColor: AppColors.surface2,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    color: _useExternalStorage
                        ? Colors.white
                        : AppColors.textSecondary,
                    fontWeight: _useExternalStorage
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                  side: BorderSide(
                    color: _useExternalStorage
                        ? AppColors.accent
                        : AppColors.border,
                  ),
                ),
              ),
            ],
          ),
          if (_useExternalStorage) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickExternalFolder,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.folder_open, size: 16, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _customExternalPath ?? 'Default External Storage (Tap to change folder)',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.edit_outlined, size: 14, color: AppColors.accent),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAdvancedOptionsSection() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              setState(() {
                _showAdvancedOptions = !_showAdvancedOptions;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.tune, size: 18, color: AppColors.accent),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Advanced Options (Branch, Tag, Auth)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Icon(
                    _showAdvancedOptions
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_showAdvancedOptions) ...[
            const Divider(color: AppColors.border, height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _branchController,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textPrimary,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Branch',
                            hintText: 'e.g. main, dev',
                            prefixIcon: const Icon(Icons.fork_right, size: 18),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _tagController,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textPrimary,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Tag',
                            hintText: 'e.g. v1.0.0',
                            prefixIcon: const Icon(Icons.label_outline, size: 18),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _usernameController,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textPrimary,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Username',
                            hintText: 'git or username',
                            prefixIcon: const Icon(Icons.person_outline, size: 18),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _tokenController,
                          obscureText: _obscureToken,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textPrimary,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Token / Password',
                            hintText: 'PAT or password',
                            prefixIcon: const Icon(Icons.key_outlined, size: 18),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureToken
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                                size: 18,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscureToken = !_obscureToken;
                                });
                              },
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.terminal),
          tooltip: 'Git2Dart Diagnostic Studio',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const Git2DartDemoHome(),
              ),
            );
          },
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.auto_awesome_motion,
                size: 80,
                color: AppColors.accent,
              ),
              const SizedBox(height: 24),
              const Text(
                "GitLoader",
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Enter a GitHub URL or select a local repository",
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 40),
              TextField(
                controller: _urlController,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: "Repository URL",
                  hintText: "https://github.com/username/repo",
                  filled: true,
                  fillColor: AppColors.surface,
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: AppColors.border),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(
                      color: AppColors.accent,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _buildStorageSelector(),
              const SizedBox(height: 14),
              _buildAdvancedOptionsSection(),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _loadRepo,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    shape: Platform.isAndroid
                        ? RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          )
                        : RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          "EXPLORE REMOTE REPO",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _loadLocalRepo,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.surface,
                    foregroundColor: AppColors.textPrimary,
                    shape: Platform.isAndroid
                        ? RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          )
                        : RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                    side: const BorderSide(color: AppColors.accent, width: 1),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.folder_open, size: 20),
                            const SizedBox(width: 8),
                            const Text(
                              "SELECT LOCAL REPOSITORY",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 24),
              _buildRecentProjectsSection(),
              const SizedBox(height: 12),
                       SizedBox(height: 20,),
                ElevatedButton(onPressed: (){
                    Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FileSearchEntry(),
          ),
        );
                }, child: Text("Search files and content")),
                                       SizedBox(height: 20,),
                ElevatedButton(onPressed: (){
                    Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GoPackageSearchPage(),
          ),
        );
                }, child: Text("Search packages and libraries")),
              if (_isLoading) ...[
                const SizedBox(height: 20),
                SizedBox(
                  width: 240,
                  child: LinearProgressIndicator(
                    value: _downloadProgress == 0.0
                        ? null
                        : _downloadProgress,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(999),
                    backgroundColor: AppColors.border,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.accent,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _downloadProgress >= 1.0
                      ? "Finalizing repository..."
                      : "Clone progress: ${(_downloadProgress * 100).round()}%",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.accent),
                ),
              ],
              if (_statusMessage != null) ...[
                const SizedBox(height: 20),
                Text(
                  _statusMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _statusMessage!.startsWith("Error")
                        ? Colors.redAccent
                        : AppColors.accent,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ProjectsHistoryPage extends StatefulWidget {
  final Future<void> Function(ProjectEntry entry) onOpen;
  const ProjectsHistoryPage({super.key, required this.onOpen});

  @override
  State<ProjectsHistoryPage> createState() => _ProjectsHistoryPageState();
}

class _ProjectsHistoryPageState extends State<ProjectsHistoryPage> {
  bool _loading = true;
  List<ProjectEntry> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await ProjectHistoryStore().load();
    if (!mounted) return;
    setState(() {
      _items = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Projects history')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('No projects yet'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemBuilder: (context, index) {
                    final entry = _items[index];
                    return ListTile(
                      title: Text(entry.name),
                      subtitle: Text(entry.path),
                      leading: const Icon(Icons.history),
                      trailing: IconButton(
                        icon: const Icon(Icons.open_in_new),
                        onPressed: () async => widget.onOpen(entry),
                      ),
                      onTap: () async => widget.onOpen(entry),
                    );
                  },
                  separatorBuilder: (_, _) => const Divider(),
                  itemCount: _items.length,
                ),
    );
  }
}

class _ConflictResolution {
  final _ConflictAction action;
  final String? newName;

  const _ConflictResolution._private(this.action, [this.newName]);

  factory _ConflictResolution.rename(String? name) =>
      _ConflictResolution._private(_ConflictAction.rename, name);
  factory _ConflictResolution.replace() =>
      _ConflictResolution._private(_ConflictAction.replace);
  factory _ConflictResolution.cancel() =>
      _ConflictResolution._private(_ConflictAction.cancel);
}

enum _ConflictAction { rename, replace, cancel }
