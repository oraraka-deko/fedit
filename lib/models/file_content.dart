// lib/models/file_content.dart

class FileContent {
  final String fileName;
  final String filePath;
  String content; // Made mutable for editing
  final String fileExtension;
  bool isSelected; // Added for selection

  FileContent({
    required this.fileName,
    required this.filePath,
    required this.content,
    required this.fileExtension,
    this.isSelected = false,
  });

  @override
  String toString() {
    return 'FileContent{fileName: $fileName, filePath: $filePath, contentLength: ${content.length}, fileExtension: $fileExtension, isSelected: $isSelected}';
  }
}