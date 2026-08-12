import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/connection_settings.dart';
import '../core/format.dart';
import '../models/file_entry.dart';

/// NAS browser: breadcrumb navigation over GET /api/files, upload (via
/// file_picker — see deviation note in the build report), download (saved
/// through file_picker's save-file dialog), delete, mkdir.
class FilesScreen extends StatefulWidget {
  final bool active;
  const FilesScreen({super.key, required this.active});

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  String _path = '/';
  List<FileEntry> _entries = [];
  bool _loading = true;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<String> get _crumbs {
    final parts = _path.split('/').where((p) => p.isNotEmpty).toList();
    return parts;
  }

  String _pathUpTo(int index) {
    final parts = _crumbs.sublist(0, index + 1);
    return '/${parts.join('/')}';
  }

  Future<void> _load() async {
    final settings = context.read<ConnectionSettings>();
    if (!settings.isConfigured) return;
    final client = ApiClient(settings);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await client.listFiles(_path);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    } finally {
      client.dispose();
    }
  }

  void _open(FileEntry entry) {
    if (entry.isDir) {
      setState(() => _path = entry.path);
      _load();
    }
  }

  Future<void> _mkdir() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Folder name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(controller.text.trim()), child: const Text('Create')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    if (!mounted) return;
    final settings = context.read<ConnectionSettings>();
    final client = ApiClient(settings);
    setState(() => _busy = true);
    try {
      final newPath = _path.endsWith('/') ? '$_path$name' : '$_path/$name';
      await client.mkdir(newPath);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      client.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not read the selected file')));
      }
      return;
    }
    if (!mounted) return;
    final settings = context.read<ConnectionSettings>();
    final client = ApiClient(settings);
    setState(() => _busy = true);
    try {
      await client.uploadFile(_path, file.name, file.bytes!);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Uploaded ${file.name}')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      client.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download(FileEntry entry) async {
    final settings = context.read<ConnectionSettings>();
    final client = ApiClient(settings);
    setState(() => _busy = true);
    try {
      final bytes = await client.downloadFile(entry.path);
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save ${entry.name}',
        fileName: entry.name,
        bytes: Uint8List.fromList(bytes),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(savedPath != null ? 'Saved to $savedPath' : 'Download cancelled')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      client.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(FileEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${entry.name}?'),
        content: Text(entry.isDir ? 'This deletes the folder and its contents.' : 'This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    final settings = context.read<ConnectionSettings>();
    final client = ApiClient(settings);
    setState(() => _busy = true);
    try {
      await client.deleteFile(entry.path);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      client.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        InkWell(
                          onTap: () {
                            setState(() => _path = '/');
                            _load();
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(Icons.home, size: 18),
                          ),
                        ),
                        for (var i = 0; i < _crumbs.length; i++) ...[
                          const Icon(Icons.chevron_right, size: 16),
                          InkWell(
                            onTap: () {
                              setState(() => _path = _pathUpTo(i));
                              _load();
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Text(_crumbs[i]),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                IconButton(icon: const Icon(Icons.create_new_folder_outlined), tooltip: 'New folder', onPressed: _busy ? null : _mkdir),
                IconButton(icon: const Icon(Icons.upload_file), tooltip: 'Upload', onPressed: _busy ? null : _upload),
              ],
            ),
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              FilledButton(onPressed: _load, child: const Text('Retry')),
                            ],
                          ),
                        ),
                      )
                    : _entries.isEmpty
                        ? const Center(child: Text('This folder is empty'))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              itemCount: _entries.length,
                              itemBuilder: (context, i) {
                                final entry = _entries[i];
                                return ListTile(
                                  leading: Icon(entry.isDir ? Icons.folder : Icons.insert_drive_file),
                                  title: Text(entry.name),
                                  subtitle: entry.isDir
                                      ? null
                                      : Text('${Fmt.bytesStr(entry.size)} · ${Fmt.dateTime(entry.modifiedAt)}'),
                                  onTap: () => _open(entry),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (!entry.isDir)
                                        IconButton(
                                          icon: const Icon(Icons.download),
                                          tooltip: 'Download',
                                          onPressed: _busy ? null : () => _download(entry),
                                        ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                                        tooltip: 'Delete',
                                        onPressed: _busy ? null : () => _delete(entry),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
