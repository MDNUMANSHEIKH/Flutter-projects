import 'dart:io';
import 'dart:typed_data';

import 'package:dart_appwrite/dart_appwrite.dart';
import 'package:dart_appwrite/models.dart' as appwrite_models;
import 'package:external_path/external_path.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pstublc/config/appwrite_storage.dart';
import 'package:pstublc/services/api_service.dart';

class CourseMaterialsSection extends StatefulWidget {
  final int courseId;
  final String courseScope;
  final String userEmail;
  final String userRole;
  final bool canDeleteAny;
  final bool canUpload;
  final String courseName;

  const CourseMaterialsSection({
    super.key,
    required this.courseId,
    required this.courseScope,
    required this.userEmail,
    required this.userRole,
    this.canDeleteAny = false,
    this.canUpload = true,
    this.courseName = '',
  });

  @override
  State<CourseMaterialsSection> createState() => _CourseMaterialsSectionState();
}

class _SelectedFile {
  final String? path;
  final Uint8List? bytes;
  final String name;
  final int sizeBytes;

  _SelectedFile({
    this.path,
    this.bytes,
    required this.name,
    required this.sizeBytes,
  });

  String get sizeMB => (sizeBytes / (1024 * 1024)).toStringAsFixed(2);
  bool get isValid => sizeBytes <= 50 * 1024 * 1024;
}

class _MaterialInfo {
  final appwrite_models.File file;
  final String originalName;
  final String uploaderEmail;
  final String uploaderRole;
  final DateTime? uploadedAt;
  final String rawName;

  _MaterialInfo({
    required this.file,
    required this.originalName,
    required this.uploaderEmail,
    required this.uploaderRole,
    required this.uploadedAt,
    required this.rawName,
  });

  String get id => file.$id;
  int get size => file.sizeOriginal;
}

class _CourseMaterialsSectionState extends State<CourseMaterialsSection> {
  bool _loadingMaterials = true;
  bool _uploading = false;
  bool _selectionMode = false;
  List<appwrite_models.File> _materials = [];
  final Set<String> _selectedFileIds = <String>{};

