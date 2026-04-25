import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dart_appwrite/dart_appwrite.dart';
import 'package:file_picker/file_picker.dart';
import 'package:external_path/external_path.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pstublc/config/appwrite_storage.dart';
import 'package:pstublc/login_page.dart';
import 'package:pstublc/services/api_service.dart';
import 'package:pstublc/widgets/delete_account_dialog.dart';
import 'package:pstublc/widgets/teacher_assignment_section.dart';
import 'package:pstublc/widgets/course_discussion_section.dart';
import 'package:pstublc/widgets/course_materials_section.dart';
import 'package:pstublc/widgets/teacher_course_result_section.dart';

class _PickedProfileImage {
  final String? path;
  final Uint8List? bytes;
  final String? name;
  const _PickedProfileImage({this.path, this.bytes, this.name});
}

class TeacherDashboardPage extends StatefulWidget {
  const TeacherDashboardPage({super.key});
  @override
  State<TeacherDashboardPage> createState() => _TeacherDashboardPageState();
}

class _TeacherDashboardPageState extends State<TeacherDashboardPage> {
  final ApiService _apiService = ApiService();
  int _selectedTab = 0;
  bool _loadingCourses = true;
  bool _loadingProfile = true;
  String _email = '';
  String _facultyFilter = 'all';
  String _sessionFilter = 'all';
  String _visibilityFilter = 'all';
  String _stFacultyFilter = 'all';
  String _stSessionFilter = 'all';
  List<Map<String, dynamic>> _allCourses = [];
  List<Map<String, dynamic>> _allStudents = [];
  Map<String, String> _studentProfileImageUrlByEmail = {};
  Map<String, dynamic> _profile = {};
  bool _loadingStudents = true;
  bool _showDatabaseErrorScreen = false;
  bool _showProfilePassword = false;
  String _profileImageUrlState = '';
  String _profileImageFileId = '';
  bool _profileImageBusy = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final session = await _apiService.getSession();
    _email = session['email'] ?? '';
    await Future.wait([_loadCourses(), _loadProfile(), _loadAllStudents()]);
  }

  bool _isDatabaseConnectionError(String text) {
    final message = text.toLowerCase();
    return message.contains('connection error') ||
        message.contains('database connection failed') ||
        message.contains('socketexception');
  }

  void _showMsg(String text) {
    if (_isDatabaseConnectionError(text)) {
      if (!_showDatabaseErrorScreen && mounted) {
        setState(() => _showDatabaseErrorScreen = true);
      }
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _loadCourses() async {
    if (_email.isEmpty) return;
    setState(() => _loadingCourses = true);
    final result = await _apiService.getTeacherCourses(_email);
    if (!mounted) return;
    if (result['success'] == true) {
      final rows = (result['courses'] as List? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      setState(() => _allCourses = rows);
    } else {
      _showMsg(result['message'] ?? 'Failed to load courses');
    }
    setState(() => _loadingCourses = false);
  }

  Future<void> _loadProfile() async {
    if (_email.isEmpty) return;
    setState(() => _loadingProfile = true);
    final result = await _apiService.getProfile('teacher', _email);
    if (!mounted) return;
    if (result['success'] == true && result['data'] is Map) {
      setState(
        () => _profile = Map<String, dynamic>.from(result['data'] as Map),
      );
    } else {
      _showMsg(result['message'] ?? 'Failed to load profile');
    }
    await _loadProfileAvatarFromStorage();
    setState(() => _loadingProfile = false);
  }

  String _profileImagePrefix() {
    final safeEmail = _email.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '_',
    );
    return 'teacher_profile__${safeEmail}__';
  }

  String _buildProfileImageUrl(String fileId) {
    return '$appwriteEndpoint/storage/buckets/$materialsBucketId/files/$fileId/view?project=$appwriteProjectId';
  }

  Future<void> _loadProfileAvatarFromStorage() async {
    try {
      final prefix = _profileImagePrefix();
      final files = await appwriteStorage.listFiles(
        bucketId: materialsBucketId,
        queries: [Query.limit(500)],
      );
      final candidates =
          files.files.where((f) => f.name.startsWith(prefix)).toList()
            ..sort((a, b) => b.$createdAt.compareTo(a.$createdAt));
      if (!mounted) return;
      if (candidates.isEmpty) {
        setState(() {
          _profileImageUrlState = '';
          _profileImageFileId = '';
        });
        return;
      }
      final latest = candidates.first;
      setState(() {
        _profileImageFileId = latest.$id;
        _profileImageUrlState = _buildProfileImageUrl(latest.$id);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _profileImageUrlState = '';
        _profileImageFileId = '';
      });
    }
  }

  Future<void> _openProfileImageOptions() async {
    if (_profileImageBusy) return;
    final hasCustom = _profileImageFileId.isNotEmpty;
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildProfilePhotoPreview(size: 92),
              const SizedBox(height: 12),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, null),
              child: const Text('Cancel'),
            ),
            TextButton.icon(
              onPressed: hasCustom
                  ? () => Navigator.pop(dialogContext, 'delete')
                  : null,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(dialogContext, 'upload'),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Upload'),
            ),
          ],
        );
      },
    );
    if (action == 'upload') {
      await _pickCropAndUploadProfileImage();
    } else if (action == 'delete') {
      await _deleteProfileImage();
    }
  }

  Future<void> _pickCropAndUploadProfileImage() async {
    try {
      setState(() => _profileImageBusy = true);
      final selected = await _pickImageWithFallback();
      if (selected == null) {
        if (mounted) setState(() => _profileImageBusy = false);
        return;
      }

      final originalBytes = selected.bytes;
      if (originalBytes == null || originalBytes.isEmpty) {
        if (mounted) setState(() => _profileImageBusy = false);
        return;
      }

      final confirmed = await _showUploadConfirmDialog(originalBytes);
      if (confirmed != true) {
        if (mounted) setState(() => _profileImageBusy = false);
        return;
      }

      final prefix = _profileImagePrefix();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${prefix}${stamp}.jpg';
      final uploaded = await appwriteStorage.createFile(
        bucketId: materialsBucketId,
        fileId: ID.unique(),
        file: InputFile.fromBytes(bytes: originalBytes, filename: fileName),
      );

      await _deleteOldProfileImagesExcept(uploaded.$id);

      if (mounted) {
        setState(() {
          _profileImageFileId = uploaded.$id;
          _profileImageUrlState = _buildProfileImageUrl(uploaded.$id);
        });
      }
      _showMsg('Profile photo uploaded');
    } catch (e) {
      _showMsg('Failed to upload profile photo: $e');
    } finally {
      if (mounted) setState(() => _profileImageBusy = false);
    }
  }

  Future<void> _deleteOldProfileImagesExcept(String keepFileId) async {
    final prefix = _profileImagePrefix();
    try {
      final files = await appwriteStorage.listFiles(
        bucketId: materialsBucketId,
        queries: [Query.limit(500)],
      );
      for (final file in files.files) {
        if (!file.name.startsWith(prefix)) continue;
        if (file.$id == keepFileId) continue;
        try {
          await appwriteStorage.deleteFile(
            bucketId: materialsBucketId,
            fileId: file.$id,
          );
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<bool?> _showUploadConfirmDialog(Uint8List imageBytes) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Upload'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(
                  imageBytes,
                  fit: BoxFit.cover,
                  width: 180,
                  height: 180,
                  filterQuality: FilterQuality.low,
                ),
              ),
              const SizedBox(height: 10),
              const Text('Upload this image as profile picture?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Upload'),
            ),
          ],
        );
      },
    );
  }

  Future<_PickedProfileImage?> _pickImageWithFallback() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 2000,
        maxHeight: 2000,
      );
      if (picked == null) return null;
      if (kIsWeb) {
        final bytes = await picked.readAsBytes();
        if (bytes.isEmpty) return null;
        return _PickedProfileImage(path: null, bytes: bytes, name: picked.name);
      }
      final path = picked.path;
      if (path.isEmpty) {
        final bytes = await picked.readAsBytes();
        if (bytes.isEmpty) return null;
        return _PickedProfileImage(path: null, bytes: bytes, name: picked.name);
      }
      final bytes = await picked.readAsBytes();
      return _PickedProfileImage(path: path, bytes: bytes, name: picked.name);
    } on MissingPluginException {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      final file = picked?.files.single;
      final bytes = file?.bytes;
      final hasPath = !kIsWeb && (file?.path != null && file!.path!.isNotEmpty);
      final hasBytes = bytes != null && bytes.isNotEmpty;
      if (!hasPath && !hasBytes) {
        _showMsg('Selection failed');
        return null;
      }
      if (kIsWeb) {
        return _PickedProfileImage(
          path: null,
          bytes: hasBytes ? bytes : null,
          name: file?.name,
        );
      }
      return _PickedProfileImage(
        path: hasPath ? file.path : null,
        bytes: hasBytes ? bytes : null,
        name: file?.name,
      );
    } catch (e) {
      _showMsg('Failed to pick image: $e');
      return null;
    }
  }

  Widget _buildProfilePhotoPreview({double size = 88}) {
    final imageUrl = _profileImageUrl();
    final initials = _profileInitials();
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: Colors.green.withOpacity(0.12),
      backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
      child: imageUrl.isNotEmpty
          ? null
          : (initials.isNotEmpty
                ? Text(
                    initials,
                    style: TextStyle(
                      fontSize: size * 0.26,
                      fontWeight: FontWeight.w700,
                      color: Colors.green,
                    ),
                  )
                : Icon(
                    Icons.person_outline,
                    size: size * 0.36,
                    color: Colors.green,
                  )),
    );
  }

  Future<void> _deleteProfileImage() async {
    if (_profileImageFileId.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Profile Photo'),
        content: const Text('Remove profile photo and use default avatar?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      setState(() => _profileImageBusy = true);
      await appwriteStorage.deleteFile(
        bucketId: materialsBucketId,
        fileId: _profileImageFileId,
      );
      if (!mounted) return;
      setState(() {
        _profileImageFileId = '';
        _profileImageUrlState = '';
      });
      _showMsg('Profile photo deleted');
    } catch (e) {
      _showMsg('Failed to delete profile photo: $e');
    } finally {
      if (mounted) setState(() => _profileImageBusy = false);
    }
  }

  Future<void> _loadAllStudents() async {
    setState(() => _loadingStudents = true);
    final result = await _apiService.getAllStudents();
    if (!mounted) return;
    if (result['success'] == true) {
      final rows = (result['students'] as List? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      final avatarMap = await _loadStudentProfileImages(rows);
      if (!mounted) return;
      setState(() {
        _allStudents = rows;
        _studentProfileImageUrlByEmail = avatarMap;
      });
    } else {
      _showMsg(result['message'] ?? 'Failed to load students');
    }
    setState(() => _loadingStudents = false);
  }

  String _sanitizeStudentEmail(String email) {
    return email.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  }

  String _studentInitialsFromName(String name) {
    final normalized = name.trim();
    if (normalized.isEmpty) return '';
    final parts = normalized
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1) {
      final one = parts.first;
      return one.length >= 2
          ? one.substring(0, 2).toUpperCase()
          : one.substring(0, 1).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  String _studentImageUrlFromFileId(String fileId) {
    return '$appwriteEndpoint/storage/buckets/$materialsBucketId/files/$fileId/view?project=$appwriteProjectId';
  }

  Future<Map<String, String>> _loadStudentProfileImages(
    List<Map<String, dynamic>> students,
  ) async {
    final emailToPrefix = <String, String>{};
    for (final student in students) {
      final email = (student['email'] ?? '').toString().trim().toLowerCase();
      if (email.isEmpty) continue;
      emailToPrefix[email] =
          'student_profile__${_sanitizeStudentEmail(email)}__';
    }
    if (emailToPrefix.isEmpty) return <String, String>{};

    try {
      final files = await appwriteStorage.listFiles(
        bucketId: materialsBucketId,
        queries: [Query.limit(500)],
      );

      final latestFileByEmail = <String, dynamic>{};
      for (final file in files.files) {
        for (final entry in emailToPrefix.entries) {
          final email = entry.key;
          final prefix = entry.value;
          if (!file.name.startsWith(prefix)) continue;
          final existing = latestFileByEmail[email];
          if (existing == null ||
              file.$createdAt.compareTo(existing.$createdAt) > 0) {
            latestFileByEmail[email] = file;
          }
          break;
        }
      }

      final urls = <String, String>{};
      latestFileByEmail.forEach((email, file) {
        urls[email] = _studentImageUrlFromFileId(file.$id);
      });
      return urls;
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<void> _createCourse() async {
    final code = TextEditingController();
    final name = TextEditingController();
    final session = TextEditingController();
    String faculty = 'CSE';
    bool isPrivate = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Create Course'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: code,
                    decoration: const InputDecoration(labelText: 'Course Code'),
                  ),
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Course Name'),
                  ),
                  TextField(
                    controller: session,
                    decoration: const InputDecoration(
                      labelText: 'Session (ex: 2022-23)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: faculty,
                    items: const [
                      DropdownMenuItem(value: 'AGRI', child: Text('AGRI')),
                      DropdownMenuItem(value: 'CSE', child: Text('CSE')),
                      DropdownMenuItem(value: 'FBA', child: Text('FBA')),
                      DropdownMenuItem(
                        value: 'FISHERIES',
                        child: Text('FISHERIES'),
                      ),
                      DropdownMenuItem(value: 'NFS', child: Text('NFS')),
                      DropdownMenuItem(value: 'ESDM', child: Text('ESDM')),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => faculty = value ?? 'CSE'),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: isPrivate,
                    title: const Text('Private course'),

                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (value) =>
                        setDialogState(() => isPrivate = value ?? false),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Create'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    final result = await _apiService.createCourse(
      email: _email,
      code: code.text.trim(),
      name: name.text.trim(),
      session: session.text.trim(),
      faculty: faculty,
      isPrivate: isPrivate,
    );
    if (result['success'] == true) {
      _showMsg('Course created successfully');
      await _loadCourses();
    } else {
      _showMsg(result['message'] ?? 'Create failed');
    }
  }

  Future<void> _toggleVisibility(Map<String, dynamic> course) async {
    final id = int.tryParse((course['course_id'] ?? 0).toString()) ?? 0;
    final isPrivate = ((course['is_private'] ?? 0).toString() == '1');
    final newState = !isPrivate;
    final label = newState ? 'Private' : 'Public';
    final courseName = (course['course_name'] ?? 'this course').toString();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Make $label?'),
        content: Text('Are you sure you want to make "$courseName" $label?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: newState ? Colors.orange : Colors.green,
              foregroundColor: Colors.white,
            ),
            child: Text('Make $label'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final result = await _apiService.toggleCourseVisibility(
      courseId: id,
      isPrivate: newState,
    );
    if (result['success'] == true) {
      await _loadCourses();
    }
    _showMsg(result['message'] ?? 'Update failed');
  }

  Future<void> _editCourse(Map<String, dynamic> course) async {
    final courseId = int.tryParse((course['course_id'] ?? 0).toString()) ?? 0;
    final code = TextEditingController(
      text: (course['course_code'] ?? '').toString(),
    );
    final name = TextEditingController(
      text: (course['course_name'] ?? '').toString(),
    );
    final session = TextEditingController(
      text: (course['session'] ?? '').toString(),
    );
    String faculty = (course['faculty_name'] ?? 'CSE').toString().toUpperCase();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Edit Course'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: code,
                    decoration: const InputDecoration(labelText: 'Course Code'),
                  ),
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Course Name'),
                  ),
                  TextField(
                    controller: session,
                    decoration: const InputDecoration(
                      labelText: 'Session (ex: 2022-23)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: faculty,
                    items: const [
                      DropdownMenuItem(value: 'AGRI', child: Text('AGRI')),
                      DropdownMenuItem(value: 'CSE', child: Text('CSE')),
                      DropdownMenuItem(value: 'FBA', child: Text('FBA')),
                      DropdownMenuItem(
                        value: 'FISHERIES',
                        child: Text('FISHERIES'),
                      ),
                      DropdownMenuItem(value: 'NFS', child: Text('NFS')),
                      DropdownMenuItem(value: 'ESDM', child: Text('ESDM')),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => faculty = value ?? faculty),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;

    final result = await _apiService.updateCourse(
      courseId: courseId,
      email: _email,
      code: code.text.trim(),
      name: name.text.trim(),
      session: session.text.trim(),
      faculty: faculty,
    );
    if (result['success'] == true) {
      _showMsg(result['message'] ?? 'Course updated successfully');
      await _loadCourses();
    } else {
      _showMsg(result['message'] ?? 'Update failed');
    }
  }

  Future<void> _deleteCourse(Map<String, dynamic> course) async {
    final courseId = int.tryParse((course['course_id'] ?? 0).toString()) ?? 0;
    final courseScope = _courseScopeFromCourse(course);
    final passwordController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Course'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Are you sure you want to delete this course? All associated data will be removed.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Enter password to confirm',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _deleteCourseResultFiles(courseScope);
    } catch (e) {
      _showMsg('Failed to delete course-related files: $e');
      return;
    }

    final result = await _apiService.deleteCourse(
      courseId: courseId,
      email: _email,
      password: passwordController.text,
    );
    if (result['success'] == true) {
      _showMsg('Course deleted successfully');
      await _loadCourses();
    } else {
      _showMsg(result['message'] ?? 'Delete failed');
    }
  }

  String _courseScopeFromCourse(Map<String, dynamic> course) {
    final courseId = int.tryParse(
      (course['course_id'] ?? course['id'] ?? course['courseId'] ?? 0)
          .toString(),
    );
    if ((courseId ?? 0) > 0) return courseId.toString();

    final code = (course['course_code'] ?? course['code'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    final session = (course['session'] ?? '').toString().toLowerCase().trim();
    final raw = '${code}_$session';
    final safe = raw.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return safe.isEmpty ? 'unknown_course' : safe;
  }

  Future<void> _deleteCourseResultFiles(String courseScope) async {
    final prefixes = <String>[
      'course_${courseScope}__',
      'result_${courseScope}__',
    ];
    final result = await appwriteStorage.listFiles(
      bucketId: materialsBucketId,
      queries: [Query.limit(500)],
    );

    for (final file in result.files) {
      if (!prefixes.any((prefix) => file.name.startsWith(prefix))) continue;
      await appwriteStorage.deleteFile(
        bucketId: materialsBucketId,
        fileId: file.$id,
      );
    }
  }

  Future<void> _editField(String field, String current) async {
    final profileCurrent = switch (field) {
      'name' => (_profile['name'] ?? '').toString(),
      'email' => (_profile['email'] ?? '').toString(),
      'phone' => (_profile['phone'] ?? '').toString(),
      _ => (_profile[field] ?? '').toString(),
    };
    final controller = TextEditingController();
    final updated = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit ${field[0].toUpperCase()}${field.substring(1)}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: 'Enter $field'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (updated == null ||
        updated.isEmpty ||
        updated == profileCurrent ||
        updated == current) {
      return;
    }
    final result = await _apiService.updateProfileField(
      role: 'teacher',
      email: _email,
      field: field,
      value: updated,
    );
    if (result['success'] == true) {
      if (field == 'email') {
        _email = updated.toLowerCase();
      }
      await _loadProfile();
      _showMsg('Profile updated');
    } else {
      _showMsg(result['message'] ?? 'Update failed');
    }
  }

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: current,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current Password'),
            ),
            TextField(
              controller: next,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New Password'),
            ),
            TextField(
              controller: confirm,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirm New Password',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (next.text.length < 3) {
      _showMsg('Password must be at least 3 characters');
      return;
    }
    if (next.text != confirm.text) {
      _showMsg('Passwords do not match');
      return;
    }
    final result = await _apiService.changePassword(
      role: 'teacher',
      email: _email,
      currentPassword: current.text,
      newPassword: next.text,
    );
    if (result['success'] == true) {
      await _loadProfile();
      if (mounted) {
        setState(() {
          _showProfilePassword = false;
        });
      }
    }
    _showMsg(
      result['message'] ??
          (result['success'] == true ? 'Password updated' : 'Update failed'),
    );
  }

  Future<void> _deleteAccount() async {
    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => DeleteAccountDialog(
        email: _email,
        role: 'teacher',
        apiService: _apiService,
      ),
    );

    if (deleted == true) {
      await _apiService.logout();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (_) => false,
      );
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await _apiService.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  List<Map<String, dynamic>> get _filteredCourses {
    final filtered = _allCourses.where((course) {
      final facultyName = (course['faculty_name'] ?? '')
          .toString()
          .toUpperCase();
      final session = (course['session'] ?? '').toString();
      final isPrivate = ((course['is_private'] ?? 0).toString() == '1');
      final passFaculty =
          _facultyFilter == 'all' || facultyName == _facultyFilter;
      final passSession = _sessionFilter == 'all' || session == _sessionFilter;
      final passVisibility =
          _visibilityFilter == 'all' ||
          (_visibilityFilter == 'private' && isPrivate) ||
          (_visibilityFilter == 'public' && !isPrivate);
      return passFaculty && passSession && passVisibility;
    }).toList();

    final publicCourses = filtered
        .where((course) => (course['is_private'] ?? 0).toString() != '1')
        .toList();
    final privateCourses = filtered
        .where((course) => (course['is_private'] ?? 0).toString() == '1')
        .toList();

    return [...publicCourses, ...privateCourses];
  }

  @override
  Widget build(BuildContext context) {
    if (_showDatabaseErrorScreen) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset('img/sad-face.png', height: 180),
                  const SizedBox(height: 20),
                  const Text(
                    'Database Error\nBe Paitent',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Teacher Panel'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      ),
      body: IndexedStack(
        index: _selectedTab,
        children: [_buildCoursesTab(), _buildStudentsTab(), _buildProfileTab()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) => setState(() => _selectedTab = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.menu_book), label: 'Courses'),
          NavigationDestination(icon: Icon(Icons.people), label: 'Students'),
          NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
      floatingActionButton: _selectedTab == 0
          ? FloatingActionButton.extended(
              onPressed: _createCourse,
              icon: const Icon(Icons.add),
              label: const Text('Create Course'),
            )
          : null,
    );
  }

  Widget _buildCoursesTab() {
    if (_loadingCourses) {
      return const Center(child: CircularProgressIndicator());
    }
    final sessions =
        _allCourses.map((e) => (e['session'] ?? '').toString()).toSet().toList()
          ..sort();
    final faculties =
        _allCourses
            .map((e) => (e['faculty_name'] ?? '').toString().toUpperCase())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final courses = _filteredCourses;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              DropdownButton<String>(
                value: _facultyFilter,
                items: [
                  const DropdownMenuItem(
                    value: 'all',
                    child: Text('All Faculties'),
                  ),
                  ...faculties.map(
                    (f) => DropdownMenuItem(value: f, child: Text(f)),
                  ),
                ],
                onChanged: (v) => setState(() => _facultyFilter = v ?? 'all'),
              ),
              DropdownButton<String>(
                value: _sessionFilter,
                items: [
                  const DropdownMenuItem(
                    value: 'all',
                    child: Text('All Sessions'),
                  ),
                  ...sessions.map(
                    (s) => DropdownMenuItem(value: s, child: Text(s)),
                  ),
                ],
                onChanged: (v) => setState(() => _sessionFilter = v ?? 'all'),
              ),
              DropdownButton<String>(
                value: _visibilityFilter,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All Visibility')),
                  DropdownMenuItem(value: 'public', child: Text('Public Only')),
                  DropdownMenuItem(
                    value: 'private',
                    child: Text('Private Only'),
                  ),
                ],
                onChanged: (v) =>
                    setState(() => _visibilityFilter = v ?? 'all'),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadCourses,
            child: courses.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 250),
                      Center(child: Text('No courses available')),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: courses.length,
                    itemBuilder: (context, index) {
                      final c = courses[index];
                      final isPrivate =
                          ((c['is_private'] ?? 0).toString() == '1');
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: ListTile(
                          title: Text(
                            '${c['course_code']} - ${c['course_name']}',
                          ),
                          subtitle: Text(
                            'Session: ${c['session']} | ${c['faculty_name']}\nEnrolled: ${c['enrolled_count'] ?? 0}/${c['student_count'] ?? 0}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: isPrivate
                                    ? 'Set Public'
                                    : 'Set Private',
                                onPressed: () => _toggleVisibility(c),
                                icon: Icon(
                                  isPrivate ? Icons.lock : Icons.lock_open,
                                ),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    _editCourse(c);
                                  } else if (value == 'delete') {
                                    _deleteCourse(c);
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Edit'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text(
                                      'Delete',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TeacherCourseDetailPage(
                                  course: c,
                                  teacherEmail: _email,
                                  apiService: _apiService,
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildStudentsTab() {
    if (_loadingStudents) {
      return const Center(child: CircularProgressIndicator());
    }
    final faculties =
        _allStudents
            .map((e) => (e['faculty_name'] ?? '').toString())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final sessions =
        _allStudents
            .map((e) => (e['session'] ?? '').toString())
            .where((e) => e.isNotEmpty && e != 'Unknown')
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));
    final students = _allStudents.where((s) {
      final passFaculty =
          _stFacultyFilter == 'all' || s['faculty_name'] == _stFacultyFilter;
      final passSession =
          _stSessionFilter == 'all' || s['session'] == _stSessionFilter;
      return passFaculty && passSession;
    }).toList();
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            boxShadow: [
              BoxShadow(blurRadius: 4, color: Colors.black.withOpacity(0.05)),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _stFacultyFilter,
                  decoration: const InputDecoration(
                    labelText: 'Faculty',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('All Faculties'),
                    ),
                    ...faculties.map(
                      (f) => DropdownMenuItem(value: f, child: Text(f)),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => _stFacultyFilter = v ?? 'all'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _stSessionFilter,
                  decoration: const InputDecoration(
                    labelText: 'Session',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('All Sessions'),
                    ),
                    ...sessions.map(
                      (s) => DropdownMenuItem(value: s, child: Text(s)),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => _stSessionFilter = v ?? 'all'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadAllStudents,
            child: students.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 200),
                      Center(child: Text('No students found.')),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: students.length,
                    itemBuilder: (context, index) {
                      final s = students[index];
                      final studentName = (s['name'] ?? '').toString();
                      final studentInitials = _studentInitialsFromName(
                        studentName,
                      );
                      final email = (s['email'] ?? '').toString();
                      final studentImageUrl =
                          _studentProfileImageUrlByEmail[email
                              .trim()
                              .toLowerCase()] ??
                          '';
                      final match = RegExp(r'(\d+)@').firstMatch(email);
                      final rollNo = match?.group(1) ?? 'N/A';
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.green.withOpacity(0.2),
                            backgroundImage: studentImageUrl.isNotEmpty
                                ? NetworkImage(studentImageUrl)
                                : null,
                            child: studentImageUrl.isNotEmpty
                                ? null
                                : (studentInitials.isNotEmpty
                                      ? Text(
                                          studentInitials,
                                          style: const TextStyle(
                                            color: Colors.green,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.person,
                                          color: Colors.green,
                                        )),
                          ),
                          title: Text(studentName),
                          subtitle: Text(
                            'Roll: $rollNo | ${s['faculty_name']} | ${s['session']}',
                          ),
                          trailing: const Icon(Icons.chevron_right, size: 16),
                          onTap: () {
                            final studentName = (s['name'] ?? 'Student Profile')
                                .toString();
                            final studentInitials = _studentInitialsFromName(
                              studentName,
                            );
                            final studentEmail = (s['email'] ?? 'N/A')
                                .toString();
                            final studentImageUrl =
                                _studentProfileImageUrlByEmail[(s['email'] ??
                                        '')
                                    .toString()
                                    .trim()
                                    .toLowerCase()] ??
                                '';
                            final studentPhone = (s['phone'] ?? 'N/A')
                                .toString();
                            final studentFaculty = (s['faculty_name'] ?? 'N/A')
                                .toString();
                            final studentSession = (s['session'] ?? 'N/A')
                                .toString();
                            Future<void> copyValue(
                              String label,
                              String value,
                            ) async {
                              final trimmed = value.trim();
                              if (trimmed.isEmpty ||
                                  trimmed.toLowerCase() == 'n/a') {
                                _showMsg('No $label to copy');
                                return;
                              }
                              await Clipboard.setData(
                                ClipboardData(text: trimmed),
                              );
                              _showMsg('$label copied');
                            }

                            showDialog(
                              context: context,
                              builder: (c) => AlertDialog(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                titlePadding: const EdgeInsets.fromLTRB(
                                  20,
                                  18,
                                  20,
                                  0,
                                ),
                                contentPadding: const EdgeInsets.fromLTRB(
                                  20,
                                  14,
                                  20,
                                  8,
                                ),
                                actionsPadding: const EdgeInsets.fromLTRB(
                                  8,
                                  0,
                                  8,
                                  8,
                                ),
                                title: Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: Colors.green.withOpacity(
                                        0.12,
                                      ),
                                      backgroundImage:
                                          studentImageUrl.isNotEmpty
                                          ? NetworkImage(studentImageUrl)
                                          : null,
                                      child: studentImageUrl.isNotEmpty
                                          ? null
                                          : (studentInitials.isNotEmpty
                                                ? Text(
                                                    studentInitials,
                                                    style: const TextStyle(
                                                      color: Colors.green,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  )
                                                : const Icon(
                                                    Icons.person,
                                                    color: Colors.green,
                                                  )),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        studentName,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                content: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color: Theme.of(c).colorScheme.surface,
                                    border: Border.all(
                                      color: Theme.of(c).dividerColor,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      InkWell(
                                        borderRadius: BorderRadius.circular(8),
                                        onTap: () =>
                                            copyValue('Email', studentEmail),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 6,
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.email_outlined,
                                                size: 18,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  studentEmail,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Icon(
                                                Icons.copy_rounded,
                                                size: 16,
                                                color: Theme.of(
                                                  c,
                                                ).colorScheme.onSurface,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      InkWell(
                                        borderRadius: BorderRadius.circular(8),
                                        onTap: () =>
                                            copyValue('Phone', studentPhone),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 6,
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.phone_outlined,
                                                size: 18,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  studentPhone,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Icon(
                                                Icons.copy_rounded,
                                                size: 16,
                                                color: Theme.of(
                                                  c,
                                                ).colorScheme.onSurface,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.apartment_outlined,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(child: Text(studentFaculty)),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.calendar_today_outlined,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(child: Text(studentSession)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(c),
                                    child: const Text('Close'),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileTab() {
    if (_loadingProfile) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _loadProfile,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _buildProfileAvatarHeader(),
          const SizedBox(height: 14),
          _buildProfileCombinedCard(),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            label: const Text('Logout'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: _deleteAccount,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete Account'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileAvatarHeader() {
    return Center(
      child: SizedBox(
        width: 98,
        height: 98,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            _buildProfilePhotoPreview(),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: IconButton(
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  padding: EdgeInsets.zero,
                  iconSize: 16,
                  onPressed: _openProfileImageOptions,
                  tooltip: 'Edit profile picture',
                  icon: const Icon(Icons.edit_outlined, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _profileImageUrl() {
    if (_profileImageUrlState.isNotEmpty) return _profileImageUrlState;
    const keys = [
      'profile_image',
      'profile_pic',
      'profilePhoto',
      'avatar',
      'photo_url',
    ];
    for (final key in keys) {
      final value = (_profile[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _profileInitials() {
    final name = (_profile['name'] ?? '').toString().trim();
    if (name.isEmpty) return '';
    final parts = name
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1) {
      final one = parts.first;
      return one.length >= 2
          ? one.substring(0, 2).toUpperCase()
          : one.substring(0, 1).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  Widget _buildProfileCombinedCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.green.withOpacity(0.25)),
        color: Colors.green.withOpacity(0.04),
      ),
      child: Column(
        children: [
          _buildProfileDetailRow(
            title: 'Name',
            value: (_profile['name'] ?? '').toString(),
            icon: Icons.badge_outlined,
            onEdit: () =>
                _editField('name', (_profile['name'] ?? '').toString()),
          ),
          const Divider(height: 1),
          _buildProfileDetailRow(
            title: 'Email',
            value: (_profile['email'] ?? '').toString(),
            icon: Icons.email_outlined,
            onEdit: () =>
                _editField('email', (_profile['email'] ?? '').toString()),
          ),
          const Divider(height: 1),
          _buildProfileDetailRow(
            title: 'Phone',
            value: (_profile['phone'] ?? '').toString(),
            icon: Icons.phone_outlined,
            onEdit: () =>
                _editField('phone', (_profile['phone'] ?? '').toString()),
          ),
          const Divider(height: 1),
          _buildProfileDetailRow(
            title: 'Password',
            value: _showProfilePassword
                ? ((_profile['password'] ?? '').toString().isNotEmpty
                      ? (_profile['password'] ?? '').toString()
                      : 'Password hidden')
                : '****',
            icon: Icons.lock_outline,
            onEdit: _changePassword,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: _showProfilePassword
                      ? 'Hide password'
                      : 'Show password',
                  icon: Icon(
                    _showProfilePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() {
                      _showProfilePassword = !_showProfilePassword;
                    });
                  },
                ),
                IconButton(
                  tooltip: 'Edit Password',
                  onPressed: _changePassword,
                  icon: const Icon(Icons.edit_outlined, size: 20),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileDetailRow({
    required String title,
    required String value,
    required IconData icon,
    required VoidCallback onEdit,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.green, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.3,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.55),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          trailing ??
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                tooltip: 'Edit $title',
                onPressed: onEdit,
              ),
        ],
      ),
    );
  }
}

class TeacherCourseDetailPage extends StatefulWidget {
  final Map<String, dynamic> course;
  final String teacherEmail;
  final ApiService apiService;
  const TeacherCourseDetailPage({
    super.key,
    required this.course,
    required this.teacherEmail,
    required this.apiService,
  });
  @override
  State<TeacherCourseDetailPage> createState() =>
      _TeacherCourseDetailPageState();
}

class _TeacherCourseDetailPageState extends State<TeacherCourseDetailPage> {
  bool _loadingStudents = true;
  bool _loadingAttendance = true;
  bool _showAttendanceHistory = false;
  bool _showStudentDetails = false;
  Timer? _attendanceTicker;
  Future<Map<String, dynamic>>? _studentOverviewFuture;
  List<Map<String, dynamic>> _students = [];
  Map<String, String> _studentProfileImageUrlByEmail = {};
  List<Map<String, dynamic>> _attendanceSessions = [];
  int get _courseId =>
      int.tryParse(
        (widget.course['course_id'] ??
                widget.course['id'] ??
                widget.course['courseId'] ??
                0)
            .toString(),
      ) ??
      0;

  String get _courseScope {
    if (_courseId > 0) return _courseId.toString();
    final code = (widget.course['course_code'] ?? widget.course['code'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    final session = (widget.course['session'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    final raw = '${code}_$session';
    final safe = raw.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return safe.isEmpty ? 'unknown_course' : safe;
  }

  @override
  void initState() {
    super.initState();
    _loadAll();
    _attendanceTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_loadingAttendance) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _attendanceTicker?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration duration, {bool withSeconds = false}) {
    final safe = duration.isNegative ? Duration.zero : duration;
    final hours = safe.inHours;
    final minutes = safe.inMinutes.remainder(60);
    final seconds = safe.inSeconds.remainder(60);
    if (withSeconds) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
  }

  String _formatMarkedTime(dynamic rawTime) {
    final value = rawTime?.toString() ?? '';
    if (value.isEmpty) return '';
    try {
      final parsed = DateTime.parse(value);
      final adjusted = parsed.subtract(const Duration(hours: 1));
      int hour = adjusted.hour;
      final minute = adjusted.minute.toString().padLeft(2, '0');
      final second = adjusted.second.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'PM' : 'AM';
      hour = hour % 12;
      if (hour == 0) hour = 12;
      return '$hour:$minute:$second $period';
    } catch (_) {
      final parts = value.split(' ');
      return parts.length > 1 ? parts[1] : value;
    }
  }

  Future<void> _toggleAttendanceFromReport({
    required int sessionId,
    required String studentEmail,
    required bool currentPresent,
    required VoidCallback onUpdated,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(currentPresent ? 'Mark as Absent' : 'Mark as Present'),
        content: Text(
          currentPresent
              ? 'Are you sure you want to mark this student as absent?'
              : 'Are you sure you want to mark this student as present?',
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

    final result = await widget.apiService.toggleManualAttendance(
      sessionId: sessionId,
      email: studentEmail,
      present: !currentPresent,
    );

    if (result['success'] == true) {
      _showMsg(currentPresent ? 'Marked as absent' : 'Marked as present');
      onUpdated();
    } else {
      _showMsg(result['message'] ?? 'Action failed');
    }
  }

  Future<void> _showAttendanceReport(Map<String, dynamic> session) async {
    final sessionId = int.tryParse(session['id']?.toString() ?? '') ?? 0;
    final Set<String> selectedEmails = {};
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (context, controller) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Attendance Report',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(),
              Expanded(
                child: StatefulBuilder(
                  builder: (context, setSheetState) {
                    return FutureBuilder<Map<String, dynamic>>(
                      future: widget.apiService.getSessionAttendanceReport(
                        sessionId: sessionId,
                        courseId: _courseId,
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snapshot.hasError ||
                            snapshot.data?['success'] != true) {
                          return Center(
                            child: Text(
                              snapshot.data?['message'] ??
                                  'Failed to load report',
                            ),
                          );
                        }
                        final report = snapshot.data!['report'] as List;
                        final total = report.length;
                        final attendedList = report
                            .where((r) => r['attended'] == true)
                            .toList();
                        final attended = attendedList.length;
                        return Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  _buildStatCard(
                                    'Total',
                                    total.toString(),
                                    Colors.blue,
                                  ),
                                  _buildStatCard(
                                    'Present',
                                    attended.toString(),
                                    Colors.green,
                                  ),
                                  _buildStatCard(
                                    'Absent',
                                    (total - attended).toString(),
                                    Colors.red,
                                  ),
                                ],
                              ),
                            ),
                            if (selectedEmails.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  12,
                                ),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(100),
                                      border: Border.all(
                                        color: Colors.blue.shade100,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: Transform.scale(
                                            scale: 0.85,
                                            child: Checkbox(
                                              value:
                                                  selectedEmails.length ==
                                                  report.length,
                                              activeColor: Colors.blue,
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              onChanged: (val) {
                                                setSheetState(() {
                                                  if (val == true) {
                                                    selectedEmails.addAll(
                                                      report.map(
                                                        (e) =>
                                                            (e['email'] ?? '')
                                                                .toString()
                                                                .trim(),
                                                      ),
                                                    );
                                                  } else {
                                                    selectedEmails.clear();
                                                  }
                                                });
                                              },
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${selectedEmails.length} selected',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w500,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        // Present Icon (Tick icon)
                                        _buildCircleAction(
                                          icon: Icons.check_circle_outline,
                                          color: Colors.green,
                                          tooltip: 'Mark Present',
                                          onPressed: () async {
                                            final ok = await showDialog<bool>(
                                              context: context,
                                              builder: (context) => AlertDialog(
                                                title: const Text(
                                                  'Mark as Present',
                                                ),
                                                content: Text(
                                                  'Mark ${selectedEmails.length} selected students as present?',
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          context,
                                                          false,
                                                        ),
                                                    child: const Text('Cancel'),
                                                  ),
                                                  ElevatedButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          context,
                                                          true,
                                                        ),
                                                    child: const Text(
                                                      'Confirm',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (ok != true) return;

                                            for (final email
                                                in selectedEmails) {
                                              final student = report.firstWhere(
                                                (e) =>
                                                    (e['email'] ?? '')
                                                        .toString()
                                                        .trim() ==
                                                    email,
                                                orElse: () => {},
                                              );
                                              if (student['attended'] == true)
                                                continue;

                                              await widget.apiService
                                                  .toggleManualAttendance(
                                                    sessionId: sessionId,
                                                    email: email,
                                                    present: true,
                                                  );
                                            }
                                            setSheetState(() {
                                              selectedEmails.clear();
                                            });
                                            _showMsg('Batch update completed');
                                          },
                                        ),
                                        // Absent Icon (Cross icon)
                                        _buildCircleAction(
                                          icon: Icons.cancel_outlined,
                                          color: Colors.red,
                                          tooltip: 'Mark Absent',
                                          onPressed: () async {
                                            final ok = await showDialog<bool>(
                                              context: context,
                                              builder: (context) => AlertDialog(
                                                title: const Text(
                                                  'Mark as Absent',
                                                ),
                                                content: Text(
                                                  'Mark ${selectedEmails.length} selected students as absent?',
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          context,
                                                          false,
                                                        ),
                                                    child: const Text('Cancel'),
                                                  ),
                                                  ElevatedButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          context,
                                                          true,
                                                        ),
                                                    child: const Text(
                                                      'Confirm',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (ok != true) return;

                                            for (final email
                                                in selectedEmails) {
                                              final student = report.firstWhere(
                                                (e) =>
                                                    (e['email'] ?? '')
                                                        .toString()
                                                        .trim() ==
                                                    email,
                                                orElse: () => {},
                                              );
                                              if (student['attended'] == false)
                                                continue;

                                              await widget.apiService
                                                  .toggleManualAttendance(
                                                    sessionId: sessionId,
                                                    email: email,
                                                    present: false,
                                                  );
                                            }
                                            setSheetState(() {
                                              selectedEmails.clear();
                                            });
                                            _showMsg('Batch update completed');
                                          },
                                        ),
                                        // Close Icon
                                        _buildCircleAction(
                                          icon: Icons.close,
                                          color: Colors.grey.shade600,
                                          tooltip: 'Close',
                                          onPressed: () {
                                            setSheetState(() {
                                              selectedEmails.clear();
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            Expanded(
                              child: ListView.builder(
                                controller: controller,
                                itemCount: report.length,
                                itemBuilder: (context, index) {
                                  final r = report[index];
                                  final hasAttended = r['attended'] == true;
                                  final isBlocked =
                                      ((r['is_blocked'] ?? 0).toString() ==
                                      '1');
                                  final studentEmail = (r['email'] ?? '')
                                      .toString();
                                  final isSelected = selectedEmails.contains(
                                    studentEmail,
                                  );
                                  return AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? Colors.blue.withOpacity(0.1)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isSelected
                                            ? Colors.blue.withOpacity(0.4)
                                            : Colors.transparent,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: ListTile(
                                      onLongPress: () {
                                        setSheetState(() {
                                          if (isSelected) {
                                            selectedEmails.remove(studentEmail);
                                          } else {
                                            selectedEmails.add(studentEmail);
                                          }
                                        });
                                      },
                                      onTap: selectedEmails.isNotEmpty
                                          ? () {
                                              setSheetState(() {
                                                if (isSelected) {
                                                  selectedEmails.remove(
                                                    studentEmail,
                                                  );
                                                } else {
                                                  selectedEmails.add(
                                                    studentEmail,
                                                  );
                                                }
                                              });
                                            }
                                          : null,
                                      leading: Stack(
                                        children: [
                                          CircleAvatar(
                                            backgroundImage:
                                                _studentProfileImageUrlByEmail
                                                    .containsKey(
                                                      studentEmail
                                                          .trim()
                                                          .toLowerCase(),
                                                    )
                                                ? NetworkImage(
                                                    _studentProfileImageUrlByEmail[studentEmail
                                                        .trim()
                                                        .toLowerCase()]!,
                                                  )
                                                : null,
                                            backgroundColor: hasAttended
                                                ? Colors.green.withOpacity(0.1)
                                                : Colors.red.withOpacity(0.1),
                                            child:
                                                !_studentProfileImageUrlByEmail
                                                    .containsKey(
                                                      studentEmail
                                                          .trim()
                                                          .toLowerCase(),
                                                    )
                                                ? Text(
                                                    _studentInitialsFromName(
                                                      r['name'] ?? '',
                                                    ),
                                                    style: TextStyle(
                                                      color: hasAttended
                                                          ? Colors.green
                                                          : Colors.red,
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  )
                                                : null,
                                          ),
                                          Positioned(
                                            right: 0,
                                            bottom: 0,
                                            child: Container(
                                              padding: const EdgeInsets.all(1),
                                              decoration: const BoxDecoration(
                                                color: Colors.white,
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                hasAttended
                                                    ? Icons.check_circle
                                                    : Icons.cancel,
                                                size: 14,
                                                color: hasAttended
                                                    ? Colors.green
                                                    : Colors.red,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      title: Text(
                                        r['name'] ?? '',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      subtitle: Text(studentEmail),
                                      trailing: isBlocked
                                          ? const Text(
                                              'BLOCKED',
                                              style: TextStyle(
                                                color: Colors.red,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 10,
                                              ),
                                            )
                                          : Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.end,
                                                  children: [
                                                    Text(
                                                      hasAttended
                                                          ? 'PRESENT'
                                                          : 'ABSENT',
                                                      style: TextStyle(
                                                        color: hasAttended
                                                            ? Colors.green
                                                            : Colors.red,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 10,
                                                      ),
                                                    ),
                                                    if (hasAttended) ...[
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        _formatMarkedTime(
                                                          r['time'],
                                                        ),
                                                        style: TextStyle(
                                                          color:
                                                              Colors.grey[600],
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                                if (selectedEmails.isEmpty) ...[
                                                  const SizedBox(width: 6),
                                                  IconButton(
                                                    onPressed:
                                                        studentEmail.isEmpty
                                                        ? null
                                                        : () =>
                                                              _toggleAttendanceFromReport(
                                                                sessionId:
                                                                    sessionId,
                                                                studentEmail:
                                                                    studentEmail,
                                                                currentPresent:
                                                                    hasAttended,
                                                                onUpdated: () {
                                                                  setSheetState(
                                                                    () {},
                                                                  );
                                                                },
                                                              ),
                                                    icon: Icon(
                                                      hasAttended
                                                          ? Icons
                                                                .remove_circle_outline
                                                          : Icons
                                                                .check_circle_outline,
                                                      color: hasAttended
                                                          ? Colors.red
                                                          : Colors.green,
                                                      size: 20,
                                                    ),
                                                    tooltip: hasAttended
                                                        ? 'Mark Absent'
                                                        : 'Mark Present',
                                                  ),
                                                ],
                                              ],
                                            ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildCircleAction({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    String? tooltip,
  }) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, color: color, size: 20),
        onPressed: onPressed,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      ),
    );
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadStudents(), _loadAttendanceSessions()]);
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _loadStudents() async {
    setState(() => _loadingStudents = true);
    final result = await widget.apiService.getBatchStudents(_courseId);
    if (!mounted) return;
    if (result['success'] == true) {
      final rows = (result['students'] as List? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      final avatarMap = await _loadStudentProfileImages(rows);
      if (!mounted) return;
      setState(() {
        _students = rows;
        _studentProfileImageUrlByEmail = avatarMap;
      });
    }
    setState(() => _loadingStudents = false);
  }

  String _sanitizeStudentEmail(String email) {
    return email.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  }

  String _studentInitialsFromName(String name) {
    final normalized = name.trim();
    if (normalized.isEmpty) return '';
    final parts = normalized
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1) {
      final one = parts.first;
      return one.length >= 2
          ? one.substring(0, 2).toUpperCase()
          : one.substring(0, 1).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  String _studentImageUrlFromFileId(String fileId) {
    return '$appwriteEndpoint/storage/buckets/$materialsBucketId/files/$fileId/view?project=$appwriteProjectId';
  }

  Future<Map<String, String>> _loadStudentProfileImages(
    List<Map<String, dynamic>> students,
  ) async {
    final emailToPrefix = <String, String>{};
    for (final student in students) {
      final email = (student['email'] ?? '').toString().trim().toLowerCase();
      if (email.isEmpty) continue;
      emailToPrefix[email] =
          'student_profile__${_sanitizeStudentEmail(email)}__';
    }
    if (emailToPrefix.isEmpty) return <String, String>{};

    try {
      final files = await appwriteStorage.listFiles(
        bucketId: materialsBucketId,
        queries: [Query.limit(500)],
      );

      final latestFileByEmail = <String, dynamic>{};
      for (final file in files.files) {
        for (final entry in emailToPrefix.entries) {
          final email = entry.key;
          final prefix = entry.value;
          if (!file.name.startsWith(prefix)) continue;
          final existing = latestFileByEmail[email];
          if (existing == null ||
              file.$createdAt.compareTo(existing.$createdAt) > 0) {
            latestFileByEmail[email] = file;
          }
          break;
        }
      }

      final urls = <String, String>{};
      latestFileByEmail.forEach((email, file) {
        urls[email] = _studentImageUrlFromFileId(file.$id);
      });
      return urls;
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<void> _loadAttendanceSessions() async {
    setState(() => _loadingAttendance = true);
    final result = await widget.apiService.getAttendanceSessions(_courseId);
    if (!mounted) return;
    if (result['success'] == true) {
      final rows = (result['sessions'] as List? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      setState(() => _attendanceSessions = rows);
    }
    setState(() => _loadingAttendance = false);
  }

  Future<void> _showAttendanceDialog({Map<String, dynamic>? session}) async {
    final isEdit = session != null;
    final deviceNow = DateTime.now();
    DateTime? selectedDate;
    TimeOfDay? selectedStartTime;
    TimeOfDay? selectedEndTime;
    if (isEdit) {
      try {
        final st = DateTime.parse(session['session_date']);
        final en = DateTime.parse(session['session_end']);
        selectedDate = DateTime(st.year, st.month, st.day);
        selectedStartTime = TimeOfDay.fromDateTime(st);
        selectedEndTime = TimeOfDay.fromDateTime(en);
      } catch (_) {}
    } else {
      selectedDate = DateTime(deviceNow.year, deviceNow.month, deviceNow.day);
      selectedStartTime = TimeOfDay.fromDateTime(deviceNow);
      selectedEndTime = TimeOfDay.fromDateTime(
        deviceNow.add(const Duration(hours: 1)),
      );
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          String displayDate = "Select Date";
          if (selectedDate != null) {
            displayDate =
                "${selectedDate!.year}-${selectedDate!.month.toString().padLeft(2, '0')}-${selectedDate!.day.toString().padLeft(2, '0')}";
          }
          String formatTime(TimeOfDay? tod) {
            if (tod == null) return "Select Time";
            final hourNum = tod.hourOfPeriod == 0 ? 12 : tod.hourOfPeriod;
            final periodStr = tod.period == DayPeriod.am ? 'AM' : 'PM';
            return "${hourNum.toString().padLeft(2, '0')}:${tod.minute.toString().padLeft(2, '0')} $periodStr";
          }

          return AlertDialog(
            title: Text(isEdit ? 'Edit Attendance' : 'Get Attendance'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                ListTile(
                  title: const Text('Date'),
                  subtitle: Text(displayDate),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      // Use deviceNow so the green highlight moves at YOUR midnight
                      initialDate: selectedDate ?? deviceNow,
                      firstDate: isEdit
                          ? deviceNow.subtract(const Duration(days: 30))
                          : deviceNow,
                      lastDate: deviceNow.add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setDialogState(() => selectedDate = picked);
                    }
                  },
                ),
                ListTile(
                  title: const Text('Start Time'),
                  subtitle: Text(formatTime(selectedStartTime)),
                  trailing: const Icon(Icons.access_time),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime:
                          selectedStartTime ??
                          TimeOfDay.fromDateTime(deviceNow),
                    );
                    if (picked != null) {
                      setDialogState(() => selectedStartTime = picked);
                    }
                  },
                ),
                ListTile(
                  title: const Text('End Time'),
                  subtitle: Text(formatTime(selectedEndTime)),
                  trailing: const Icon(Icons.access_time_filled),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime:
                          selectedEndTime ??
                          TimeOfDay.fromDateTime(
                            deviceNow.add(const Duration(hours: 1)),
                          ),
                    );
                    if (picked != null) {
                      setDialogState(() => selectedEndTime = picked);
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(isEdit ? 'Save Changes' : 'Create'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    if (selectedDate == null ||
        selectedStartTime == null ||
        selectedEndTime == null) {
      _showMsg('Please select date, start time, and end time');
      return;
    }
    final startDT = DateTime(
      selectedDate!.year,
      selectedDate!.month,
      selectedDate!.day,
      selectedStartTime!.hour,
      selectedStartTime!.minute,
    );
    final endDT = DateTime(
      selectedDate!.year,
      selectedDate!.month,
      selectedDate!.day,
      selectedEndTime!.hour,
      selectedEndTime!.minute,
    );
    final normalizedEndDT = !endDT.isAfter(startDT)
        ? endDT.add(const Duration(days: 1))
        : endDT;
    // STRICT VALIDATION for CREATE: cannot select past
    if (!isEdit && startDT.isBefore(deviceNow)) {
      _showMsg('Error: Start time cannot be in the past');
      return;
    }
    final startStr =
        "${startDT.year}-${startDT.month.toString().padLeft(2, '0')}-${startDT.day.toString().padLeft(2, '0')} ${startDT.hour.toString().padLeft(2, '0')}:${startDT.minute.toString().padLeft(2, '0')}:00";
    final endStr =
        "${normalizedEndDT.year}-${normalizedEndDT.month.toString().padLeft(2, '0')}-${normalizedEndDT.day.toString().padLeft(2, '0')} ${normalizedEndDT.hour.toString().padLeft(2, '0')}:${normalizedEndDT.minute.toString().padLeft(2, '0')}:00";
    Map<String, dynamic> result;
    if (isEdit) {
      result = await widget.apiService.updateAttendanceSession(
        id: int.tryParse(session['id'].toString()) ?? 0,
        sessionDate: startStr,
        sessionEnd: endStr,
      );
    } else {
      result = await widget.apiService.createAttendanceSession(
        courseId: _courseId,
        teacherEmail: widget.teacherEmail,
        sessionDate: startStr,
        sessionEnd: endStr,
      );
    }
    _showMsg(
      result['message'] ??
          (result['success'] == true
              ? (isEdit ? 'Session Updated' : 'Session Created')
              : 'Failed'),
    );
    if (result['success'] == true) {
      _loadAttendanceSessions();
    }
  }

  Future<void> _showGetAttendanceDialog() => _showAttendanceDialog();

  Future<void> _showStudentAttendanceOverview() async {
    setState(() {
      _showStudentDetails = true;
      _studentOverviewFuture ??= widget.apiService.getCourseAttendanceOverview(
        _courseId,
      );
    });
  }

  Future<void> _refreshStudentAttendanceOverview() async {
    setState(() {
      _studentOverviewFuture = widget.apiService.getCourseAttendanceOverview(
        _courseId,
      );
    });
    await _studentOverviewFuture;
  }

  Widget _buildStudentAttendanceOverviewInline() {
    final future =
        _studentOverviewFuture ??
        widget.apiService.getCourseAttendanceOverview(_courseId);
    _studentOverviewFuture = future;

    return FutureBuilder<Map<String, dynamic>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError || snapshot.data?['success'] != true) {
          return RefreshIndicator(
            onRefresh: _refreshStudentAttendanceOverview,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 220),
                Center(
                  child: Text(
                    snapshot.data?['message'] ??
                        'Failed to load student details',
                  ),
                ),
              ],
            ),
          );
        }

        final data = snapshot.data ?? {};
        final totalSessions =
            int.tryParse((data['total_sessions'] ?? 0).toString()) ?? 0;
        final overview = (data['overview'] as List? ?? [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();

        return RefreshIndicator(
          onRefresh: _refreshStudentAttendanceOverview,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
            itemCount: overview.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildStatCard(
                    'Total Sessions',
                    totalSessions.toString(),
                    Colors.blue,
                  ),
                );
              }

              final row = overview[index - 1];
              final present =
                  int.tryParse((row['total_present'] ?? 0).toString()) ?? 0;
              final absent =
                  int.tryParse((row['total_absent'] ?? 0).toString()) ?? 0;
              final percentage =
                  int.tryParse((row['score_percentage'] ?? 0).toString()) ?? 0;
              final isBlocked = (row['is_blocked']?.toString() ?? '0') == '1';

              final percentColor = percentage >= 75
                  ? Colors.green
                  : (percentage >= 60 ? Colors.orange : Colors.red);

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (row['name'] ?? '').toString(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  (row['email'] ?? '').toString(),
                                  style: const TextStyle(color: Colors.black54),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Present: $present',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Absent: $absent',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 14),
                          Text(
                            '$percentage%',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: percentColor,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      if (isBlocked)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            'BLOCKED',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildAttendance() {
    if (_loadingAttendance) {
      return const Center(child: CircularProgressIndicator());
    }
    final deviceNow = DateTime.now();
    final hasHistorySessions = _attendanceSessions.any((session) {
      try {
        final end = DateTime.parse((session['session_end'] ?? '').toString());
        return deviceNow.isAfter(end) || deviceNow.isAtSameMomentAs(end);
      } catch (_) {
        return false;
      }
    });
    // Filter sessions:
    // Active if now < session_end
    // History if now >= session_end
    final filtered = _attendanceSessions.where((s) {
      try {
        final endStr = s['session_end'] ?? '';
        final end = DateTime.parse(endStr);
        if (_showAttendanceHistory) {
          return deviceNow.isAfter(end) || deviceNow.isAtSameMomentAs(end);
        } else {
          return deviceNow.isBefore(end);
        }
      } catch (_) {
        return false;
      }
    }).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _showGetAttendanceDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('Get Attendance'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 45),
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => setState(() {
                        _showStudentDetails = false;
                        _showAttendanceHistory = !_showAttendanceHistory;
                      }),
                      icon: Icon(
                        _showAttendanceHistory
                            ? Icons.dashboard
                            : Icons.history,
                      ),
                      label: Text(
                        _showAttendanceHistory ? 'Active' : 'History',
                      ),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 45),
                        backgroundColor: _showAttendanceHistory
                            ? Colors.blueAccent
                            : Colors.blueGrey,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _showStudentAttendanceOverview,
                      icon: const Icon(Icons.people_alt_outlined),
                      label: const Text('Student Details'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 45),
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: hasHistorySessions
                          ? _confirmDownloadAttendanceReport
                          : null,
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Download'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 45),
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.deepPurple.shade200,
                        disabledForegroundColor: Colors.white70,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _showStudentDetails
              ? _buildStudentAttendanceOverviewInline()
              : RefreshIndicator(
                  onRefresh: _loadAttendanceSessions,
                  child: filtered.isEmpty
                      ? ListView(
                          children: [
                            const SizedBox(height: 100),
                            Center(
                              child: Text(
                                _showAttendanceHistory
                                    ? 'No history available'
                                    : 'No active sessions scheduled',
                              ),
                            ),
                          ],
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                childAspectRatio: 0.8,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                              ),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final s = filtered[index];
                            final start = s['session_date'] ?? '';
                            final end = s['session_end'] ?? '';
                            bool isStarted = false;
                            String displayDate = "";
                            String displayTime = "";
                            String durationText = "";
                            String remainingText = "";
                            try {
                              final st = DateTime.parse(start);
                              final en = DateTime.parse(end);
                              isStarted =
                                  deviceNow.isAfter(st) ||
                                  deviceNow.isAtSameMomentAs(st);
                              displayDate =
                                  "${st.year}-${st.month.toString().padLeft(2, '0')}-${st.day.toString().padLeft(2, '0')}";
                              String fmt(DateTime d) {
                                final h = d.hour > 12
                                    ? d.hour - 12
                                    : (d.hour == 0 ? 12 : d.hour);
                                final p = d.hour >= 12 ? 'PM' : 'AM';
                                return "${h.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} $p";
                              }

                              displayTime = "${fmt(st)} - ${fmt(en)}";

                              durationText =
                                  'Duration: ${_formatDuration(en.difference(st))}';
                              if (_showAttendanceHistory) {
                                remainingText = 'Status: Ended';
                              } else if (deviceNow.isBefore(st)) {
                                remainingText =
                                    'Starts in: ${_formatDuration(st.difference(deviceNow), withSeconds: true)}';
                              } else if (deviceNow.isBefore(en) ||
                                  deviceNow.isAtSameMomentAs(en)) {
                                remainingText =
                                    'Remaining: ${_formatDuration(en.difference(deviceNow), withSeconds: true)}';
                              } else {
                                remainingText = 'Status: Ended';
                              }
                            } catch (_) {}
                            final isPrivate = s['is_private'].toString() == '1';
                            final statusColor = _showAttendanceHistory
                                ? Colors.blueGrey
                                : (isPrivate || !isStarted
                                      ? Colors.red
                                      : Colors.green);
                            final bgColor = statusColor.withOpacity(0.05);
                            String statusText = "";
                            if (_showAttendanceHistory) {
                              statusText = "History";
                            } else if (isPrivate) {
                              statusText = "Private";
                            } else if (!isStarted) {
                              statusText = "Scheduled";
                            } else {
                              statusText = "Active";
                            }
                            return InkWell(
                              onTap: () => _showAttendanceReport(s),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: statusColor.withOpacity(0.3),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 5,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(height: 5, color: statusColor),
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          10,
                                          8,
                                          4,
                                          2,
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 6,
                                                          vertical: 2,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: statusColor
                                                          .withOpacity(0.1),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            4,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      statusText.toUpperCase(),
                                                      style: TextStyle(
                                                        color: statusColor,
                                                        fontSize: 9,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        letterSpacing: 0.5,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    s['course_code']
                                                            ?.toString() ??
                                                        '',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: statusColor,
                                                      fontSize: 16,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            PopupMenuButton(
                                              icon: const Icon(
                                                Icons.more_vert,
                                                size: 20,
                                              ),
                                              onSelected: (val) async {
                                                if (val == 'public') {
                                                  _publishSession(s);
                                                } else if (val == 'private') {
                                                  _privateSession(s);
                                                } else if (val == 'stop') {
                                                  _stopAttendanceSession(s);
                                                } else if (val == 'edit') {
                                                  _showAttendanceDialog(
                                                    session: s,
                                                  );
                                                } else if (val == 'delete') {
                                                  final sessionId =
                                                      int.tryParse(
                                                        s['id']?.toString() ??
                                                            '',
                                                      );
                                                  if (sessionId == null) return;
                                                  final confirm = await showDialog<bool>(
                                                    context: context,
                                                    builder: (context) => AlertDialog(
                                                      title: const Text(
                                                        'Delete Session',
                                                      ),
                                                      content: const Text(
                                                        'Are you sure you want to delete this session?',
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                context,
                                                                false,
                                                              ),
                                                          child: const Text(
                                                            'No',
                                                          ),
                                                        ),
                                                        ElevatedButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                context,
                                                                true,
                                                              ),
                                                          style:
                                                              ElevatedButton.styleFrom(
                                                                backgroundColor:
                                                                    Colors.red,
                                                              ),
                                                          child: const Text(
                                                            'Delete',
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                  if (confirm == true) {
                                                    final result = await widget
                                                        .apiService
                                                        .deleteAttendanceSession(
                                                          sessionId,
                                                        );
                                                    _showMsg(
                                                      result['message'] ??
                                                          'Deleted',
                                                    );
                                                    _loadAttendanceSessions();
                                                  }
                                                }
                                              },
                                              itemBuilder: (context) => [
                                                if ((!isStarted &&
                                                        !_showAttendanceHistory) ||
                                                    isPrivate)
                                                  const PopupMenuItem(
                                                    value: 'public',
                                                    child: Row(
                                                      children: [
                                                        Icon(
                                                          Icons.public,
                                                          size: 18,
                                                          color: Colors.green,
                                                        ),
                                                        SizedBox(width: 8),
                                                        Text('Public'),
                                                      ],
                                                    ),
                                                  ),
                                                if (isStarted &&
                                                    !_showAttendanceHistory &&
                                                    !isPrivate)
                                                  const PopupMenuItem(
                                                    value: 'private',
                                                    child: Row(
                                                      children: [
                                                        Icon(
                                                          Icons.lock_outline,
                                                          size: 18,
                                                          color: Colors.red,
                                                        ),
                                                        SizedBox(width: 8),
                                                        Text('Private'),
                                                      ],
                                                    ),
                                                  ),
                                                if (isStarted &&
                                                    !_showAttendanceHistory)
                                                  const PopupMenuItem(
                                                    value: 'stop',
                                                    child: Row(
                                                      children: [
                                                        Icon(
                                                          Icons
                                                              .stop_circle_outlined,
                                                          size: 18,
                                                          color: Colors.red,
                                                        ),
                                                        SizedBox(width: 8),
                                                        Text('Stop Attendance'),
                                                      ],
                                                    ),
                                                  ),
                                                const PopupMenuItem(
                                                  value: 'edit',
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        Icons.edit,
                                                        size: 18,
                                                        color: Colors.orange,
                                                      ),
                                                      SizedBox(width: 8),
                                                      Text('Edit'),
                                                    ],
                                                  ),
                                                ),
                                                const PopupMenuItem(
                                                  value: 'delete',
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        Icons.delete,
                                                        size: 18,
                                                        color: Colors.red,
                                                      ),
                                                      SizedBox(width: 8),
                                                      Text('Delete'),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                          ),
                                          child: Align(
                                            alignment: const Alignment(
                                              -1.0,
                                              0.15,
                                            ),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                _buildLabelRow(
                                                  'Teacher:',
                                                  s['teacher_name'] ?? "",
                                                  color: statusColor,
                                                ),
                                                const SizedBox(height: 10),
                                                _buildLabelRow(
                                                  'Faculty:',
                                                  s['faculty_name'] ?? "",
                                                  color: statusColor,
                                                ),
                                                const SizedBox(height: 10),
                                                _buildLabelRow(
                                                  'Session:',
                                                  s['session'] ?? "",
                                                  color: statusColor,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      Container(
                                        width: double.infinity,
                                        margin: const EdgeInsets.all(8),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                          horizontal: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: bgColor,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Column(
                                          children: [
                                            Text(
                                              displayDate,
                                              style: TextStyle(
                                                color: statusColor,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              displayTime,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: statusColor.withOpacity(
                                                  0.9,
                                                ),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                              ),
                                            ),
                                            if (durationText.isNotEmpty) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                durationText,
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: statusColor
                                                      .withOpacity(0.9),
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                            if (remainingText.isNotEmpty &&
                                                !isPrivate) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                remainingText,
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: statusColor,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
        ),
      ],
    );
  }

  Widget _buildLabelRow(String label, String text, {Color? color}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: color ?? Colors.blueGrey,
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Colors.black87, fontSize: 15),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Future<void> _unenrollStudent(String studentEmail) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Student'),
        content: const Text('Are you sure you want to remove this student?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final result = await widget.apiService.unEnrollCourse(
      email: studentEmail,
      courseId: _courseId,
    );
    if (!mounted) return;
    if (result['success'] == true) {
      _showMsg('Student removed successfully');
      await _loadStudents();
    } else {
      _showMsg(result['message'] ?? 'Action failed');
    }
  }

  Future<void> _enrollStudent(String studentEmail) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enroll Student'),
        content: const Text('Do you want to enroll this student?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Enroll'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final result = await widget.apiService.enrollCourse(
      email: studentEmail,
      courseId: _courseId,
    );
    if (!mounted) return;
    if (result['success'] == true) {
      _showMsg('Student enrolled successfully');
      await _loadStudents();
    } else {
      _showMsg(result['message'] ?? 'Action failed');
    }
  }

  Future<void> _toggleBlockStudent({
    required String studentEmail,
    required bool shouldBlock,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(shouldBlock ? 'Block Student' : 'Unblock Student'),
        content: Text(
          shouldBlock
              ? 'This student will be blocked from this course and cannot access it. Continue?'
              : 'Restore this student\'s access to this course?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: shouldBlock ? Colors.red : Colors.green,
            ),
            child: Text(shouldBlock ? 'Block' : 'Unblock'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final result = await widget.apiService.toggleStudentBlock(
      courseId: _courseId,
      email: studentEmail,
      block: shouldBlock,
    );

    if (!mounted) return;
    if (result['success'] == true) {
      _showMsg(
        shouldBlock
            ? 'Student blocked from this course'
            : 'Student unblocked successfully',
      );
      await _loadStudents();
    } else {
      _showMsg(result['message'] ?? 'Action failed');
    }
  }

  Widget _buildStudents() {
    if (_loadingStudents) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_students.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadStudents,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Center(child: Text('No students found in this batch.')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadStudents,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _students.length,
        itemBuilder: (context, index) {
          final s = _students[index];
          final studentEmail = (s['email'] ?? '').toString();
          final studentImageUrl =
              _studentProfileImageUrlByEmail[studentEmail
                  .trim()
                  .toLowerCase()] ??
              '';
          final studentName = (s['name'] ?? '').toString();
          final studentInitials = _studentInitialsFromName(studentName);
          final studentPhone = (s['phone'] ?? '').toString();
          final isEnrolled = ((s['is_enrolled'] ?? 0).toString() == '1');
          final isBlocked = ((s['is_blocked'] ?? 0).toString() == '1');
          return Container(
            margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.green.withOpacity(0.12),
                  backgroundImage: studentImageUrl.isNotEmpty
                      ? NetworkImage(studentImageUrl)
                      : null,
                  child: studentImageUrl.isNotEmpty
                      ? null
                      : (studentInitials.isNotEmpty
                            ? Text(
                                studentInitials,
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.w700,
                                ),
                              )
                            : const Icon(Icons.person, color: Colors.green)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        studentName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        studentEmail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        studentPhone,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15),
                      ),
                    ],
                  ),
                ),
                if (isBlocked)
                  Container(
                    margin: const EdgeInsets.only(right: 4, top: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.withOpacity(0.35)),
                    ),
                    child: const Text(
                      'Blocked',
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        isBlocked ? Icons.lock_open : Icons.block,
                        color: isBlocked ? Colors.orange : Colors.red,
                      ),
                      tooltip: isBlocked ? 'Unblock Student' : 'Block Student',
                      onPressed: () => _toggleBlockStudent(
                        studentEmail: studentEmail,
                        shouldBlock: !isBlocked,
                      ),
                    ),
                    if (!isBlocked)
                      IconButton(
                        icon: Icon(
                          isEnrolled
                              ? Icons.remove_circle_outline
                              : Icons.add_circle_outline,
                          color: isEnrolled ? Colors.red : Colors.green,
                        ),
                        tooltip: isEnrolled
                            ? 'Remove Student'
                            : 'Enroll Student',
                        onPressed: () {
                          if (isEnrolled) {
                            _unenrollStudent(studentEmail);
                          } else {
                            _enrollStudent(studentEmail);
                          }
                        },
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _publishSession(Map<String, dynamic> session) async {
    final deviceNow = DateTime.now();
    final fmtNow =
        "${deviceNow.year}-${deviceNow.month.toString().padLeft(2, '0')}-${deviceNow.day.toString().padLeft(2, '0')} ${deviceNow.hour.toString().padLeft(2, '0')}:${deviceNow.minute.toString().padLeft(2, '0')}:00";
    final result = await widget.apiService.updateAttendanceSession(
      id: int.tryParse(session['id'].toString()) ?? 0,
      sessionDate: fmtNow,
      sessionEnd: session['session_end'].toString(),
      isPrivate: 0,
    );
    _showMsg(result['message'] ?? 'Session published');
    if (result['success'] == true) {
      _loadAttendanceSessions();
    }
  }

  Future<void> _privateSession(Map<String, dynamic> session) async {
    final result = await widget.apiService.updateAttendanceSession(
      id: int.tryParse(session['id'].toString()) ?? 0,
      sessionDate: session['session_date'].toString(),
      sessionEnd: session['session_end'].toString(),
      isPrivate: 1,
    );
    _showMsg(result['message'] ?? 'Session made private');
    if (result['success'] == true) {
      _loadAttendanceSessions();
    }
  }

  Future<void> _stopAttendanceSession(Map<String, dynamic> session) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop Attendance'),
        content: const Text(
          'Stop attendance now for this session? It will move to history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Stop'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final deviceNow = DateTime.now();
    final stoppedAt =
        "${deviceNow.year}-${deviceNow.month.toString().padLeft(2, '0')}-${deviceNow.day.toString().padLeft(2, '0')} ${deviceNow.hour.toString().padLeft(2, '0')}:${deviceNow.minute.toString().padLeft(2, '0')}:${deviceNow.second.toString().padLeft(2, '0')}";

    final result = await widget.apiService.updateAttendanceSession(
      id: int.tryParse(session['id'].toString()) ?? 0,
      sessionDate: session['session_date'].toString(),
      sessionEnd: stoppedAt,
      isPrivate: 1,
    );

    _showMsg(result['message'] ?? 'Attendance stopped');
    if (result['success'] == true) {
      await _loadAttendanceSessions();
      if (!mounted) return;
      setState(() {
        _showAttendanceHistory = true;
      });
    }
  }

  Future<void> _confirmDownloadAttendanceReport() async {
    final deviceNow = DateTime.now();
    final hasHistorySessions = _attendanceSessions.any((session) {
      try {
        final end = DateTime.parse((session['session_end'] ?? '').toString());
        return deviceNow.isAfter(end) || deviceNow.isAtSameMomentAs(end);
      } catch (_) {
        return false;
      }
    });

    if (!hasHistorySessions) {
      _showMsg('No history attendance available yet');
      return;
    }

    bool includeBlocked = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Download Attendance Report'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Do you want to download this course attendance report as PDF?',
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: includeBlocked,
                contentPadding: EdgeInsets.zero,
                title: const Text('Include blocked student details'),
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (value) {
                  setDialogState(() => includeBlocked = value ?? false);
                },
              ),
            ],
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
      ),
    );

    if (ok != true) return;
    await _downloadAttendanceReportPdf(includeBlocked: includeBlocked);
  }

  Future<void> _downloadAttendanceReportPdf({
    required bool includeBlocked,
  }) async {
    final result = await widget.apiService.getCourseAttendanceOverview(
      _courseId,
    );

    if (!mounted) return;
    if (result['success'] != true) {
      _showMsg(result['message'] ?? 'Failed to generate report');
      return;
    }

    final totalSessions =
        int.tryParse((result['total_sessions'] ?? 0).toString()) ?? 0;
    final rows = (result['overview'] as List? ?? [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();

    final filteredRows = includeBlocked
        ? rows
        : rows
              .where((row) => (row['is_blocked']?.toString() ?? '0') != '1')
              .toList();

    final now = DateTime.now();
    final generatedOn =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final courseCode = (widget.course['course_code'] ?? '').toString();
    final courseName = (widget.course['course_name'] ?? '').toString();
    final courseSession = (widget.course['session'] ?? '').toString();
    final faculty = (widget.course['faculty_name'] ?? '').toString();
    final teacher = (widget.course['teacher_name'] ?? widget.teacherEmail)
        .toString();

    final reportTable = <List<String>>[];
    for (int index = 0; index < filteredRows.length; index++) {
      final row = filteredRows[index];
      final present = int.tryParse((row['total_present'] ?? 0).toString()) ?? 0;
      final absent = int.tryParse((row['total_absent'] ?? 0).toString()) ?? 0;
      final percentage =
          int.tryParse((row['score_percentage'] ?? 0).toString()) ?? 0;

      reportTable.add([
        (row['name'] ?? '').toString(),
        (row['email'] ?? '').toString(),
        present.toString(),
        absent.toString(),
        '$percentage%',
      ]);
    }

    pw.MemoryImage? logoImage;
    try {
      final logoData = await rootBundle.load('img/pstu logo.png');
      logoImage = pw.MemoryImage(logoData.buffer.asUint8List());
    } catch (_) {}

    final pdfDoc = pw.Document();
    pdfDoc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(45, 35, 45, 35),
        build: (context) => [
          if (logoImage != null)
            pw.Center(
              child: pw.SizedBox(
                height: 90,
                width: 90,
                child: pw.Image(logoImage, fit: pw.BoxFit.contain),
              ),
            ),
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.Text(
              'Patuakhali Science and Technology University',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Center(
            child: pw.Text(
              'Attendance Overview Report',
              style: pw.TextStyle(
                fontSize: 16,
                decoration: pw.TextDecoration.underline,
              ),
            ),
          ),
          pw.SizedBox(height: 24),
          pw.Text(
            'Course: $courseCode - $courseName',
            style: const pw.TextStyle(fontSize: 12.5),
          ),
          pw.Text(
            'Teacher: $teacher',
            style: const pw.TextStyle(fontSize: 12.5),
          ),
          pw.Text(
            'Session: $courseSession',
            style: const pw.TextStyle(fontSize: 12.5),
          ),
          pw.Text(
            'Faculty: $faculty',
            style: const pw.TextStyle(fontSize: 12.5),
          ),
          pw.Text(
            'Total Past Sessions: $totalSessions',
            style: const pw.TextStyle(fontSize: 12.5),
          ),
          if (includeBlocked)
            pw.Text(
              'Included blocked students',
              style: const pw.TextStyle(fontSize: 11),
            ),
          pw.Text(
            'Generated on: $generatedOn',
            style: const pw.TextStyle(fontSize: 11),
          ),
          pw.SizedBox(height: 20),
          if (reportTable.isEmpty)
            pw.Text(
              includeBlocked
                  ? 'No student data available for this course.'
                  : 'No unblocked students available for this course.',
            )
          else
            pw.TableHelper.fromTextArray(
              headers: const [
                'Student Name',
                'Email',
                'Present',
                'Absent',
                'Percentage',
              ],
              data: reportTable,
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 11,
              ),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.white),
              cellAlignments: {
                2: pw.Alignment.center,
                3: pw.Alignment.center,
                4: pw.Alignment.center,
              },
              cellHeight: 26,
              cellStyle: const pw.TextStyle(fontSize: 10),
              border: pw.TableBorder.all(color: PdfColors.black, width: 0.8),
              headerAlignment: pw.Alignment.center,
            ),
        ],
      ),
    );

    final safeCode = courseCode.isEmpty ? 'course' : courseCode;
    final safeSession = courseSession.isEmpty ? 'session' : courseSession;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'Attendance_${safeCode}_${safeSession}_$timestamp.pdf';

    // Aggressively sanitize filename: keep only alphanumeric and dots
    final safeFileName = fileName.replaceAll(RegExp(r'[^\w\.]'), '_');

    try {
      final pdfBytes = await pdfDoc.save();

      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: safeFileName,
          bytes: pdfBytes,
          fileExtension: 'pdf',
          mimeType: MimeType.other,
        );
      } else {
        // Try direct save first
        try {
          final downloadsPath =
              await ExternalPath.getExternalStoragePublicDirectory(
                ExternalPath.DIRECTORY_DOWNLOAD,
              );
          final targetFile = File('$downloadsPath/$safeFileName');
          await targetFile.writeAsBytes(pdfBytes, flush: true);
        } catch (ioErr) {
          // Fallback to Folder Picker
          _showMsg('Please select a folder to save the report');
          String? selectedDirectory =
              await FilePicker.platform.getDirectoryPath();

          if (selectedDirectory != null) {
            final targetFile = File('$selectedDirectory/$safeFileName');
            await targetFile.writeAsBytes(pdfBytes, flush: true);
          } else {
            if (!mounted) return;
            _showMsg('Download cancelled.');
            return;
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      _showMsg('Failed to process report: $e');
      return;
    }

    if (!mounted) return;
    _showMsg('Attendance report downloaded');
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      initialIndex: 0,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
          title: Text(
            widget.course['course_name']?.toString() ?? 'Course Detail',
          ),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Attendance'),
              Tab(text: 'Discussion'),
              Tab(text: 'Assignments'),
              Tab(text: 'Materials'),
              Tab(text: 'Students'),
              Tab(text: 'Result'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildAttendance(),
            CourseDiscussionSection(
              courseId: _courseId,
              courseName: (widget.course['course_name'] ?? '').toString(),
              userEmail: widget.teacherEmail,
              userRole: 'teacher',
              userName: (widget.course['teacher_name'] ?? '').toString(),
              apiService: widget.apiService,
            ),
            TeacherAssignmentSection(
              courseId: _courseId,
              teacherEmail: widget.teacherEmail,
              teacherName: (widget.course['teacher_name'] ?? '').toString(),
              studentProfileImageUrlByEmail: _studentProfileImageUrlByEmail,
            ),
            CourseMaterialsSection(
              courseId: _courseId,
              courseScope: _courseScope,
              userEmail: widget.teacherEmail,
              userRole: 'teacher',
              canDeleteAny: true,
              canUpload: true,
              courseName: (widget.course['course_name'] ?? '').toString(),
            ),
            _buildStudents(),
            TeacherCourseResultSection(
              course: widget.course,
              teacherEmail: widget.teacherEmail,
              apiService: widget.apiService,
              courseId: _courseId,
              courseScope: _courseScope,
            ),
          ],
        ),
      ),
    );
  }
}
