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

class AssignmentSubmissionSection extends StatefulWidget {
  final int assignmentId;
  final int courseId;
  final String userEmail;
  final String userRole;
  final String userName;
  final ApiService apiService;
  final DateTime dueDate;

  const AssignmentSubmissionSection({
    super.key,
    required this.assignmentId,
    required this.courseId,
    required this.userEmail,
    required this.userRole,
    required this.userName,
    required this.apiService,
    required this.dueDate,
  });

  @override
  State<AssignmentSubmissionSection> createState() => _AssignmentSubmissionSectionState();
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

class _SubmissionInfo {
  final int id;
  final int assignmentId;
  final String studentEmail;
  final String studentName;
  final List<String> fileIds;
  final List<String> fileNames;
  final bool isTurnedIn;
  final DateTime? turnedInAt;
  final DateTime submittedAt;

  _SubmissionInfo({
    required this.id,
    required this.assignmentId,
    required this.studentEmail,
    required this.studentName,
    required this.fileIds,
    required this.fileNames,
    required this.isTurnedIn,
    this.turnedInAt,
    required this.submittedAt,
  });

  factory _SubmissionInfo.fromJson(Map<String, dynamic> json) {
    return _SubmissionInfo(
      id: int.tryParse(json['id'].toString()) ?? 0,
      assignmentId: int.tryParse(json['assignment_id'].toString()) ?? 0,
      studentEmail: (json['student_email'] ?? '').toString(),
      studentName: (json['student_name'] ?? '').toString(),
      fileIds: List<String>.from(json['file_ids'] ?? []),
      fileNames: List<String>.from(json['file_names'] ?? []),
      isTurnedIn: (json['is_turned_in'] == 1 || json['is_turned_in'] == true),
      turnedInAt: json['turned_in_at'] != null ? DateTime.tryParse(json['turned_in_at'].toString()) : null,
      submittedAt: DateTime.tryParse(json['submitted_at'].toString()) ?? DateTime.now(),
    );
  }
}

class _AssignmentSubmissionSectionState extends State<AssignmentSubmissionSection> {
  bool _loading = true;
  bool _uploading = false;
  List<_SubmissionInfo> _submissions = [];
  List<Map<String, dynamic>> _allStudents = [];
  int _teacherTabIndex = 0; // 0: Submitted, 1: Not Submitted
  _SubmissionInfo? _mySubmission;
  Map<String, String> _avatarUrlByKey = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final res = await widget.apiService.getAssignmentSubmissions(
        assignmentId: widget.assignmentId,
        studentEmail: widget.userRole == 'student' ? widget.userEmail : null,
      );

