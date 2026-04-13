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

class TeacherCourseResultSection extends StatefulWidget {
  final Map<String, dynamic> course;
  final String teacherEmail;
  final ApiService apiService;
  final int courseId;
  final String courseScope;

  const TeacherCourseResultSection({
    super.key,
    required this.course,
    required this.teacherEmail,
    required this.apiService,
    required this.courseId,
    required this.courseScope,
  });

  @override
  State<TeacherCourseResultSection> createState() =>
      _TeacherCourseResultSectionState();
}

class _ResultSelectedFile {
  final String? path;
  final Uint8List? bytes;
  final String name;
  final int sizeBytes;

  _ResultSelectedFile({
    this.path,
    this.bytes,
    required this.name,
    required this.sizeBytes,
  });

  bool get isValid => sizeBytes <= 50 * 1024 * 1024;
}

class _TeacherCourseResultSectionState extends State<TeacherCourseResultSection> {
  bool _loadingResults = true;
  bool _uploadingResults = false;
  bool _loadingSelectableStudents = true;
  bool _selectionMode = false;
  List<appwrite_models.File> _resultFiles = [];
  List<Map<String, String>> _selectableStudents = [];
  final Set<String> _selectedFileIds = <String>{};

  String get _resultPrefix => 'result_${widget.courseScope}__';
  
  bool _isVisibilityToken(String token) {
    return token == 'v_public' || token == 'v_private';
  }
  
  Map<String, dynamic> _parseStoredResultName(String storedName) {
    if (!storedName.startsWith(_resultPrefix)) {
      return {
        'studentEmail': '',
        'originalName': storedName,
        'stamp': _uploadStamp(),
        'isPrivate': false,
      };
    }
  
    final body = storedName.substring(_resultPrefix.length);
    final parts = body.split('__');
    if (parts.length < 3) {
      return {
        'studentEmail': '',
        'originalName': storedName,
        'stamp': _uploadStamp(),
        'isPrivate': false,
      };
    }
  
    final studentEmail = parts.first;
    final hasVisibility = parts.length >= 4 && _isVisibilityToken(parts[1]);
    final isPrivate = hasVisibility ? parts[1] == 'v_private' : false;
    final stamp = hasVisibility ? parts[2] : parts[1];
    final originalName = hasVisibility
        ? parts.sublist(3).join('__')
        : parts.sublist(2).join('__');
  
    return {
      'studentEmail': studentEmail,
      'originalName': originalName.isEmpty ? storedName : originalName,
      'stamp': stamp.isEmpty ? _uploadStamp() : stamp,
      'isPrivate': isPrivate,
    };
  }
  
  String _buildStoredResultName({
    required String studentEmail,
    required String stamp,
    required String originalFileName,
    required bool isPrivate,
  }) {
    final safeStudent = _sanitizeForFileName(studentEmail);
    final safeName = _sanitizeForFileName(originalFileName);
    final visibilityToken = isPrivate ? 'v_private' : 'v_public';
    return '$_resultPrefix${safeStudent}__${visibilityToken}__${stamp}__${safeName}';
  }

  @override
  void initState() {
    super.initState();
    _loadResultFiles();
    _loadSelectableStudents();
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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

  String _sanitizeForFileName(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  String _fileId(appwrite_models.File file) => file.$id;

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

  String _safePathName(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
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
      if (_selectedFileIds.length == _resultFiles.length) {
        _selectedFileIds.clear();
        _selectionMode = false;
      } else {
        _selectedFileIds
          ..clear()
          ..addAll(_resultFiles.map(_fileId).where((id) => id.isNotEmpty));
        _selectionMode = true;
      }
    });
  }

