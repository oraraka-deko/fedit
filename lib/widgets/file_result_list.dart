// lib/widgets/file_result_list.dart

import 'package:flutter/material.dart';
import '../models/file_content.dart';

class FileResultList extends StatelessWidget {
  final List<FileContent> displayedFiles;
  final int totalFilesFound;
  final bool isSearching;
  final Function(FileContent file) onFileTap;
  final Function(FileContent file, bool? isSelected) onSelectionChanged;

  const FileResultList({
    super.key,
    required this.displayedFiles,
    required this.totalFilesFound,
    required this.isSearching,
    required this.onFileTap,
    required this.onSelectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            'Displayed Files: ${displayedFiles.length} (Total Found: $totalFilesFound)',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: displayedFiles.isEmpty
              ? Center(
                  child: Text(
                    isSearching
                        ? 'Searching...'
                        : 'No files found yet or no files match current content filters. Select a directory and start search.',
                    style: const TextStyle(color: Colors.grey, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  itemCount: displayedFiles.length,
                  itemBuilder: (context, index) {
                    final file = displayedFiles[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: ListTile(
                        leading: Checkbox(
                          value: file.isSelected,
                          onChanged: (bool? newValue) =>
                              onSelectionChanged(file, newValue),
                        ),
                        title: Text(
                          file.fileName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          file.filePath,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                        trailing: Text(
                          '${file.content.length} chars',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white54,
                          ),
                        ),
                        onTap: () => onFileTap(file),
                        tileColor: file.isSelected
                            ? Colors.blue.withValues(alpha: 0.2)
                            : null,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