      if (res['success'] == true) {
        final list = (res['submissions'] as List? ?? [])
            .map((s) => _SubmissionInfo.fromJson(Map<String, dynamic>.from(s)))
            .toList();
        
        if (mounted) {
          setState(() {
            _submissions = list;
            if (widget.userRole == 'student') {
              _mySubmission = list.isNotEmpty ? list.first : null;
            }
          });
        }

        // Load avatars and student list if teacher
        if (widget.userRole == 'teacher') {
          final studentsRes = await widget.apiService.getBatchStudents(widget.courseId);
          if (studentsRes['success'] == true) {
            _allStudents = (studentsRes['students'] as List? ?? [])
                .map((s) => Map<String, dynamic>.from(s))
                .where((s) => s['is_enrolled'].toString() == '1' && s['is_blocked'].toString() != '1')
                .toList();
          }
          await _loadAvatars();
        }
      }
    } catch (e) {
      _showMsg('Error loading submissions: $e');
    } finally {
      if (mounted && !silent) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadAvatars() async {
    final Map<String, String> avatars = {};
    final students = _allStudents.isNotEmpty 
        ? _allStudents.map((s) => (s['email'] ?? '').toString()).toSet()
        : _submissions.map((s) => s.studentEmail).toSet();
    
    if (students.isEmpty) return;

    try {
      // Use query to only fetch profile pictures
      final files = await appwriteStorage.listFiles(
        bucketId: materialsBucketId,
        queries: [
          Query.limit(500),
        ],
      );

      for (final email in students) {
        final sanitized = email.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
        final prefix = 'student_profile__${sanitized}__';
        appwrite_models.File? latest;
        
        for (final file in files.files) {
          if (file.name.startsWith(prefix)) {
            if (latest == null || file.$createdAt.compareTo(latest.$createdAt) > 0) {
              latest = file;
            }
          }
        }

        if (latest != null) {
          avatars[email] = '$appwriteEndpoint/storage/buckets/$materialsBucketId/files/${latest.$id}/view?project=$appwriteProjectId';
        }
      }

      if (mounted) {
        setState(() => _avatarUrlByKey = avatars);
      }
    } catch (_) {}
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
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
        if (!kIsWeb) safePath = file.path;
      } catch (_) {
        safePath = null;
      }
      
      selected.add(_SelectedFile(
        path: safePath,
        bytes: file.bytes,
        name: file.name,
        sizeBytes: file.size,
      ));
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
            title: Text(_mySubmission == null ? 'Submit Assignment' : 'Resubmit Assignment'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text('Select files (Max 50MB each)'),
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
                          _showMsg('File size must be less than 50MB');
                        }
                      } catch (e) {
                        _showMsg('Error selecting files: $e');
                      }
                    },
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('Choose Files'),
                  ),
                  if (selectedFiles.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Theme.of(context).dividerColor),
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 180),
                        child: SingleChildScrollView(
                          child: Column(
                            children: selectedFiles.asMap().entries.map((entry) {
                              final index = entry.key;
                              final file = entry.value;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Icon(_getFileIcon(file.name), color: Colors.blue.shade300, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis, 
                                              style: const TextStyle(fontSize: 13)),
                                          Text(_formatSize(file.sizeBytes), 
                                              style: TextStyle(fontSize: 11, color: file.isValid ? Colors.grey : Colors.red)),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close, color: Colors.red, size: 18),
                                      onPressed: () => setDialogState(() => selectedFiles.removeAt(index)),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                    if (invalidCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('$invalidCount file(s) exceed 50MB and will be skipped.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red, fontSize: 11)),
                      ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: !canSubmit ? null : () {
                  final validFiles = selectedFiles.where((f) => f.isValid).toList();
                  Navigator.pop(dialogContext);
                  _uploadFiles(validFiles);
                },
                child: const Text('Submit'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _uploadFiles(List<_SelectedFile> selected) async {
    if (selected.isEmpty) return;

    setState(() => _uploading = true);
    
    try {
      // Initialize with existing files if any
      final List<String> finalFileIds = _mySubmission != null ? [..._mySubmission!.fileIds] : [];
      final List<String> finalFileNames = _mySubmission != null ? [..._mySubmission!.fileNames] : [];

      for (final file in selected) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final safeName = file.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        final uploadName = 'submission_${widget.assignmentId}_${widget.userEmail}_${timestamp}__$safeName';

        InputFile inputFile;
        if (file.path != null) {
          inputFile = InputFile.fromPath(path: file.path!, filename: uploadName);
        } else {
          inputFile = InputFile.fromBytes(bytes: file.bytes!, filename: uploadName);
        }

        final uploaded = await appwriteStorage.createFile(
          bucketId: materialsBucketId,
          fileId: ID.unique(),
          file: inputFile,
        );

        finalFileIds.add(uploaded.$id);
        finalFileNames.add(file.name);
      }

      final res = await widget.apiService.submitAssignment(
        assignmentId: widget.assignmentId,
        studentEmail: widget.userEmail,
        fileIds: finalFileIds,
        fileNames: finalFileNames,
      );

      if (res['success'] == true) {
        _showMsg('Assignment submitted successfully');
        _loadData(silent: true);
      } else {
        _showMsg(res['message'] ?? 'Failed to submit assignment');
      }
    } catch (e) {
      _showMsg('Error uploading files: $e');
    }

    setState(() => _uploading = false);
  }

  Future<void> _deleteFile(String fileId, String fileName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete File'),
        content: Text('Are you sure you want to delete "$fileName"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // First delete from Appwrite storage
      try {
        await appwriteStorage.deleteFile(
          bucketId: materialsBucketId,
          fileId: fileId,
        );
      } catch (storageError) {
        // If file not found in storage, we can still proceed with DB deletion
        if (!storageError.toString().contains('404')) {
          _showMsg('Error deleting file from storage: $storageError');
          return;
        }
      }

      final res = await widget.apiService.deleteSubmissionFile(
        assignmentId: widget.assignmentId,
        studentEmail: widget.userEmail,
        fileId: fileId,
      );

      if (res['success'] == true) {
        _showMsg('File deleted successfully');
        _loadData(silent: true);
      } else {
        _showMsg(res['message'] ?? 'Failed to delete file');
      }
    } catch (e) {
      _showMsg('Error deleting file: $e');
    }
  }

  Future<void> _toggleTurnInStatus() async {
    final currentlyTurnedIn = _mySubmission?.isTurnedIn ?? false;
    final now = DateTime.now();
    final deadline = DateTime(
      widget.dueDate.year,
      widget.dueDate.month,
      widget.dueDate.day,
      23,
      59,
      59,
    );
    final isExpired = now.isAfter(deadline);

    if (isExpired && currentlyTurnedIn) {
      return;
    }

    final String action = currentlyTurnedIn ? 'Unsubmit' : 'Turn In';
    final String content = currentlyTurnedIn 
      ? 'If you unsubmit, your files will no longer be visible to the teacher. You can turn in again after making changes.'
      : 'Are you sure you want to turn in your assignment?';
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$action Assignment'),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            child: Text(action, style: TextStyle(color: currentlyTurnedIn ? Colors.red : Colors.blue)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final res = await widget.apiService.updateSubmissionStatus(
        assignmentId: widget.assignmentId,
        studentEmail: widget.userEmail,
        isTurnedIn: !currentlyTurnedIn,
      );

      if (res['success'] == true) {
        _showMsg('Assignment ${!currentlyTurnedIn ? "turned in" : "unsubmitted"} successfully');
        _loadData(silent: true);
      } else {
        _showMsg(res['message'] ?? 'Failed to update status');
      }
    } catch (e) {
      _showMsg('Error updating status: $e');
    }
  }

  Future<void> _downloadFile(String fileId, String fileName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Download File'),
        content: Text('Do you want to download "$fileName"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('Download'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      _showMsg('Downloading $fileName...');
      final bytes = await appwriteStorage.getFileDownload(
        bucketId: materialsBucketId,
        fileId: fileId,
      );

      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: fileName.split('.').first,
          bytes: bytes,
          fileExtension: fileName.split('.').last,
          mimeType: MimeType.other,
        );
      } else {
        final downloadsPath = await ExternalPath.getExternalStoragePublicDirectory(
          ExternalPath.DIRECTORY_DOWNLOAD,
        );
        final targetDir = Directory('$downloadsPath/PSTU_BLC_Submissions');
        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }
        final targetFile = File('${targetDir.path}/$fileName');
        await targetFile.writeAsBytes(bytes, flush: true);
        _showMsg('Downloaded to ${targetFile.path}');
      }
    } catch (e) {
      _showMsg('Download failed: $e');
    }
  }

  String _formatTime(DateTime dt) {
    final year = dt.year;
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = (dt.hour % 12 == 0 ? 12 : dt.hour % 12).toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final sec = dt.second.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$year-$month-$day $hour:$min:$sec $ampm';
  }

  String _initials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return parts[0].substring(0, parts[0].length >= 2 ? 2 : 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (widget.userRole == 'student') {
      return _buildStudentView();
    } else {
      return _buildTeacherView();
    }
  }

  Widget _buildStudentView() {
    final isTurnedIn = _mySubmission?.isTurnedIn ?? false;
    final isExpired = DateTime.now().isAfter(DateTime(widget.dueDate.year, widget.dueDate.month, widget.dueDate.day, 23, 59, 59));
    
    final showCentering = isExpired && _mySubmission == null;

    Widget content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildUploadSection(),
        if (_mySubmission != null) ...[
          const SizedBox(height: 20),
          _buildSubmissionCard(_mySubmission!),
          const SizedBox(height: 16),
          if (!(isTurnedIn && isExpired))
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _toggleTurnInStatus,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isTurnedIn ? Colors.grey.shade100 : Colors.green,
                  foregroundColor: isTurnedIn ? Colors.black87 : Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: isTurnedIn ? BorderSide(color: Colors.grey.shade300) : BorderSide.none,
                  ),
                ),
                child: Text(
                  isTurnedIn ? 'Unsubmit' : 'Turn In',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
        ],
      ],
    );

    if (showCentering) {
      content = LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _buildUploadSection(),
                ),
              ),
            ),
          );
        }
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadData(silent: true),
      child: content,
    );
  }

  Widget _buildUploadSection() {
    final isTurnedIn = _mySubmission?.isTurnedIn ?? false;
    if (isTurnedIn) return const SizedBox.shrink();

    final now = DateTime.now();
    final deadline = DateTime(
      widget.dueDate.year,
      widget.dueDate.month,
      widget.dueDate.day,
      23,
      59,
      59,
    );
    final isExpired = now.isAfter(deadline);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isExpired ? Colors.red.shade100 : Colors.grey.shade200),
      ),
      color: isExpired ? Colors.red.withOpacity(0.02) : null,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              isExpired ? Icons.timer_off_outlined : Icons.cloud_upload_outlined, 
              size: 48, 
              color: isExpired ? Colors.red : Colors.blue.shade400
            ),
            const SizedBox(height: 12),
            Text(
              isExpired ? 'Submission Closed' : (_mySubmission == null ? 'Submit Assignment' : 'Add more files'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (!isExpired) ...[
              const SizedBox(height: 8),
              Text(
                'Select multiple files. Max 50MB per file.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _uploading ? null : _showUploadDialog,
                  icon: _uploading 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.add_rounded),
                  label: Text(_uploading ? 'Uploading...' : 'Choose Files'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTeacherView() {
    final submittedEmails = _submissions.map((s) => s.studentEmail.toLowerCase().trim()).toSet();
    final notSubmitted = _allStudents.where((s) {
      final email = (s['email'] ?? '').toString().toLowerCase().trim();
      return email.isNotEmpty && !submittedEmails.contains(email);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: _buildFilterTab(
                  'Submitted (${_submissions.length})', 
                  0, 
                  Colors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildFilterTab(
                  'Not Submitted (${notSubmitted.length})', 
                  1, 
                  Colors.blueGrey,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _teacherTabIndex == 0 
            ? _buildSubmittedList() 
            : _buildNotSubmittedList(notSubmitted),
        ),
      ],
    );
  }

  Widget _buildFilterTab(String label, int index, Color activeColor) {
    final isActive = _teacherTabIndex == index;
    return InkWell(
      onTap: () => setState(() => _teacherTabIndex = index),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? activeColor : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isActive ? activeColor : Colors.grey.shade300),
          boxShadow: isActive ? [
            BoxShadow(color: activeColor.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 2))
          ] : null,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.grey.shade600,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubmittedList() {
    if (_submissions.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _loadData(silent: true),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 60),
          children: const [
            Center(child: Text('No submissions yet.', style: TextStyle(color: Colors.grey))),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadData(silent: true),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _submissions.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final sub = _submissions[index];
          final avatarUrl = _avatarUrlByKey[sub.studentEmail];
          
          return Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: ExpansionTile(
                leading: _buildAvatar(avatarUrl, sub.studentName),
                title: Text(sub.studentName, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(sub.studentEmail, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.check_circle_outline_rounded, size: 16, color: Colors.green),
                            const SizedBox(width: 8),
                            Text('Submitted at: ${_formatTime(sub.turnedInAt ?? sub.submittedAt)}', 
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text('Uploaded Files:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 8),
                        ...List.generate(sub.fileIds.length, (i) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: ListTile(
                              dense: true,
                              leading: Icon(_getFileIcon(sub.fileNames[i]), color: Colors.blue.shade700, size: 20),
                              title: Text(sub.fileNames[i], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                              trailing: IconButton(
                                icon: const Icon(Icons.download_rounded, size: 20, color: Colors.blue),
                                onPressed: () => _downloadFile(sub.fileIds[i], sub.fileNames[i]),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNotSubmittedList(List<Map<String, dynamic>> students) {
    if (students.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _loadData(silent: true),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 60),
          children: const [
            Center(child: Text('All students have submitted!', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadData(silent: true),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: students.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final s = students[index];
          final email = (s['email'] ?? '').toString();
          final name = (s['name'] ?? '').toString();
          final avatarUrl = _avatarUrlByKey[email];

          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: ListTile(
              leading: _buildAvatar(avatarUrl, name),
              title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(email, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade100),
                ),
                child: const Text(
                  'Missing',
                  style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAvatar(String? url, String name) {
    if (url != null) {
      return CircleAvatar(
        radius: 20,
        backgroundColor: Colors.grey.shade200,
        backgroundImage: NetworkImage(url),
      );
    }
    return CircleAvatar(
      radius: 20,
      backgroundColor: Colors.blue.shade100,
      child: Text(_initials(name), style: TextStyle(color: Colors.blue.shade800, fontWeight: FontWeight.bold, fontSize: 14)),
    );
  }

  Widget _buildSubmissionCard(_SubmissionInfo sub) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.blue.shade100),
      ),
      color: Colors.blue.withOpacity(0.02),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  sub.isTurnedIn ? Icons.check_circle_rounded : Icons.info_outline_rounded, 
                  color: sub.isTurnedIn ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Text(
                  sub.isTurnedIn ? 'You have submitted this assignment' : 'Assignment not turned in yet', 
                  style: TextStyle(
                    fontWeight: FontWeight.bold, 
                    color: sub.isTurnedIn ? Colors.green : Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Saved at: ${_formatTime(sub.submittedAt)}', 
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            if (sub.isTurnedIn && sub.turnedInAt != null) ...[
              const SizedBox(height: 4),
              Text(
                'Submitted at: ${_formatTime(sub.turnedInAt!)}', 
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
              ),
            ],
            const Divider(height: 24),
            const Text('Files:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
                color: Colors.white,
              ),
              child: Column(
                children: List.generate(sub.fileIds.length, (i) {
                  return Column(
                    children: [
                      ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                        leading: Icon(_getFileIcon(sub.fileNames[i]), color: Colors.grey.shade700, size: 20),
                        title: Text(sub.fileNames[i], style: const TextStyle(fontSize: 13)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!sub.isTurnedIn)
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 18, color: Colors.red),
                                onPressed: () => _deleteFile(sub.fileIds[i], sub.fileNames[i]),
                              ),
                            IconButton(
                              icon: const Icon(Icons.download_rounded, size: 18),
                              onPressed: () => _downloadFile(sub.fileIds[i], sub.fileNames[i]),
                            ),
                          ],
                        ),
                      ),
                      if (i < sub.fileIds.length - 1)
                        Divider(height: 1, indent: 12, endIndent: 12, color: Colors.grey.shade100),
                    ],
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getFileIcon(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf': return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx': return Icons.description_rounded;
      case 'xls':
      case 'xlsx': return Icons.table_chart_rounded;
      case 'ppt':
      case 'pptx': return Icons.slideshow_rounded;
      case 'jpg':
      case 'jpeg':
      case 'png': return Icons.image_rounded;
      case 'zip':
      case 'rar': return Icons.archive_rounded;
      default: return Icons.insert_drive_file_rounded;
    }
  }
}