  Future<void> _downloadSelectedResults() async {
    if (_selectedFileIds.isEmpty) return;

    final selected = _resultFiles
        .where((file) => _selectedFileIds.contains(_fileId(file)))
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
    for (var index = 0; index < selected.length; index++) {
      final file = selected[index];
      try {
        final originalName = _extractOriginalFileName(file.name);
        progressText.value =
            'Downloading ${index + 1}/${selected.length}: $originalName';

        final bytes = await appwriteStorage.getFileDownload(
          bucketId: materialsBucketId,
          fileId: _fileId(file),
        );

        if (kIsWeb) {
          await FileSaver.instance.saveFile(
            name: _baseFileName(originalName),
            bytes: bytes,
            fileExtension: _fileExt(originalName),
            mimeType: MimeType.other,
          );
        } else {
          final downloadsPath =
              await ExternalPath.getExternalStoragePublicDirectory(
                ExternalPath.DIRECTORY_DOWNLOAD,
              );
          final targetDir = Directory('$downloadsPath/PSTU_BLC_Results');
          if (!await targetDir.exists()) {
            await targetDir.create(recursive: true);
          }
          final targetFile = File(
            '${targetDir.path}/${_safePathName(originalName)}',
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
    _cancelSelectionMode();
  }

  Future<void> _deleteSelectedResults() async {
    if (_selectedFileIds.isEmpty) return;

    final count = _selectedFileIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Result Files'),
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
    final selectedIds = _selectedFileIds.toList();
    for (final fileId in selectedIds) {
      try {
        await appwriteStorage.deleteFile(
          bucketId: materialsBucketId,
          fileId: fileId,
        );
        deleted++;
      } catch (_) {}
    }

    _cancelSelectionMode();
    if (deleted > 0) {
      _showMsg('$deleted file(s) deleted');
      await _loadResultFiles();
    }
  }

  Future<void> _loadResultFiles() async {
    setState(() => _loadingResults = true);
    try {
      final result = await appwriteStorage.listFiles(
        bucketId: materialsBucketId,
        queries: [Query.limit(200)],
      );
      if (!mounted) return;
      final rows = result.files
          .where((file) => file.name.startsWith(_resultPrefix))
          .toList()
        ..sort((a, b) => b.$createdAt.compareTo(a.$createdAt));
      setState(() {
        _resultFiles = rows;
        _selectedFileIds.removeWhere(
          (id) => !_resultFiles.any((file) => _fileId(file) == id),
        );
        if (_selectedFileIds.isEmpty) {
          _selectionMode = false;
        }
      });
    } catch (e) {
      _showMsg('Failed to load results: $e');
    }
    setState(() => _loadingResults = false);
  }

  String _studentNameFromEmail(String email) {
    for (final student in _selectableStudents) {
      if ((student['email'] ?? '').toLowerCase() == email.toLowerCase()) {
        final name = (student['name'] ?? '').trim();
        return name.isEmpty ? email : name;
      }
    }
    return email;
  }

  String _extractStudentEmailFromStoredName(String storedName) {
    return (_parseStoredResultName(storedName)['studentEmail'] ?? '')
        .toString();
  }

  String _extractOriginalFileName(String storedName) {
    return (_parseStoredResultName(storedName)['originalName'] ?? storedName)
        .toString();
  }
  
  bool _isPrivateFromStoredName(String storedName) {
    return _parseStoredResultName(storedName)['isPrivate'] == true;
  }

  String _formatCreatedAt(String raw) {
    try {
      final date = DateTime.parse(raw).toLocal();
      final y = date.year.toString();
      final m = date.month.toString().padLeft(2, '0');
      final d = date.day.toString().padLeft(2, '0');
      final hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
      final hh = hour12.toString().padLeft(2, '0');
      final mm = date.minute.toString().padLeft(2, '0');
      final ss = date.second.toString().padLeft(2, '0');
      final amPm = date.hour >= 12 ? 'PM' : 'AM';
      return '$y-$m-$d $hh:$mm:$ss $amPm';
    } catch (_) {
      return raw;
    }
  }

  Future<void> _loadSelectableStudents() async {
    setState(() => _loadingSelectableStudents = true);
    final result = await widget.apiService.getBatchStudents(widget.courseId);
    if (!mounted) return;

    if (result['success'] == true) {
      final rows = (result['students'] as List? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .where(
            (student) =>
                (student['is_enrolled'] ?? 0).toString() == '1' &&
                (student['is_blocked'] ?? 0).toString() != '1',
          )
          .map(
            (student) => {
              'name': (student['name'] ?? '').toString(),
              'email': (student['email'] ?? '').toString().toLowerCase(),
            },
          )
          .where((student) => (student['email'] ?? '').isNotEmpty)
          .toList();
      setState(() => _selectableStudents = rows);
    } else {
      setState(() => _selectableStudents = []);
    }

    setState(() => _loadingSelectableStudents = false);
  }

  Future<List<_ResultSelectedFile>> _pickResultFiles() async {
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: kIsWeb,
      type: FileType.any,
    );
    if (picked == null || picked.files.isEmpty) return [];

    final selected = <_ResultSelectedFile>[];
    for (final file in picked.files) {
      String? safePath;
      try {
        safePath = file.path;
      } catch (_) {
        safePath = null;
      }
      if (safePath == null && file.bytes == null) continue;
      selected.add(
        _ResultSelectedFile(
          path: safePath,
          bytes: file.bytes,
          name: file.name,
          sizeBytes: file.size,
        ),
      );
    }
    return selected;
  }

  Future<void> _showResultUploadDialog() async {
    if (_selectableStudents.isEmpty && !_loadingSelectableStudents) {
      await _loadSelectableStudents();
    }

    List<_ResultSelectedFile> selectedFiles = [];
    String? selectedStudentEmail;
    bool isPublicFile = true;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final validCount = selectedFiles.where((f) => f.isValid).length;
          final invalidCount = selectedFiles.length - validCount;
          final canSubmit =
              validCount > 0 &&
              !_uploadingResults &&
              selectedStudentEmail != null &&
              selectedStudentEmail!.isNotEmpty;
          return AlertDialog(
            title: const Text('Upload File'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text('Select files (Max 50 MB each)'),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Select Student',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_loadingSelectableStudents)
                    const SizedBox(
                      height: 46,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    DropdownButtonFormField<String>(
                      value: selectedStudentEmail,
                      isExpanded: true,
                      menuMaxHeight: 280,
                      borderRadius: BorderRadius.circular(12),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      hint: const Text('Choose student'),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surface,
                        prefixIcon: const Icon(Icons.person_outline, size: 20),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                            width: 1.4,
                          ),
                        ),
                      ),
                      selectedItemBuilder: (context) {
                        return _selectableStudents.map((student) {
                          final name = (student['name'] ?? '').toString();
                          final email = (student['email'] ?? '').toString();
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '$name ($email)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          );
                        }).toList();
                      },
                      items: _selectableStudents
                          .map(
                            (student) => DropdownMenuItem<String>(
                              value: student['email'],
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      (student['name'] ?? '').toString(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      (student['email'] ?? '').toString(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withOpacity(0.75),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setDialogState(() => selectedStudentEmail = value);
                      },
                    ),
                  if (!_loadingSelectableStudents && _selectableStudents.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'No unblocked students found for this course',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        final picked = await _pickResultFiles();
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
                  CheckboxListTile(
                    value: isPublicFile,
                    onChanged: (value) {
                      setDialogState(() => isPublicFile = value ?? true);
                    },
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Public file'),
                  ),
                  const SizedBox(height: 8),
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
                        final uploadList = List<_ResultSelectedFile>.from(selectedFiles);
                        final studentEmail = selectedStudentEmail!;
                        Navigator.pop(dialogContext);
                        await _uploadResultFiles(
                          uploadList,
                          studentEmail: studentEmail,
                          isPublic: isPublicFile,
                        );
                      },
                child: const Text('Submit'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _uploadResultFiles(
    List<_ResultSelectedFile> files, {
    required String studentEmail,
    required bool isPublic,
  }) async {
    if (_uploadingResults || files.isEmpty) return;
    setState(() => _uploadingResults = true);

    int successCount = 0;
    int skippedCount = 0;
    int notifyFailedCount = 0;

    final courseCode = (widget.course['course_code'] ?? '').toString().trim();
    final courseName = (widget.course['course_name'] ?? '').toString().trim();
    final courseLabel = [courseCode, courseName]
      .where((value) => value.isNotEmpty)
      .join(' - ');
    final notificationTitle = courseLabel.isEmpty
      ? 'Result Uploaded'
      : 'Result Uploaded: $courseLabel';

    for (final file in files) {
      if (!file.isValid) {
        skippedCount++;
        continue;
      }
      try {
        final stamp = _uploadStamp();
        final storedFileName = _buildStoredResultName(
          studentEmail: studentEmail,
          stamp: stamp,
          originalFileName: file.name,
          isPrivate: !isPublic,
        );
        late final InputFile inputFile;
        if (file.path != null) {
          inputFile = InputFile.fromPath(
            path: file.path!,
            filename: storedFileName,
          );
        } else if (file.bytes != null) {
          inputFile = InputFile.fromBytes(
            bytes: file.bytes!,
            filename: storedFileName,
          );
        } else {
          continue;
        }

        final uploaded = await appwriteStorage.createFile(
          bucketId: materialsBucketId,
          fileId: ID.unique(),
          file: inputFile,
        );
        successCount++;

        if (widget.courseId > 0 && uploaded.$id.isNotEmpty) {
          if (isPublic) {
            final notifyResult = await widget.apiService.notifyResultToStudent(
              studentEmail: studentEmail,
              courseId: widget.courseId,
              title: notificationTitle,
              message: courseLabel.isEmpty
                  ? 'A new result file has been uploaded: ${file.name}'
                  : 'A new result file has been uploaded for $courseLabel: ${file.name}',
              fileId: uploaded.$id,
              actorEmail: widget.teacherEmail,
              actorRole: 'teacher',
            );
            if (notifyResult['success'] != true) {
              notifyFailedCount++;
            }
          }
        }
      } catch (e) {
        _showMsg('Failed to upload ${file.name}: $e');
      }
    }

    if (!mounted) return;
    setState(() => _uploadingResults = false);

    if (successCount > 0) {
      _showMsg('$successCount file(s) uploaded successfully');
      await _loadResultFiles();
    }
    if (skippedCount > 0) {
      _showMsg('$skippedCount file(s) skipped (over 50 MB)');
    }
    if (notifyFailedCount > 0) {
      _showMsg('Uploaded, but $notifyFailedCount notification(s) failed to send');
    }
  }

  Future<void> _setSelectedResultsVisibility({required bool makePublic}) async {
    if (_selectedFileIds.isEmpty) return;

    final actionLabel = makePublic ? 'Public' : 'Private';
    final count = _selectedFileIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Set as $actionLabel'),
        content: Text(
          'Are you sure you want to set $count selected file(s) as $actionLabel?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    int updated = 0;
    int unchanged = 0;
    int failed = 0;
    int notifyFailedCount = 0;

    final selectedFiles = _resultFiles
        .where((file) => _selectedFileIds.contains(_fileId(file)))
        .toList();

    for (final file in selectedFiles) {
      final parsed = _parseStoredResultName(file.name);
      final currentlyPrivate = parsed['isPrivate'] == true;
      final targetPrivate = !makePublic;

      if (currentlyPrivate == targetPrivate) {
        unchanged++;
        continue;
      }

      try {
        final newName = _buildStoredResultName(
          studentEmail: (parsed['studentEmail'] ?? '').toString(),
          stamp: (parsed['stamp'] ?? _uploadStamp()).toString(),
          originalFileName: (parsed['originalName'] ?? file.name).toString(),
          isPrivate: targetPrivate,
        );
        await appwriteStorage.updateFile(
          bucketId: materialsBucketId,
          fileId: _fileId(file),
          name: newName,
        );
        updated++;

        if (makePublic && widget.courseId > 0) {
          final studentEmail = (parsed['studentEmail'] ?? '').toString();
          final originalName = (parsed['originalName'] ?? file.name).toString();
          final courseCode =
              (widget.course['course_code'] ?? '').toString().trim();
          final courseName =
              (widget.course['course_name'] ?? '').toString().trim();
          final courseLabel = [courseCode, courseName]
              .where((value) => value.isNotEmpty)
              .join(' - ');
          final notificationTitle = courseLabel.isEmpty
              ? 'Result Uploaded'
              : 'Result Uploaded: $courseLabel';

          final notifyResult = await widget.apiService.notifyResultToStudent(
            studentEmail: studentEmail,
            courseId: widget.courseId,
            title: notificationTitle,
            message: courseLabel.isEmpty
                ? 'A result file is now public: $originalName'
                : 'A result file is now public for $courseLabel: $originalName',
            fileId: _fileId(file),
            actorEmail: widget.teacherEmail,
            actorRole: 'teacher',
          );
          if (notifyResult['success'] != true) {
            notifyFailedCount++;
          }
        }
      } catch (_) {
        failed++;
      }
    }

    _cancelSelectionMode();
    await _loadResultFiles();
    _showMsg(
      '$updated updated, $unchanged unchanged${failed > 0 ? ', $failed failed' : ''}',
    );
    if (notifyFailedCount > 0) {
      _showMsg('$notifyFailedCount notification(s) failed to send');
    }
  }

  Future<void> _setSingleResultVisibility({
    required appwrite_models.File file,
    required bool makePublic,
  }) async {
    final fileId = _fileId(file);
    if (fileId.isEmpty) return;

    final parsed = _parseStoredResultName(file.name);
    final currentlyPrivate = parsed['isPrivate'] == true;
    final targetPrivate = !makePublic;

    if (currentlyPrivate == targetPrivate) {
      _showMsg(makePublic ? 'Already public' : 'Already private');
      return;
    }

    final actionLabel = makePublic ? 'Public' : 'Private';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Set as $actionLabel'),
        content: Text(
          'Are you sure you want to make this file $actionLabel?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final newName = _buildStoredResultName(
        studentEmail: (parsed['studentEmail'] ?? '').toString(),
        stamp: (parsed['stamp'] ?? _uploadStamp()).toString(),
        originalFileName: (parsed['originalName'] ?? file.name).toString(),
        isPrivate: targetPrivate,
      );

      await appwriteStorage.updateFile(
        bucketId: materialsBucketId,
        fileId: fileId,
        name: newName,
      );

      if (makePublic && widget.courseId > 0) {
        final courseCode = (widget.course['course_code'] ?? '').toString().trim();
        final courseName = (widget.course['course_name'] ?? '').toString().trim();
        final courseLabel = [courseCode, courseName]
            .where((value) => value.isNotEmpty)
            .join(' - ');
        final notificationTitle = courseLabel.isEmpty
            ? 'Result Uploaded'
            : 'Result Uploaded: $courseLabel';

        final studentEmail = (parsed['studentEmail'] ?? '').toString();
        final originalName = (parsed['originalName'] ?? file.name).toString();
        final notifyResult = await widget.apiService.notifyResultToStudent(
          studentEmail: studentEmail,
          courseId: widget.courseId,
          title: notificationTitle,
          message: courseLabel.isEmpty
              ? 'A result file is now public: $originalName'
              : 'A result file is now public for $courseLabel: $originalName',
          fileId: fileId,
          actorEmail: widget.teacherEmail,
          actorRole: 'teacher',
        );
        if (notifyResult['success'] != true) {
          _showMsg('Visibility updated, but notification failed to send');
        }
      }

      await _loadResultFiles();
      _showMsg(makePublic ? 'Set to public' : 'Set to private');
    } catch (e) {
      _showMsg('Failed to update visibility: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingResults) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadResultFiles,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SizedBox(
              height: 44,
              child: ElevatedButton.icon(
                onPressed: _uploadingResults ? null : _showResultUploadDialog,
                icon: const Icon(Icons.cloud_upload, size: 18),
                label: const Text('Upload File'),
                style: ElevatedButton.styleFrom(shape: const StadiumBorder()),
              ),
            ),
          ),
          if (_resultFiles.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 120),
              child: Center(child: Text('No result files uploaded yet.')),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Uploaded Files',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (_selectionMode || _selectedFileIds.isNotEmpty) ...[
                    Text(
                      '${_selectedFileIds.length} selected',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      onPressed: _resultFiles.isEmpty ? null : _toggleSelectAll,
                      icon: Icon(
                        _resultFiles.isNotEmpty &&
                                _selectedFileIds.length == _resultFiles.length
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        color: _resultFiles.isEmpty ? Colors.grey : null,
                      ),
                      tooltip: 'Select all',
                    ),
                    IconButton(
                      onPressed: _selectedFileIds.isEmpty
                          ? null
                          : _downloadSelectedResults,
                      icon: Icon(
                        Icons.download,
                        color: _selectedFileIds.isEmpty ? Colors.grey : null,
                      ),
                      tooltip: 'Download selected',
                    ),
                    IconButton(
                      onPressed: _selectedFileIds.isEmpty
                          ? null
                          : () => _setSelectedResultsVisibility(
                                makePublic: true,
                              ),
                      icon: Icon(
                        Icons.public,
                        color: _selectedFileIds.isEmpty ? Colors.grey : null,
                      ),
                      tooltip: 'Set selected public',
                    ),
                    IconButton(
                      onPressed: _selectedFileIds.isEmpty
                          ? null
                          : () => _setSelectedResultsVisibility(
                                makePublic: false,
                              ),
                      icon: Icon(
                        Icons.lock_outline,
                        color: _selectedFileIds.isEmpty ? Colors.grey : null,
                      ),
                      tooltip: 'Set selected private',
                    ),
                    IconButton(
                      onPressed: _selectedFileIds.isEmpty
                          ? null
                          : _deleteSelectedResults,
                      icon: Icon(
                        Icons.delete,
                        color: _selectedFileIds.isEmpty
                            ? Colors.grey
                            : Colors.red,
                      ),
                      tooltip: 'Delete selected',
                    ),
                    IconButton(
                      onPressed: _cancelSelectionMode,
                      icon: const Icon(Icons.close),
                      tooltip: 'Close',
                    ),
                  ] else
                    TextButton(
                      onPressed: _toggleSelectAll,
                      child: const Text('Select'),
                    ),
                ],
              ),
            ),
            ..._resultFiles.map((file) {
              final fileId = _fileId(file);
              final isSelected = _selectedFileIds.contains(fileId);
              final storedName = file.name;
              final studentEmail = _extractStudentEmailFromStoredName(
                storedName,
              );
              final studentName = studentEmail.isEmpty
                  ? 'Unknown'
                  : _studentNameFromEmail(studentEmail);
              final uploadedBy = studentEmail.isEmpty
                  ? studentName
                  : '$studentName ($studentEmail)';
              final originalFileName = _extractOriginalFileName(storedName);
              final uploadedAt = _formatCreatedAt(file.$createdAt);
              final fileSize = _formatSize(file.sizeOriginal);
              final isPrivate = _isPrivateFromStoredName(storedName);

              return Container(
                margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onLongPress: fileId.isEmpty
                      ? null
                      : () => _enterSelectionMode(fileId),
                  onTap: _selectionMode && fileId.isNotEmpty
                      ? () => _toggleSelectedFile(fileId)
                      : null,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_selectionMode)
                        Padding(
                          padding: const EdgeInsets.only(right: 8, top: 2),
                          child: Checkbox(
                            value: isSelected,
                            onChanged: (_) => _toggleSelectedFile(fileId),
                          ),
                        ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              originalFileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 17,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text('Size: $fileSize'),
                            const SizedBox(height: 2),
                            Text('Uploaded: $uploadedAt'),
                            const SizedBox(height: 2),
                            Text('To $uploadedBy'),
                            const SizedBox(height: 4),
                            if (!isPrivate) const SizedBox(height: 2),
                          ],
                        ),
                      ),
                      if (!_selectionMode)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: IconButton(
                            onPressed: () => _setSingleResultVisibility(
                              file: file,
                              makePublic: isPrivate,
                            ),
                            icon: Icon(
                              isPrivate ? Icons.lock_outline : Icons.public,
                              color: isPrivate
                                  ? Colors.red
                                  : Theme.of(context).colorScheme.primary,
                            ),
                            tooltip: isPrivate
                                ? 'Make public'
                                : 'Make private',
                          ),
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
}
