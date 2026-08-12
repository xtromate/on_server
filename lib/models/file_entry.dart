/// One entry (file or directory) returned by GET /api/files.
class FileEntry {
  final String name;
  final String path;
  final String type; // "file" | "dir"
  final int size;
  final DateTime? modifiedAt;

  const FileEntry({
    required this.name,
    required this.path,
    required this.type,
    required this.size,
    this.modifiedAt,
  });

  factory FileEntry.fromJson(Map<String, dynamic> json) {
    return FileEntry(
      name: json['name'] as String,
      path: json['path'] as String,
      type: json['type'] as String? ?? 'file',
      size: (json['size'] as num?)?.toInt() ?? 0,
      modifiedAt: json['modifiedAt'] != null ? DateTime.tryParse(json['modifiedAt'].toString()) : null,
    );
  }

  bool get isDir => type == 'dir';
}