  String _normalizeScope(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]+'), '_');
  }

  String get _primaryCourseToken {
    if (widget.courseId > 0) return widget.courseId.toString();
    return _normalizeScope(widget.courseScope);
  }

  List<String> get _coursePrefixes {
    final tokens = <String>{
      _primaryCourseToken,
      _normalizeScope(widget.courseScope),
    }..removeWhere((t) => t.isEmpty);
    return tokens.map((t) => 'course_${t}__').toList();
  }

  String get _uploadCoursePrefix => 'course_${_primaryCourseToken}__';

  @override
  void initState() {
    super.initState();
    _loadMaterials();
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _sanitize(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9@._-]+'), '_');
  }

  String _uploadStamp() {
    final now = DateTime.now().toLocal();
    final year = now.year.toString();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    final second = now.second.toString().padLeft(2, '0');
    return '$year$month$day$hour$minute$second';
  }

  String _safePathName(String value) {
    return value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  _MaterialInfo _parseMaterial(appwrite_models.File file) {
    final rawName = file.name;
    String remainder = rawName;
    for (final prefix in _coursePrefixes) {
      if (rawName.startsWith(prefix)) {
        remainder = rawName.substring(prefix.length);
        break;
      }
    }

    String role = '';
    String email = '';
    DateTime? uploadedAt;
    String originalName = remainder;

    final parts = remainder.split('__');
    if (parts.length >= 4) {
      role = parts[0];
      email = parts[1];
      final stamp = parts[2];
      originalName = parts.sublist(3).join('__');
      uploadedAt = _parseStamp(stamp);
    } else if (parts.length >= 2 && RegExp(r'^\d{14}$').hasMatch(parts[0])) {
      final stamp = parts[0];
      originalName = parts.sublist(1).join('__');
      uploadedAt = _parseStamp(stamp);
    } else {
      final lower = remainder.toLowerCase();
      if (lower.startsWith('teacher_')) {
        role = 'teacher';
        email = remainder.substring('teacher_'.length);
      } else if (lower.startsWith('student_')) {
        role = 'student';
        email = remainder.substring('student_'.length);
      }
    }

    uploadedAt ??= DateTime.tryParse(file.$createdAt)?.toLocal();
    return _MaterialInfo(
      file: file,
      originalName: originalName,
      uploaderEmail: email,
      uploaderRole: role,
      uploadedAt: uploadedAt,
      rawName: rawName,
    );
  }

  DateTime? _parseStamp(String stamp) {
    if (!RegExp(r'^\d{14}$').hasMatch(stamp)) return null;
    try {
      return DateTime(
        int.parse(stamp.substring(0, 4)),
        int.parse(stamp.substring(4, 6)),
        int.parse(stamp.substring(6, 8)),
        int.parse(stamp.substring(8, 10)),
        int.parse(stamp.substring(10, 12)),
        int.parse(stamp.substring(12, 14)),
      ).toLocal();
    } catch (_) {
      return null;
    }
  }

  String _fileId(appwrite_models.File file) => file.$id;
  String _fileName(appwrite_models.File file) => file.name;

  Future<void> _loadMaterials() async {
    setState(() => _loadingMaterials = true);
    try {
      final result = await appwriteStorage.listFiles(
        bucketId: materialsBucketId,
        queries: [
          Query.limit(500),
        ],
      );
      final rows = result.files
          .where((f) => _coursePrefixes.any((prefix) => _fileName(f).startsWith(prefix)))
          .toList()
        ..sort((a, b) => b.$createdAt.compareTo(a.$createdAt));
      
      if (!mounted) return;
      setState(() => _materials = rows);
    } catch (e) {
      _showMsg('Failed to load materials: $e');
    } finally {
      if (mounted) {
        setState(() => _loadingMaterials = false);
      }
    }
  }

  Future<List<_SelectedFile>> _pickMultipleFiles() async {
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: kIsWeb,
      type: FileType.any,
    );
    if (picked == null || picked.files.isEmpty) return [];

    final selected = <_SelectedFile>[];
    for (final file in picked.files) {
      String? safePath;
      try {
        safePath = file.path;
      } catch (_) {
        safePath = null;
      }
      if (safePath == null && file.bytes == null) continue;
      selected.add(
        _SelectedFile(
          path: safePath,
          bytes: file.bytes,
          name: file.name,
          sizeBytes: file.size,
        ),
      );
    }
    return selected;
  }

  Future<void> _showUploadDialog() async {
    List<_SelectedFile> selectedFiles = [];
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final validCount = selectedFiles.where((f) => f.isValid).length;
          final invalidCount = selectedFiles.length - validCount;
          final canSubmit = validCount > 0 && !_uploading;
          return AlertDialog(
            title: const Text('Upload File'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text('Select files (Max 50 MB each)'),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        final picked = await _pickMultipleFiles();
                        if (picked.isEmpty) return;
                        setDialogState(() {
                          selectedFiles = [...selectedFiles, ...picked];
                        });
                        if (picked.any((f) => !f.isValid)) {
                          _showMsg('File size must be less than 50 MB');
                        }
                      } catch (e) {
                        _showMsg('Error selecting files: $e');
                      }
                    },
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('Choose File'),
                  ),
                  const SizedBox(height: 14),
                  if (selectedFiles.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Theme.of(context).dividerColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Selected Files (${selectedFiles.length}):',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 220),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: selectedFiles.length,
                              itemBuilder: (context, index) {
                                final file = selectedFiles[index];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              file.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 2),
                                            Text('Size: ${_formatSize(file.sizeBytes)}'),
                                            if (!file.isValid)
                                              const Text(
                                                'File size must be less than 50 MB',
                                                style: TextStyle(color: Colors.red),
                                              ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close, color: Colors.red),
                                        onPressed: () => setDialogState(() {
                                          selectedFiles.removeAt(index);
                                        }),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                          if (invalidCount > 0)
                            Text(
                              '$invalidCount file(s) exceed 50 MB (will be skipped)',
                              style: const TextStyle(color: Colors.red),
                            ),
                          if (validCount > 0)
                            Text('$validCount valid file(s) ready to upload'),
                        ],
                      ),
                    )
                  else
                    const SizedBox(
                      height: 44,
                      child: Center(child: Text('No file selected')),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: !canSubmit
                    ? null
                    : () async {
                        final uploadList = List<_SelectedFile>.from(selectedFiles);
                        Navigator.pop(dialogContext);
                        await _uploadFiles(uploadList);
                      },
                child: const Text('Submit'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _uploadFiles(List<_SelectedFile> files) async {
    if (_uploading || files.isEmpty || !widget.canUpload) return;
    setState(() => _uploading = true);

    int successCount = 0;
    int skippedCount = 0;
    final notifyFilenames = <String>[];

    for (final file in files) {
      if (!file.isValid) {
        skippedCount++;
        continue;
      }
      try {
        final safeName = _safePathName(file.name);
        final stamp = _uploadStamp();
        final encodedEmail = _sanitize(widget.userEmail);
        final encodedRole = widget.userRole.toLowerCase().trim();
        final finalName = '${_uploadCoursePrefix}${encodedRole}__${encodedEmail}__${stamp}__${safeName}';

        InputFile inputFile;
        if (file.path != null) {
          inputFile = InputFile.fromPath(path: file.path!, filename: finalName);
        } else if (file.bytes != null) {
          inputFile = InputFile.fromBytes(bytes: file.bytes!, filename: finalName);
        } else {
          _showMsg('Skipped ${file.name}: no file data available');
          continue;
        }

        await appwriteStorage.createFile(
          bucketId: materialsBucketId,
          fileId: ID.unique(),
          file: inputFile,
        );
        successCount++;
        notifyFilenames.add(file.name);
      } catch (e) {
        _showMsg('Failed to upload ${file.name}: $e');
      }
    }

    if (!mounted) return;
    setState(() => _uploading = false);

    if (successCount > 0) {
      _showMsg('$successCount file(s) uploaded successfully');
      await _loadMaterials();
      
      final courseDisplay = widget.courseName.isNotEmpty 
          ? ' in ${widget.courseName}' 
          : '';
      
      await ApiService().notifyCourseStudents(
        courseId: widget.courseId,
        title: 'New Study Material$courseDisplay',
        message: notifyFilenames.length == 1
            ? 'A new material (${notifyFilenames.first}) has been uploaded$courseDisplay.'
            : '${notifyFilenames.length} new materials have been uploaded$courseDisplay.',
        type: 'material',
        excludeEmail: widget.userEmail,
        actorEmail: widget.userEmail,
        actorRole: widget.userRole,
      );
    }
    if (skippedCount > 0) {
      _showMsg('$skippedCount file(s) skipped (over 50 MB)');
    }
  }

  bool _canDeleteInfo(_MaterialInfo info) {
    if (widget.canDeleteAny) return true;
    if (widget.userRole.toLowerCase() == 'teacher') return true;
    return info.uploaderEmail.toLowerCase() == widget.userEmail.toLowerCase() &&
        info.uploaderRole.toLowerCase() == widget.userRole.toLowerCase();
  }

  bool get _canDeleteSelected {
    if (_selectedFileIds.isEmpty) return false;
    final selectedInfos = _materials
        .map(_parseMaterial)
        .where((info) => _selectedFileIds.contains(info.id))
        .toList();
    return selectedInfos.every(_canDeleteInfo);
  }

  void _enterSelectionMode(String fileId) {
    setState(() {
      _selectionMode = true;
      _selectedFileIds.add(fileId);
    });
  }

  void _toggleSelectedFile(String fileId) {
    setState(() {
      if (_selectedFileIds.contains(fileId)) {
        _selectedFileIds.remove(fileId);
      } else {
        _selectedFileIds.add(fileId);
      }
      if (_selectedFileIds.isEmpty) {
        _selectionMode = false;
      }
    });
  }

  void _cancelSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedFileIds.clear();
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedFileIds.length == _materials.length) {
        _selectedFileIds.clear();
        _selectionMode = false;
      } else {
        _selectedFileIds
          ..clear()
          ..addAll(_materials.map(_fileId).where((id) => id.isNotEmpty));
        _selectionMode = true;
      }
    });
  }

  Future<void> _downloadSelectedMaterials() async {
    if (_selectedFileIds.isEmpty) return;

    final orderedIds = _materials
        .where((m) => _selectedFileIds.contains(_fileId(m)))
        .map(_fileId)
        .toList();

    final progressText = ValueNotifier<String>('Starting download...');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Downloading'),
        content: ValueListenableBuilder<String>(
          valueListenable: progressText,
          builder: (_, value, __) => Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(value)),
            ],
          ),
        ),
      ),
    );

    int downloaded = 0;
    for (var index = 0; index < orderedIds.length; index++) {
      final fileId = orderedIds[index];
      try {
        final file = _materials.firstWhere((m) => _fileId(m) == fileId);
        final info = _parseMaterial(file);
        progressText.value =
            'Downloading ${index + 1}/${orderedIds.length}: ${info.originalName}';

        final bytes = await appwriteStorage.getFileDownload(
          bucketId: materialsBucketId,
          fileId: fileId,
        );

        final downloadName = info.originalName;
        if (kIsWeb) {
          await FileSaver.instance.saveFile(
            name: _baseFileName(downloadName),
            bytes: bytes,
            fileExtension: _fileExt(downloadName),
            mimeType: MimeType.other,
          );
        } else {
          final downloadsPath = await ExternalPath.getExternalStoragePublicDirectory(
            ExternalPath.DIRECTORY_DOWNLOAD,
          );
          final targetDir = Directory('$downloadsPath/PSTU_BLC_Materials');
          if (!await targetDir.exists()) {
            await targetDir.create(recursive: true);
          }
          final targetFile = File(
            '${targetDir.path}/${_safePathName(downloadName)}',
          );
          await targetFile.writeAsBytes(bytes, flush: true);
        }
        downloaded++;
      } catch (e) {
        _showMsg('Failed to download file: $e');
      }
    }

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    progressText.dispose();

    if (downloaded > 0) {
      _showMsg('$downloaded file(s) downloaded');
    }
  }

  Future<void> _downloadSingleMaterial(_MaterialInfo info) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Download Material'),
        content: Text('Do you want to download "${info.originalName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Download'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final progressText = ValueNotifier<String>('Starting download...');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Downloading'),
        content: ValueListenableBuilder<String>(
          valueListenable: progressText,
          builder: (_, value, __) => Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(value)),
            ],
          ),
        ),
      ),
    );

    try {
      progressText.value = 'Downloading: ${info.originalName}';
      final bytes = await appwriteStorage.getFileDownload(
        bucketId: materialsBucketId,
        fileId: info.id,
      );

      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: _baseFileName(info.originalName),
          bytes: bytes,
          fileExtension: _fileExt(info.originalName),
          mimeType: MimeType.other,
        );
      } else {
        final downloadsPath = await ExternalPath.getExternalStoragePublicDirectory(
          ExternalPath.DIRECTORY_DOWNLOAD,
        );
        final targetDir = Directory('$downloadsPath/PSTU_BLC_Materials');
        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }
        final targetFile = File(
          '${targetDir.path}/${_safePathName(info.originalName)}',
        );
        await targetFile.writeAsBytes(bytes, flush: true);
      }

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      progressText.dispose();
      _showMsg('Downloaded: ${info.originalName}');
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      progressText.dispose();
      _showMsg('Failed to download file: $e');
    }
  }

  Future<void> _deleteSelectedMaterials() async {
    if (_selectedFileIds.isEmpty) return;

    final infos = _materials.where((m) => _selectedFileIds.contains(_fileId(m))).map(_parseMaterial).toList();
    final unauthorized = infos.where((info) => !_canDeleteInfo(info)).toList();
    if (unauthorized.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete not allowed'),
          content: const Text('You can only delete your own uploaded files.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final count = _selectedFileIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Materials'),
        content: Text('Are you sure you want to delete $count file(s)?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    int deleted = 0;
    for (final fileId in _selectedFileIds) {
      try {
        await appwriteStorage.deleteFile(
          bucketId: materialsBucketId,
          fileId: fileId,
        );
        deleted++;
      } catch (e) {
        _showMsg('Failed to delete a file: $e');
      }
    }

    _cancelSelectionMode();
    if (deleted > 0) {
      _showMsg('$deleted file(s) deleted');
      await _loadMaterials();
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String _uploaderLabel(_MaterialInfo info) {
    final isCurrentUser = info.uploaderEmail.toLowerCase() == widget.userEmail.toLowerCase();
    if (widget.userRole.toLowerCase() == 'teacher') {
      if (isCurrentUser) {
        return 'Uploaded by you';
      }
      return info.uploaderEmail.isEmpty
          ? 'Uploaded by teacher'
          : 'Uploaded by ${info.uploaderEmail}';
    }
    if (info.uploaderRole.toLowerCase() == 'teacher') {
      return 'Uploaded by teacher';
    }
    if (isCurrentUser) {
      return 'Uploaded by You';
    }
    if (info.uploaderEmail.isNotEmpty) {
      return 'Uploaded by ${info.uploaderEmail}';
    }
    return 'Uploaded by a classmate';
  }

  String _formatUploadedTime(DateTime dt) {
    try {
      final year = dt.year.toString();
      final month = dt.month.toString().padLeft(2, '0');
      final day = dt.day.toString().padLeft(2, '0');
      final hour12 = (dt.hour % 12 == 0 ? 12 : dt.hour % 12)
          .toString()
          .padLeft(2, '0');
      final minute = dt.minute.toString().padLeft(2, '0');
      final second = dt.second.toString().padLeft(2, '0');
      final amPm = dt.hour >= 12 ? 'PM' : 'AM';
      return '$year-$month-$day $hour12:$minute:$second $amPm';
    } catch (_) {
      return dt.toIso8601String();
    }
  }

  String _baseFileName(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0) return name;
    return name.substring(0, dot);
  }

  String _fileExt(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return 'bin';
    return name.substring(dot + 1);
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingMaterials) {
      return const Center(child: CircularProgressIndicator());
    }

    final materialInfos = _materials.map(_parseMaterial).toList();

    return RefreshIndicator(
      onRefresh: _loadMaterials,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (widget.canUpload)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: SizedBox(
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: _uploading ? null : _showUploadDialog,
                  icon: const Icon(Icons.cloud_upload, size: 18),
                  label: const Text('Upload File'),
                  style: ElevatedButton.styleFrom(
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
            ),
          if (_materials.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 120),
              child: Center(child: Text('No materials uploaded yet.')),
            )
          else if (widget.userRole.toLowerCase() == 'student') ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Uploaded Files',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                    ),
                  ),
                  if (_selectionMode) ...[
                    Text(
                      '${_selectedFileIds.length} selected',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      onPressed: _materials.isEmpty ? null : _toggleSelectAll,
                      icon: Icon(
                        _selectedFileIds.length == _materials.length
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        color: _materials.isEmpty ? Colors.grey : null,
                      ),
                      tooltip: 'Select all',
                    ),
                    IconButton(
                      onPressed: _selectedFileIds.isEmpty
                          ? null
                          : _downloadSelectedMaterials,
                      icon: Icon(
                        Icons.download,
                        color: _selectedFileIds.isEmpty ? Colors.grey : null,
                      ),
                      tooltip: 'Download selected',
                    ),
                    IconButton(
                      onPressed: _canDeleteSelected
                          ? _deleteSelectedMaterials
                          : null,
                      icon: Icon(
                        Icons.delete,
                        color: _canDeleteSelected
                            ? Colors.red
                            : Colors.grey,
                      ),
                      tooltip: _canDeleteSelected
                          ? 'Delete selected'
                          : _selectedFileIds.isEmpty
                              ? 'No files selected'
                              : 'You can only delete your own files',
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _cancelSelectionMode,
                      tooltip: 'Cancel selection',
                    ),
                  ] else
                    TextButton(
                      onPressed: _materials.isEmpty
                          ? null
                          : () => setState(() => _selectionMode = true),
                      child: const Text('Select'),
                    ),
                ],
              ),
            ),
            _buildSection(
              title: 'Uploaded Files',
              emptyText: 'No files uploaded yet.',
              items: materialInfos,
              showUploaderLabel: true,
              showTitle: false,
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Uploaded Files',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                    ),
                  ),
                  if (_selectionMode) ...[
                    Text(
                      '${_selectedFileIds.length} selected',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      onPressed: _materials.isEmpty ? null : _toggleSelectAll,
                      icon: Icon(
                        _selectedFileIds.length == _materials.length
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        color: _materials.isEmpty ? Colors.grey : null,
                      ),
                      tooltip: 'Select all',
                    ),
                    IconButton(
                      onPressed: _selectedFileIds.isEmpty
                          ? null
                          : _downloadSelectedMaterials,
                      icon: Icon(
                        Icons.download,
                        color: _selectedFileIds.isEmpty ? Colors.grey : null,
                      ),
                      tooltip: 'Download selected',
                    ),
                    IconButton(
                      onPressed: _canDeleteSelected
                          ? _deleteSelectedMaterials
                          : null,
                      icon: Icon(
                        Icons.delete,
                        color: _canDeleteSelected
                            ? Colors.red
                            : Colors.grey,
                      ),
                      tooltip: _canDeleteSelected
                          ? 'Delete selected'
                          : _selectedFileIds.isEmpty
                              ? 'No files selected'
                              : 'You can only delete your own files',
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _cancelSelectionMode,
                      tooltip: 'Cancel selection',
                    ),
                  ] else
                    TextButton(
                      onPressed: _materials.isEmpty
                          ? null
                          : () => setState(() => _selectionMode = true),
                      child: const Text('Select'),
                    ),
                ],
              ),
            ),
            ...materialInfos.map((info) {
              final isSelected = _selectedFileIds.contains(info.id);
              return GestureDetector(
                onLongPress: () {
                  if (!_selectionMode) {
                    _enterSelectionMode(info.id);
                  }
                },
                onTap: _selectionMode ? () => _toggleSelectedFile(info.id) : null,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_selectionMode)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Checkbox(
                            value: isSelected,
                            onChanged: (_) => _toggleSelectedFile(info.id),
                          ),
                        ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              info.originalName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Size: ${_formatSize(info.size)}',
                              style: const TextStyle(fontSize: 13),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Uploaded: ${_formatUploadedTime(info.uploadedAt ?? DateTime.now())}',
                              style: const TextStyle(fontSize: 13),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _uploaderLabel(info),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      if (widget.userRole.toLowerCase() == 'student' &&
                          !_selectionMode)
                        IconButton(
                          icon: const Icon(Icons.download),
                          tooltip: 'Download',
                          onPressed: () => _downloadSingleMaterial(info),
                        ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required String emptyText,
    required List<_MaterialInfo> items,
    bool showUploaderLabel = false,
    bool showTitle = true,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showTitle)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                title,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(child: Text(emptyText)),
            )
          else
            ...items.map((info) {
              final isSelected = _selectedFileIds.contains(info.id);
              return GestureDetector(
                onLongPress: () {
                  if (!_selectionMode) {
                    _enterSelectionMode(info.id);
                  }
                },
                onTap: _selectionMode ? () => _toggleSelectedFile(info.id) : null,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_selectionMode)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Checkbox(
                            value: isSelected,
                            onChanged: (_) => _toggleSelectedFile(info.id),
                          ),
                        ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              info.originalName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Size: ${_formatSize(info.size)}',
                              style: const TextStyle(fontSize: 13),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Uploaded: ${_formatUploadedTime(info.uploadedAt ?? DateTime.now())}',
                              style: const TextStyle(fontSize: 13),
                            ),
                            if (showUploaderLabel) ...[
                              const SizedBox(height: 2),
                              Text(
                                _uploaderLabel(info),
                                style: const TextStyle(fontSize: 13),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (widget.userRole.toLowerCase() == 'student' &&
                          !_selectionMode)
                        IconButton(
                          icon: const Icon(Icons.download),
                          tooltip: 'Download',
                          onPressed: () => _downloadSingleMaterial(info),
                        ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
