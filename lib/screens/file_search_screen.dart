
// ignore_for_file: use_build_context_synchronously

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:debounce_throttle/debounce_throttle.dart';
import 'package:worker_manager/worker_manager.dart';
import 'package:path/path.dart' as path_pkg;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../main.dart';
import '../models/file_content.dart';
import '../models/diff_hunk.dart';
import '../services/search_service.dart';
import '../services/diff_service.dart';
import '../widgets/file_result_list.dart';
import '../ai/file_filters.dart';
import '../tglogs.dart';

class FileSearchScreen extends StatefulWidget {
  const FileSearchScreen({super.key});

  @override
  State<FileSearchScreen> createState() => _FileSearchScreenState();
}

class _FileSearchScreenState extends State<FileSearchScreen> {
  // === Services ===
  late SearchService _searchService;
  late DiffService _diffService;

  // === Controllers ===
  String? selectedPath;
  final TextEditingController _fileTypeController = TextEditingController(
    text: '.dart,.json,.yaml',
  );
  final TextEditingController _diffInputController = TextEditingController();
  final TextEditingController _includePathPatternController =
      TextEditingController();
  final TextEditingController _excludePathPatternController =
      TextEditingController();
  final TextEditingController _includeFileNamePatternController =
      TextEditingController();
  final TextEditingController _excludeFileNamePatternController =
      TextEditingController();
  final TextEditingController _postSearchContentFilterController =
      TextEditingController();

  // === State ===
  List<FileContent> _foundFiles = [];
  List<FileContent> _displayedFiles = [];
  bool isSearching = false;
  int totalFilesFound = 0;
  bool _isAnyFileSelected = false;

  // Filter Toggles
  bool _isFileNamePatternFilteringEnabled = false;
  bool _isPathPatternFilteringEnabled = false;
  bool _isPostSearchContentFilteringEnabled = false;
  bool _isPostSearchContentInclude = true;

  // Diff State
  Map<String, List<DiffHunk>> _parsedDiffs = {};

  // Utility
  late Debouncer _contentFilterDebouncer;
  bool _isResultsPaneExpanded = true;

  @override
  void initState() {
    super.initState();
    _diffService = DiffService();
    _searchService = SearchService(
      logError: _showError,
      onFileFound: _onFileFoundCallback,
      isSearchActive: () => isSearching,
    );

    _contentFilterDebouncer = Debouncer(
      const Duration(milliseconds: 500),
      onChanged: (debouncedValue) {
        _applyPostSearchContentFilters().catchError((error) {
          _showError('Error applying debounced content filter: $error');
        });
      },
      initialValue: null,
    );
    _postSearchContentFilterController.addListener(_onContentFilterTextChanged);

    // Placeholder for permission request
    // _requestPermissions();
  }

  // --- Utility & Feedback ---
  String _formatContentAsGitHubDiff(FileContent fileContent) {
    final buffer = StringBuffer();
    final lines = fileContent.content.split('\n');
    final numLines = lines.length;

    buffer.writeln('--- a/${fileContent.filePath}');
    buffer.writeln('+++ b/${fileContent.filePath}');
    buffer.writeln(
      '@@ -1,$numLines +1,$numLines @@',
    ); // Assuming entire file is new/changed

    for (int i = 0; i < numLines; i++) {
      buffer.writeln(' ${lines[i]}'); // ' ' indicates context line
    }
    return buffer.toString();
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  void _showSuccess(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.green),
      );
    }
  }

  void _updateSelectionState() {
    setState(() {
      _isAnyFileSelected = _displayedFiles.any((file) => file.isSelected);
    });
  }

  // --- Search & File System Logic ---

  Future<void> _selectDirectory() async {
    try {
      String? path = await FilePicker.platform.getDirectoryPath();
      if (path != null) {
        setState(() {
          selectedPath = path;
        });
      }
    } catch (e) {
      _showError('Error selecting directory: $e');
    }
  }

  void _onFileFoundCallback(FileContent fileContent) {
    if (mounted) {
      setState(() {
        _foundFiles.add(fileContent);
        totalFilesFound++;
      });
    }
  }

  Future<void> _startSearch() async {
    if (selectedPath == null || _fileTypeController.text.trim().isEmpty) {
      _showError('Please select a directory and enter file types.');
      return;
    }

    setState(() {
      isSearching = true;
      _foundFiles = [];
      _displayedFiles = [];
      totalFilesFound = 0;
      _isAnyFileSelected = false;
    });

    try {
      List<String> fileExtensions = _fileTypeController.text
          .split(',')
          .map((type) => type.trim().toLowerCase())
          .where((type) => type.isNotEmpty)
          .toList();

      final filter = await AiFileFilter.load();
      await _searchService.searchFiles(
        directoryPath: selectedPath!,
        allowedExtensions: fileExtensions,
        includePathPatterns: _includePathPatternController.text,
        excludePathPatterns: _excludePathPatternController.text,
        includeFileNamePatterns: _includeFileNamePatternController.text,
        excludeFileNamePatterns: _excludeFileNamePatternController.text,
        isPathFilteringEnabled: _isPathPatternFilteringEnabled,
        isFileNameFilteringEnabled: _isFileNamePatternFilteringEnabled,
        filter: filter,
        rootPath: selectedPath!,
      );

      _showSuccess('Search completed! Found $totalFilesFound files');

      if (_isPostSearchContentFilteringEnabled &&
          _postSearchContentFilterController.text.isNotEmpty) {
        await _applyPostSearchContentFilters();
      } else {
        setState(() {
          _displayedFiles = List.from(_foundFiles);
        });
      }
    } catch (e) {
      _showError('Error during search: $e');
    } finally {
      if (mounted) {
        setState(() {
          isSearching = false;
        });
      }
    }
  }

  void _cancelSearch() {
    setState(() {
      isSearching = false;
    });
  }

  // --- Post-Search Content Filtering ---

  void _onContentFilterTextChanged() {
    if (_isPostSearchContentFilteringEnabled) {
      // Use setValue to trigger onChanged in the debouncer
      _contentFilterDebouncer.setValue(_postSearchContentFilterController.text);
    }
  }

  Future<void> _applyPostSearchContentFilters() async {
    final String pattern = _postSearchContentFilterController.text.trim();

    if (!_isPostSearchContentFilteringEnabled || pattern.isEmpty) {
      setState(() {
        _displayedFiles = List.from(_foundFiles);
      });
      return;
    }

    try {
      final List<Cancelable> tasks = (_foundFiles.map((file) {
        return workerManager.execute(
          (String content, String regexPattern, bool include) {
                file.content;
                pattern;
                _isPostSearchContentInclude;
                // This code runs in an isolate
                final RegExp workerRegex = RegExp(
                  regexPattern,
                  caseSensitive: false,
                );
                final bool matches = workerRegex.hasMatch(content);
                return include ? matches : !matches;
              }
              as Execute,
        );
      }).toList());
      final List<bool> taskResults = await Future.wait(
        tasks.map((c) => c.future as Future<bool>), // Cast Cancelable future
      );

      List<FileContent> results = [];
      for (int i = 0; i < _foundFiles.length; i++) {
        if (taskResults[i]) {
          results.add(_foundFiles[i]);
        }
      }

      setState(() {
        _displayedFiles = results;
        _updateSelectionState();
      });
    } catch (e) {
      _showError('Error applying content filter: $e');
    }
  }

  // --- Diff Handling (Delegating Parsing/Applying to Service) ---

  Future<void> _loadDiffFromFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['diff', 'patch', 'txt'],
      );
      if (result != null && result.files.single.path != null) {
        File diffFile = File(result.files.single.path!);
        String diffContent = await diffFile.readAsString();
        _diffInputController.text = diffContent;
        _parseAndPrepareDiff(diffContent);
      }
    } catch (e) {
      _showError('Error loading diff from file: $e');
    }
  }

  void _loadDiffFromTextInput() {
    String diffContent = _diffInputController.text.trim();
    if (diffContent.isEmpty) {
      _showError('Please paste diff content into the text field.');
      return;
    }
    _parseAndPrepareDiff(diffContent);
  }

  void _parseAndPrepareDiff(String diffContent) {
    try {
      _parsedDiffs = _diffService.parseGitHubDiff(diffContent);
      if (_parsedDiffs.isEmpty) {
        _showError('No valid diff entries found in the provided content.');
      } else {
        _showSuccess('Diff content parsed successfully!');
      }
    } catch (e) {
      _showError('Error parsing diff content: $e');
      _parsedDiffs = {};
    }
    setState(() {});
  }

  int _findFirstMatchIndex(
    List<String> list,
    List<String> sublist,
    int startHint,
  ) {
    if (sublist.isEmpty) return startHint;
    if (sublist.length > list.length) return -1;

    const int searchRadius = 20;
    final int searchStart = (startHint - searchRadius).clamp(
      0,
      list.length - sublist.length,
    );
    final int searchEnd = (startHint + searchRadius).clamp(
      0,
      list.length - sublist.length,
    );

    // Prioritized search within the radius
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

    // Full scan as a fallback for robustness
    for (int i = 0; i <= list.length - sublist.length; i++) {
      if (i >= searchStart && i <= searchEnd) {
        continue; // Skip already searched area
      }

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
    return -1;
  }

  List<String> _applyHunksToLines(
    List<String> originalLines,
    List<DiffHunk> hunks,
  ) {
    List<String> resultLines = List.from(originalLines);

    // Apply hunks in reverse order of their oldStartLine to prevent index shifts
    // from affecting subsequent patches.
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
        matchIndex = _findFirstMatchIndex(
          resultLines,
          searchPattern,
          hunk.oldStartLine - 1,
        );
      }

      if (matchIndex != -1) {
        resultLines.replaceRange(
          matchIndex,
          matchIndex + searchPattern.length,
          newContent,
        );
      } else {
        sendTelegramLog(
          'Error: Could not apply hunk for lines starting around ${hunk.oldStartLine} '
          'in file (pattern: ${searchPattern.take(3).join(', ')}...). '
          'File content may have diverged too much. Skipping this hunk.',
        );
        // In a real app, you might collect these errors to display to the user.
      }
    }
    return resultLines;
  }

  Future<void> _showDiffPreviewAndApply() async {
    if (_parsedDiffs.isEmpty) {
      _showError('No diffs parsed. Please load diff content first.');
      return;
    }

    List<String> previewContent = [];
    Map<String, List<String>> fileNewContents =
        {}; // Store new content ready for saving

    bool hasErrors = false;
    for (final filePath in _parsedDiffs.keys) {
      final file = File(filePath);
      if (!await file.exists()) {
        previewContent.add('--- ERROR: File not found for diff: $filePath ---');
        hasErrors = true;
        continue;
      }

      final currentContent = await file.readAsString();
      final originalLines = currentContent.split('\n');

      final hunks = _parsedDiffs[filePath]!;
      final newLines = _applyHunksToLines(originalLines, hunks);
      fileNewContents[filePath] = newLines;

      previewContent.add('--- Diff Preview for: $filePath ---');
      previewContent.add('Original (first 10 lines):');
      previewContent.addAll(originalLines.take(10).map((l) => ' $l'));
      if (originalLines.length > 10) {
        previewContent.add('... (${originalLines.length - 10} more lines)');
      }

      previewContent.add('\nProposed Changes (Diff Hunks):');
      for (final hunk in hunks) {
        previewContent.add(
          '@@ -${hunk.oldStartLine},${hunk.oldNumLines} +${hunk.newStartLine},${hunk.newNumLines} @@',
        );
        previewContent.addAll(hunk.lines);
      }

      previewContent.add(
        '\nNew Content (first 10 lines, after applying diff):',
      );
      previewContent.addAll(newLines.take(10).map((l) => ' $l'));
      if (newLines.length > 10) {
        previewContent.add('... (${newLines.length - 10} more lines)');
      }
      previewContent.add('\n');
    }

    if (previewContent.isEmpty) {
      _showError('No files processed for diff preview.');
      return;
    }

    final TextEditingController previewController = TextEditingController(
      text: previewContent.join('\n'),
    );

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Diff Preview'),
        content: SizedBox(
          width: ResponsiveValue<double>(
            context,
            defaultValue: 800,
            conditionalValues: [
              Condition.equals(
                name: MOBILE,
                value: MediaQuery.of(context).size.width * 0.9,
              ),
              Condition.equals(name: TABLET, value: 700),
              Condition.largerThan(name: TABLET, value: 900),
            ],
          ).value,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasErrors)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      'Some files could not be found or processed. Review the preview carefully!',
                      style: TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.6,
                  ),
                  width: double.maxFinite,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                    color: Colors.grey[800],
                  ),
                  child: TextField(
                    controller: previewController,
                    readOnly: true,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: Colors.white70,
                    ),
                    decoration: const InputDecoration.collapsed(
                      hintText: 'No diff preview',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              bool allApplied = true;
              for (final filePath in fileNewContents.keys) {
                try {
                  final file = File(filePath);
                  await file.writeAsString(
                    fileNewContents[filePath]!.join('\n'),
                  );
                  // Update in-memory foundFiles if it exists in the current search results
                  int index = _foundFiles.indexWhere(
                    (f) => f.filePath == filePath,
                  );
                  if (index != -1) {
                    setState(() {
                      _foundFiles[index].content = fileNewContents[filePath]!
                          .join('\n');
                    });
                  }
                } catch (e) {
                  allApplied = false;
                  _showError('Failed to apply diff to $filePath: $e');
                  sendTelegramLog('Apply diff error for $filePath: $e');
                }
              }
              if (allApplied) {
                _showSuccess('All selected diffs applied successfully!');
              }
              _parsedDiffs = {}; // Clear parsed diffs after application
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Apply Changes'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportSelectedFiles({required bool includeDiffHeader}) async {
    final selectedFiles = _displayedFiles
        .where((file) => file.isSelected)
        .toList();

    if (selectedFiles.isEmpty) {
      _showError('No files selected for export');
      return;
    }

    try {
      StringBuffer buffer = StringBuffer();

      buffer.writeln('--- Selected Files Export ---');
      buffer.writeln('Export Date: ${DateTime.now().toIso8601String()}\n');

      for (final fileContent in selectedFiles) {
        if (includeDiffHeader) {
          buffer.writeln(_formatContentAsGitHubDiff(fileContent));
        } else {
          buffer.writeln(
            '### File: ${fileContent.fileName} (${fileContent.filePath})',
          );
          buffer.writeln(
            '```${fileContent.fileExtension.replaceFirst('.', '')}',
          ); // Markdown code block
          buffer.writeln(fileContent.content);
          buffer.writeln('```');
        }
        buffer.writeln('\n--- End File: ${fileContent.fileName} ---\n');
      }

      if (Platform.isAndroid) {
        // For Android, save to temp directory and share the file
        final tempDir = await getTemporaryDirectory();
        final fileName = includeDiffHeader
            ? 'selected_files_diff_export.txt'
            : 'selected_files_export.txt';
        final outputPath = '${tempDir.path}/$fileName';
        final File outputFile = File(outputPath);
        await outputFile.writeAsString(buffer.toString());
        // ignore: deprecated_member_use
        await Share.shareXFiles([
          XFile(outputPath),
        ], text: 'Exported selected files');
        _showSuccess('Selected files exported and shared');
      } else {
        // For other platforms, use FilePicker as before
        String? outputPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Exported Files As',
          fileName: includeDiffHeader
              ? 'selected_files_diff_export.txt'
              : 'selected_files_export.txt',
          type: FileType.custom,
          allowedExtensions: ['txt', 'md'],
        );

        if (outputPath == null) {
          return;
        }

        final File outputFile = File(outputPath);
        await outputFile.writeAsString(buffer.toString());
        _showSuccess('Selected files exported to ${outputFile.path}');
      }
    } catch (e) {
      _showError('Error exporting selected results: $e');
    }
  }
  // ... (Keep _showFileContent, _generateFileTree, _showFileTree, _formatContentWithLineNumbers, etc.) ...

  // --- UI Construction ---

  @override
  Widget build(BuildContext context) {
    bool isMobile = ResponsiveBreakpoints.of(context).smallerOrEqualTo(TABLET);

    return Scaffold(
      appBar: AppBar(
        title: const Text('File Search & Diff App'),
        actions: isMobile ? [_buildMobileCollapseButton()] : null,
           leading: IconButton(
             icon: const Icon(Icons.arrow_back),
             onPressed: () {
                                   Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GitLoaderApp(),
          ),
        );// This pops the screen and goes back

             },
           ),
      ),
      body: ResponsiveRowColumn(
        layout: ResponsiveBreakpoints.of(context).largerThan(MOBILE)
            ? ResponsiveRowColumnType.ROW
            : ResponsiveRowColumnType.COLUMN,
        rowSpacing: 16,
        columnSpacing: 16,
        rowMainAxisAlignment: MainAxisAlignment.start,
        columnCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ResponsiveRowColumnItem(
            rowFlex: 2,
            columnFlex: 1,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: _buildControlsSection(),
            ),
          ),
          ResponsiveRowColumnItem(
            rowFlex: 3,
            columnFlex: 1,
            child: isMobile
                ? AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: _isResultsPaneExpanded
                        ? MediaQuery.of(context).size.height * 0.5
                        : 50,
                    child: _isResultsPaneExpanded
                        ? _buildResultList()
                        : _buildCollapsedResultHeader(),
                  )
                : _buildResultList(),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileCollapseButton() {
    return IconButton(
      icon: Icon(
        _isResultsPaneExpanded ? Icons.chevron_right : Icons.chevron_left,
      ),
      onPressed: () {
        setState(() {
          _isResultsPaneExpanded = !_isResultsPaneExpanded;
        });
      },
      tooltip: _isResultsPaneExpanded ? 'Collapse results' : 'Expand results',
    );
  }

  Widget _buildCollapsedResultHeader() {
    return InkWell(
      onTap: () {
        setState(() {
          _isResultsPaneExpanded = true;
        });
      },
      child: Card(
        margin: const EdgeInsets.all(8.0),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Found Files: ${_displayedFiles.length}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Icon(Icons.expand_less),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the main control section including directory selection, search filters, and diff input.
  Widget _buildControlsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton(
          onPressed: _selectDirectory,
          child: const Text('Select Directory'),
        ),
        const SizedBox(height: 8),
        Text(
          selectedPath != null
              ? 'Selected: ${selectedPath!}'
              : 'No directory selected',
          style: TextStyle(
            color: selectedPath != null ? Colors.greenAccent : Colors.grey,
            fontStyle: selectedPath != null
                ? FontStyle.normal
                : FontStyle.italic,
          ),
        ),
        const SizedBox(height: 20),
        _buildSearchFilters(),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: isSearching ? _cancelSearch : _startSearch,
          style: ElevatedButton.styleFrom(
            backgroundColor: isSearching ? Colors.orange : Colors.blueAccent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: isSearching
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                    SizedBox(width: 8),
                    Text('Searching... Tap to Cancel'),
                  ],
                )
              : const Text('Start Search'),
        ),
        const SizedBox(height: 10),
        const Divider(),
        _buildPostSearchContentFilter(), // New content filter
        const Divider(),
        _buildDiffSection(),
        const Divider(),
        const SizedBox(height: 20),
        _buildActionButtons(),
      ],
    );
  }

  /// Builds the search filter expansion tile.
  Widget _buildSearchFilters() {
    return ExpansionTile(
      title: const Text('File & Path Search Filters'),
      initiallyExpanded: false,
      leading: const Icon(Icons.filter_alt),
      childrenPadding: const EdgeInsets.symmetric(
        horizontal: 16.0,
        vertical: 8.0,
      ),
      children: [
        TextField(
          controller: _fileTypeController,
          decoration: const InputDecoration(
            labelText: 'File Extensions (e.g., .dart,.json)',
            hintText: '.dart,.java,.xml',
          ),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('Filter by Directory/Path'),
          value: _isPathPatternFilteringEnabled,
          onChanged: (value) =>
              setState(() => _isPathPatternFilteringEnabled = value),
          contentPadding: EdgeInsets.zero,
        ),
        if (_isPathPatternFilteringEnabled) ...[
          TextField(
            controller: _includePathPatternController,
            decoration: const InputDecoration(
              labelText: 'Include Paths (e.g., /src/*, *controller/)',
              hintText: '/lib/src/*, *data/, /bin/',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _excludePathPatternController,
            decoration: const InputDecoration(
              labelText: 'Exclude Paths (e.g., /build/*, *node_modules/)',
              hintText: '/build/*, *node_modules/, *.git',
            ),
          ),
          const SizedBox(height: 16),
        ],
        SwitchListTile(
          title: const Text('Filter by File Name Pattern'),
          value: _isFileNamePatternFilteringEnabled,
          onChanged: (value) =>
              setState(() => _isFileNamePatternFilteringEnabled = value),
          contentPadding: EdgeInsets.zero,
        ),
        if (_isFileNamePatternFilteringEnabled) ...[
          TextField(
            controller: _includeFileNamePatternController,
            decoration: const InputDecoration(
              labelText: 'Include File Names (e.g., *-provider.go, *model*)',
              hintText: '*-repository.dart, *settings.json',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _excludeFileNamePatternController,
            decoration: const InputDecoration(
              labelText: 'Exclude File Names (e.g., *test.dart, *.tmp)',
              hintText: '*_test.dart, *.log, temporary*',
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  /// New: Builds the post-search content filter section.
  Widget _buildPostSearchContentFilter() {
    return ExpansionTile(
      title: const Text('Post-Search Content Filter'),
      initiallyExpanded: false,
      leading: const Icon(Icons.search),
      childrenPadding: const EdgeInsets.symmetric(
        horizontal: 16.0,
        vertical: 8.0,
      ),
      children: [
        SwitchListTile(
          title: const Text('Enable Content Filtering'),
          value: _isPostSearchContentFilteringEnabled,
          onChanged: (value) {
            setState(() {
              _isPostSearchContentFilteringEnabled = value;
              // If disabled, reset displayed files to all found files
              if (!value) {
                _displayedFiles = List.from(_foundFiles);
              } else {
                // If re-enabled, apply filter immediately if text is present
                _contentFilterDebouncer.onChanged;
              }
            });
          },
          contentPadding: EdgeInsets.zero,
        ),
        if (_isPostSearchContentFilteringEnabled) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _postSearchContentFilterController,
            decoration: const InputDecoration(
              labelText: 'Search content (fuzzy/regex)',
              hintText: 'e.g., class MyWidget, (await|Future)<String>',
            ),
            // Auto-adjusting input is typically done via `minLines` and `maxLines`
            // with `expands: false` and a `SingleChildScrollView`.
            // For a single line that grows, setting `minLines: 1, maxLines: null` and wrapping in IntrinsicHeight/Width
            // or a fixed max height can work.
            // For simplicity, a standard TextField with maxLines is common for "search input" that grows.
            maxLines: null, // Allow it to grow
            minLines: 1,
            keyboardType: TextInputType.multiline,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ChoiceChip(
                label: const Text('Include'),
                selected: _isPostSearchContentInclude,
                onSelected: (selected) {
                  setState(() {
                    _isPostSearchContentInclude = true;
                    _contentFilterDebouncer.onChanged;
                  });
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Exclude'),
                selected: !_isPostSearchContentInclude,
                onSelected: (selected) {
                  setState(() {
                    _isPostSearchContentInclude = false;
                    _contentFilterDebouncer.onChanged;
                  });
                },
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// Builds the diff application section.
  Widget _buildDiffSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Apply GitHub-style Diff:',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _diffInputController,
          maxLines: 5,
          keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(
            labelText: 'Paste Diff Content Here',
            hintText:
                '--- a/file.txt\n+++ b/file.txt\n@@ -1,3 +1,4 @@\n-old\n+new\n context',
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          alignment: WrapAlignment.center,
          children: [
            ElevatedButton(
              onPressed: _loadDiffFromFile,
              child: const Text('Load Diff from File'),
            ),
            ElevatedButton(
              onPressed: _loadDiffFromTextInput,
              child: const Text('Parse Diff from Input'),
            ),
            ElevatedButton(
              onPressed: _parsedDiffs.isNotEmpty
                  ? _showDiffPreviewAndApply
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purpleAccent,
              ),
              child: const Text('Preview & Apply Diff'),
            ),
          ],
        ),
      ],
    );
  }

  /// Builds the action buttons like select all, export, and file tree.
  Widget _buildActionButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'File Actions:',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          alignment: WrapAlignment.center,
          children: [
            ElevatedButton(
              onPressed: _displayedFiles.isNotEmpty ? _selectAllFiles : null,
              child: const Text('Select All'),
            ),
            ElevatedButton(
              onPressed: _isAnyFileSelected ? _deselectAllFiles : null,
              child: const Text('Deselect All'),
            ),
            ElevatedButton(
              onPressed: _isAnyFileSelected ? _deleteSelectedFiles : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              child: const Text('Delete Selected'),
            ),
            ElevatedButton(
              onPressed: _isAnyFileSelected
                  ? () => _exportSelectedFiles(includeDiffHeader: true)
                  : null,
              child: const Text('Export Selected (Diff Style)'),
            ),
            ElevatedButton(
              onPressed: _isAnyFileSelected
                  ? () => _exportSelectedFiles(includeDiffHeader: false)
                  : null,
              child: const Text('Export Selected (Raw)'),
            ),
            ElevatedButton(
              onPressed: selectedPath != null ? _showFileTree : null,
              child: const Text('Generate File Tree'),
            ),
          ],
        ),
      ],
    );
  }

  void _selectAllFiles() {
    setState(() {
      for (var file in _displayedFiles) {
        file.isSelected = true;
      }
      _isAnyFileSelected = true;
    });
  }

  void _deselectAllFiles() {
    setState(() {
      for (var file in _displayedFiles) {
        file.isSelected = false;
      }
      _isAnyFileSelected = false;
    });
  }

  void _deleteSelectedFiles() {
    setState(() {
      // Remove from both _foundFiles and _displayedFiles
      _foundFiles.removeWhere((file) => file.isSelected);
      _displayedFiles.removeWhere((file) => file.isSelected);
      _isAnyFileSelected = false;
      totalFilesFound = _foundFiles.length; // Update total count
    });
    _showSuccess('Selected files deleted from list.');
  }

  String _formatContentWithLineNumbers(String content) {
    final lines = content.split('\n');
    final buffer = StringBuffer();
    final int lineNumberPadding = lines.length.toString().length;

    for (int i = 0; i < lines.length; i++) {
      buffer.writeln(
        '${(i + 1).toString().padLeft(lineNumberPadding)}: ${lines[i]}',
      );
    }
    return buffer.toString();
  }

  Widget _buildResultList() {
    return FileResultList(
      displayedFiles: _displayedFiles,
      totalFilesFound: totalFilesFound,
      isSearching: isSearching,
      onFileTap: (file) => _showFileContent(file),
      onSelectionChanged: (file, isSelected) {
        setState(() {
          file.isSelected = isSelected ?? false;
          _updateSelectionState();
        });
      },
    );
  }

  Future<void> _showFileContent(FileContent fileContent) async {
    final TextEditingController contentController = TextEditingController(
      text: fileContent.content,
    );

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(fileContent.fileName),
        content: SizedBox(
          width: ResponsiveValue<double>(
            context,
            defaultValue: 400,
            conditionalValues: [
              Condition.equals(
                name: MOBILE,
                value: MediaQuery.of(context).size.width * 0.8,
              ),
              Condition.equals(name: TABLET, value: 600),
              Condition.largerThan(name: TABLET, value: 800),
            ],
          ).value,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Path: ${fileContent.filePath}'),
                const SizedBox(height: 8),
                Text('Extension: ${fileContent.fileExtension}'),
                const SizedBox(height: 16),
                const Text(
                  'File Content (Editable):',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.maxFinite,
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.3,
                  ),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: TextField(
                    controller: contentController,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                    decoration: const InputDecoration.collapsed(
                      hintText: 'No content to display',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Content with Line Numbers (Read-Only):',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.maxFinite,
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.3,
                  ),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                    color: Colors.grey[800], // Darker background for read-only
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      _formatContentWithLineNumbers(fileContent.content),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: _formatContentAsGitHubDiff(fileContent)),
              );
              _showSuccess('File content (GitHub diff style) copied!');
            },
            child: const Text('Copy Diff Style'),
          ),
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: fileContent.content));
              _showSuccess('File content copied!');
            },
            child: const Text('Copy Raw Content'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final File file = File(fileContent.filePath);
                await file.writeAsString(contentController.text);
                setState(() {
                  fileContent.content = contentController.text;
                });
                _showSuccess(
                  'File ${fileContent.fileName} saved successfully!',
                );
                if (mounted) Navigator.pop(context);
              } catch (e) {
                _showError('Error saving file: $e');
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<String> _generateFileTree(
    String directoryPath, [
    String prefix = '',
    String? rootPath,
    AiFileFilter? filter,
  ]) async {
    final buffer = StringBuffer();
    final directory = Directory(directoryPath);

    if (!await directory.exists()) {
      return '';
    }

    final AiFileFilter activeFilter = filter ?? await AiFileFilter.load();
    final String basePath = rootPath ?? directoryPath;
    final List<FileSystemEntity> entities = [];
    for (final entity in directory.listSync(recursive: false)) {
      final String relative = path_pkg
          .relative(entity.path, from: basePath)
          .replaceAll(r'\', '/');
      if (activeFilter.isHidden(relative)) continue;
      entities.add(entity);
    }
    entities.sort(
      (a, b) => path_pkg.basename(a.path).compareTo(path_pkg.basename(b.path)),
    );

    for (int i = 0; i < entities.length; i++) {
      final entity = entities[i];
      final isLast = i == entities.length - 1;
      final newPrefix = isLast ? '└── ' : '├── ';
      final nextPrefix = isLast ? '    ' : '│   ';

      buffer.writeln('$prefix$newPrefix${path_pkg.basename(entity.path)}');

      if (entity is Directory) {
        buffer.write(
          await _generateFileTree(
            entity.path,
            prefix + nextPrefix,
            basePath,
            activeFilter,
          ),
        );
      }
    }
    return buffer.toString();
  }

  Future<void> _showFileTree() async {
    if (selectedPath == null) {
      _showError('Please select a directory first to generate a file tree.');
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Generating file tree... This might take a moment.'),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      final String tree = await _generateFileTree(selectedPath!);
      final TextEditingController treeController = TextEditingController(
        text: tree,
      );

      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Generated File Tree'),
          content: SizedBox(
            width: ResponsiveValue<double>(
              context,
              defaultValue: 600,
              conditionalValues: [
                Condition.equals(
                  name: MOBILE,
                  value: MediaQuery.of(context).size.width * 0.9,
                ),
                Condition.equals(name: TABLET, value: 700),
                Condition.largerThan(name: TABLET, value: 800),
              ],
            ).value,
            child: SingleChildScrollView(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.6,
                ),
                width: double.maxFinite,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                  color: Colors.grey[800],
                ),
                child: TextField(
                  controller: treeController,
                  readOnly: true,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: Colors.white70,
                  ),
                  decoration: const InputDecoration.collapsed(
                    hintText: 'No tree generated',
                  ),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: treeController.text),
                );
                _showSuccess('File tree copied to clipboard!');
              },
              child: const Text('Copy to Clipboard'),
            ),
            TextButton(
              onPressed: () async {
                String? outputPath = await FilePicker.platform.saveFile(
                  dialogTitle: 'Save File Tree As',
                  fileName: 'file_tree.txt',
                  type: FileType.custom,
                  allowedExtensions: ['txt'],
                );

                if (outputPath != null) {
                  try {
                    final File outputFile = File(outputPath);
                    await outputFile.writeAsString(treeController.text);
                    _showSuccess('File tree saved to ${outputFile.path}');
                  } catch (e) {
                    _showError('Error saving file tree: $e');
                  }
                }
              },
              child: const Text('Save'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showError('Error generating file tree: $e');
      sendTelegramLog('File tree generation error: $e');
    }
  }

  // --- Disposal ---
  @override
  void dispose() {
    _fileTypeController.dispose();
    _diffInputController.dispose();
    _includePathPatternController.dispose();
    _excludePathPatternController.dispose();
    _includeFileNamePatternController.dispose();
    _excludeFileNamePatternController.dispose();
    _postSearchContentFilterController.removeListener(
      _onContentFilterTextChanged,
    );
    _postSearchContentFilterController.dispose();
    _contentFilterDebouncer.cancel();
    // Ensure worker manager is cleaned up if necessary, depending on its lifecycle management.
    super.dispose();
  }
}
