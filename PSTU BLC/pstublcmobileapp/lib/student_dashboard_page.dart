import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dart_appwrite/dart_appwrite.dart';
import 'package:dart_appwrite/models.dart' as appwrite_models;
import 'package:external_path/external_path.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:pstublc/config/appwrite_storage.dart';
import 'package:pstublc/login_page.dart';
import 'package:pstublc/services/api_service.dart';
import 'package:pstublc/widgets/course_discussion_section.dart';
import 'package:pstublc/widgets/student_assignment_section.dart';
import 'package:pstublc/widgets/student_course_materials_section.dart';
import 'package:pstublc/widgets/delete_account_dialog.dart';

class _PickedProfileImage {
  final String? path;
  final Uint8List? bytes;
  final String? name;
  const _PickedProfileImage({this.path, this.bytes, this.name});
}

class StudentDashboardPage extends StatefulWidget {
  const StudentDashboardPage({super.key});
  @override
  State<StudentDashboardPage> createState() => _StudentDashboardPageState();
}

class _StudentDashboardPageState extends State<StudentDashboardPage> {
  final ApiService _apiService = ApiService();
  int _selectedTab = 0;
  bool _loadingCourses = false;
  bool _loadingProfile = false;
  bool _loadingResults = false;
  bool _resultSelectionMode = false;
  String _selectedStudentCourseFilter = 'all';
  String _selectedStudentEnrollmentFilter = 'all';
  String _selectedResultCourseFilter = 'all';
  String _email = '';
  List<Map<String, dynamic>> _courses = [];
  List<Map<String, dynamic>> _results = [];
  final Set<String> _selectedResultFileIds = <String>{};
  List<Map<String, dynamic>> _teachers = [];
  Map<String, String> _teacherProfileImageUrlByEmail = {};
  Map<String, dynamic> _profile = {};
  bool _loadingTeachers = false;
  bool _showProfilePassword = false;
  String _profileImageUrlState = '';
  String _profileImageFileId = '';
  bool _profileImageBusy = false;
  List<Map<String, dynamic>> _notifications = [];
  int _unreadCount = 0;
  bool _loadingNotifications = false;
  String _highlightedResultFileId = '';
  Timer? _resultHighlightTimer;
  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _resultHighlightTimer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final session = await _apiService.getSession();
    _email = session['email'] ?? '';

    if (_email.isEmpty) {
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (_) => false,
      );
      return;
    }

    // Set initial loading states to true before starting the parallel wait
    setState(() {
      _loadingCourses = true;
      _loadingProfile = true;
      _loadingResults = true;
    });

    try {
      await Future.wait([_loadCourses(), _loadProfile(), _loadResults()]);
    } catch (e) {
      debugPrint('Error in _init: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loadingCourses = false;
          _loadingProfile = false;
          _loadingResults = false;
        });
      }
    }

    // Start loading in background without blocking initial render
    _loadNotifications();
  }

  Future<void> _loadCourses() async {
    if (_email.isEmpty) return;
    setState(() => _loadingCourses = true);
    try {
      final result = await _apiService.getStudentCourses(_email);
      if (!mounted) return;
      if (result['success'] == true) {
        final rows = (result['courses'] as List? ?? [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        final keys = rows.map(_studentCourseKey).toSet();
        setState(() {
          _courses = rows;
          if (_selectedStudentCourseFilter != 'all' &&
              !keys.contains(_selectedStudentCourseFilter)) {
            _selectedStudentCourseFilter = 'all';
          }
        });
      } else {
        _showMsg(result['message'] ?? 'Failed to load courses');
      }
    } finally {
      if (mounted) setState(() => _loadingCourses = false);
    }
  }

  String _studentCourseKey(Map<String, dynamic> course) {
    final id = (course['course_id'] ?? '').toString().trim();
    if (id.isNotEmpty && id != '0') return id;
    final code = (course['course_code'] ?? '').toString().trim();
    final name = (course['course_name'] ?? '').toString().trim();
    return '$code|||$name';
  }

  String _studentCourseLabel(String key) {
    if (key == 'all') return 'All Courses';
    for (final course in _courses) {
      if (_studentCourseKey(course) == key) {
        final code = (course['course_code'] ?? '').toString().trim();
        final name = (course['course_name'] ?? '').toString().trim();
        if (code.isEmpty && name.isEmpty) return 'Unknown Course';
        if (code.isEmpty) return name;
        if (name.isEmpty) return code;
        return '$code ($name)';
      }
    }
    return key;
  }

  List<String> _studentCourseFilterKeys() {
    final keys = _courses.map(_studentCourseKey).toSet().toList()
      ..sort(
        (a, b) => _studentCourseLabel(a).compareTo(_studentCourseLabel(b)),
      );
    return ['all', ...keys];
  }

  bool _isStudentCourseEnrolled(Map<String, dynamic> course) {
    return (course['is_enrolled'] ?? 0).toString() == '1';
  }

  List<Map<String, dynamic>> _filteredStudentCourses() {
    return _courses.where((course) {
      final matchesCourse =
          _selectedStudentCourseFilter == 'all' ||
          _studentCourseKey(course) == _selectedStudentCourseFilter;

      final enrolled = _isStudentCourseEnrolled(course);
      final matchesEnrollment =
          _selectedStudentEnrollmentFilter == 'all' ||
          (_selectedStudentEnrollmentFilter == 'enrolled' && enrolled) ||
          (_selectedStudentEnrollmentFilter == 'unenrolled' && !enrolled);

      return matchesCourse && matchesEnrollment;
    }).toList();
  }

  Future<void> _loadProfile() async {
    if (_email.isEmpty) return;
    setState(() => _loadingProfile = true);
    try {
      final result = await _apiService.getProfile('student', _email);
      if (!mounted) return;
      if (result['success'] == true && result['data'] is Map) {
        setState(
          () => _profile = Map<String, dynamic>.from(result['data'] as Map),
        );
      } else {
        _showMsg(result['message'] ?? 'Failed to load profile');
      }
      await _loadProfileAvatarFromStorage();
    } finally {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  String _profileImagePrefix() {
    final safeEmail = _email.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '_',
    );
    return 'student_profile__${safeEmail}__';
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
      await _pickAndUploadProfileImage();
    } else if (action == 'delete') {
      await _deleteProfileImage();
    }
  }

  Future<void> _pickAndUploadProfileImage() async {
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

  Future<void> _loadResults() async {
    if (_email.isEmpty) return;
    setState(() => _loadingResults = true);
    try {
      final result = await appwriteStorage.listFiles(
        bucketId: materialsBucketId,
        queries: [Query.limit(300)],
      );
      if (!mounted) return;

      final email = _email.toLowerCase().trim();
      final rows =
          result.files
              .where((f) => f.name.startsWith('result_'))
              .map((f) => _mapResultFile(f))
              .where((r) => (r['student_email'] ?? '') == email)
              .where((r) => (r['result_is_private'] ?? false) != true)
              .toList()
            ..sort(
              (a, b) => (b['uploaded_at_raw'] ?? '').toString().compareTo(
                (a['uploaded_at_raw'] ?? '').toString(),
              ),
            );

      final scopes = rows
          .map((row) => (row['course_scope'] ?? '').toString())
          .where((scope) => scope.isNotEmpty)
          .toSet()
          .toList();
      if (scopes.isNotEmpty) {
        final metaResult = await _apiService.getCourseMetaByScopes(
          email: _email,
          scopes: scopes,
        );
        if (metaResult['success'] == true && metaResult['courses'] is List) {
          final List<Map<String, dynamic>> metaRows =
              (metaResult['courses'] as List)
                  .map((item) => Map<String, dynamic>.from(item as Map))
                  .toList();
          final Map<String, Map<String, dynamic>> byScope = {
            for (final row in metaRows) (row['scope'] ?? '').toString(): row,
          };

          for (var i = 0; i < rows.length; i++) {
            final scope = (rows[i]['course_scope'] ?? '').toString();
            final found = byScope[scope];
            if (found == null) continue;
            rows[i]['course_code'] = (found['course_code'] ?? '').toString();
            rows[i]['course_name'] = (found['course_name'] ?? '').toString();
            rows[i]['is_private'] =
                (found['is_private']?.toString() == '1') ||
                (found['is_private'] == true);
          }
        }
      }

      final availableCourseKeys = rows
          .map((row) => _resultCourseKey(row))
          .toSet();

      setState(() {
        _results = rows;
        if (_selectedResultCourseFilter != 'all' &&
            !availableCourseKeys.contains(_selectedResultCourseFilter)) {
          _selectedResultCourseFilter = 'all';
          _resultSelectionMode = false;
          _selectedResultFileIds.clear();
        }
      });
      _selectedResultFileIds.removeWhere(
        (id) => !_results.any((result) => (result['file_id'] ?? '') == id),
      );
    } catch (e) {
      _showMsg('Failed to load results');
      setState(() => _results = []);
    } finally {
      if (mounted) setState(() => _loadingResults = false);
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

  Map<String, dynamic> _courseMetaFromScope(String scope) {
    for (final course in _courses) {
      if (_courseScopeFromCourse(course) == scope) {
        return {
          'course_code': (course['course_code'] ?? '').toString(),
          'course_name': (course['course_name'] ?? '').toString(),
        };
      }
    }
    return {'course_code': '', 'course_name': ''};
  }

  String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    }
    return '$bytes B';
  }

  String _formatDateTimeWithAmPm(String raw) {
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

  Map<String, dynamic> _mapResultFile(appwrite_models.File file) {
    final storedName = file.name;
    final parts = storedName.split('__');

    String scope = '';
    String studentEmail = '';
    String originalName = storedName;
    bool resultIsPrivate = false;
    if (parts.length >= 4 && parts.first.startsWith('result_')) {
      scope = parts.first.replaceFirst('result_', '');
      studentEmail = parts[1].toLowerCase();
      final hasVisibilityToken =
          parts.length >= 5 &&
          (parts[2] == 'v_public' || parts[2] == 'v_private');
      resultIsPrivate = hasVisibilityToken && parts[2] == 'v_private';
      originalName = hasVisibilityToken
          ? parts.sublist(4).join('__')
          : parts.sublist(3).join('__');
    }

    final courseMeta = _courseMetaFromScope(scope);
    return {
      'file_id': file.$id,
      'file_name': originalName,
      'file_size': _formatSize(file.sizeOriginal),
      'uploaded_at': _formatDateTimeWithAmPm(file.$createdAt),
      'uploaded_at_raw': file.$createdAt,
      'course_scope': scope,
      'student_email': studentEmail,
      'result_is_private': resultIsPrivate,
      'course_code': courseMeta['course_code'],
      'course_name': courseMeta['course_name'],
      'is_private': false,
    };
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

  String _safePathName(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  String _resultCourseKey(Map<String, dynamic> row) {
    final code = (row['course_code'] ?? '').toString().trim();
    final name = (row['course_name'] ?? '').toString().trim();
    final isPrivate =
        (row['is_private'] == true) || (row['is_private']?.toString() == '1');
    if (code.isEmpty && name.isEmpty) {
      return '__unknown__|||${isPrivate ? '1' : '0'}';
    }
    return '$code|||$name|||${isPrivate ? '1' : '0'}';
  }

  String _resultCourseLabel(String key) {
    if (key == 'all') return 'All Courses';
    if (key.startsWith('__unknown__')) return 'Unknown Course';

    final parts = key.split('|||');
    final code = parts.isNotEmpty ? parts.first.trim() : '';
    final name = parts.length > 1 ? parts[1].trim() : '';

    if (code.isEmpty && name.isEmpty) return 'Unknown Course';
    if (code.isEmpty) return name;
    if (name.isEmpty) return code;
    return '$code ($name)';
  }

  bool _resultCourseKeyIsPrivate(String key) {
    if (key == 'all') return false;
    final parts = key.split('|||');
    final marker = parts.isNotEmpty ? parts.last.trim() : '0';
    return marker == '1';
  }

  List<String> _resultCourseFilterKeys() {
    final keys = _results.map((row) => _resultCourseKey(row)).toSet().toList()
      ..sort((a, b) => _resultCourseLabel(a).compareTo(_resultCourseLabel(b)));
    return ['all', ...keys];
  }

  List<Map<String, dynamic>> _filteredResults() {
    if (_selectedResultCourseFilter == 'all') return _results;
    return _results
        .where((row) => _resultCourseKey(row) == _selectedResultCourseFilter)
        .toList();
  }

  void _enterResultSelectionMode(String fileId) {
    setState(() {
      _resultSelectionMode = true;
      _selectedResultFileIds.add(fileId);
    });
  }

  void _toggleResultFileSelection(String fileId) {
    setState(() {
      if (_selectedResultFileIds.contains(fileId)) {
        _selectedResultFileIds.remove(fileId);
      } else {
        _selectedResultFileIds.add(fileId);
      }
      if (_selectedResultFileIds.isEmpty) {
        _resultSelectionMode = false;
      }
    });
  }

  void _toggleResultSelectionMode() {
    setState(() {
      if (_resultSelectionMode) {
        _resultSelectionMode = false;
        _selectedResultFileIds.clear();
      } else {
        _resultSelectionMode = true;
      }
    });
  }

  List<String> _visibleResultFileIds() {
    return _filteredResults()
        .map((row) => (row['file_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList();
  }

  void _toggleSelectAllVisibleResults() {
    final visibleIds = _visibleResultFileIds();
    if (visibleIds.isEmpty) return;

    setState(() {
      final allSelected = visibleIds.every(_selectedResultFileIds.contains);
      if (allSelected) {
        _selectedResultFileIds.removeAll(visibleIds);
        if (_selectedResultFileIds.isEmpty) {
          _resultSelectionMode = false;
        }
      } else {
        _resultSelectionMode = true;
        _selectedResultFileIds.addAll(visibleIds);
      }
    });
  }

  Future<void> _downloadSelectedResults() async {
    if (_selectedResultFileIds.isEmpty) return;

    final selectedRows = _results
        .where(
          (result) => _selectedResultFileIds.contains(
            (result['file_id'] ?? '').toString(),
          ),
        )
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
    for (var index = 0; index < selectedRows.length; index++) {
      final row = selectedRows[index];
      final fileId = (row['file_id'] ?? '').toString();
      final fileName = (row['file_name'] ?? 'result_file').toString();
      if (fileId.isEmpty) continue;
      try {
        progressText.value =
            'Downloading ${index + 1}/${selectedRows.length}: $fileName';
        final bytes = await appwriteStorage.getFileDownload(
          bucketId: materialsBucketId,
          fileId: fileId,
        );

        if (kIsWeb) {
          await FileSaver.instance.saveFile(
            name: _baseFileName(fileName),
            bytes: bytes,
            fileExtension: _fileExt(fileName),
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
            '${targetDir.path}/${_safePathName(fileName)}',
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
    setState(() {
      _resultSelectionMode = false;
      _selectedResultFileIds.clear();
    });
  }

  Future<void> _downloadSingleResult({
    required String fileId,
    required String fileName,
  }) async {
    if (fileId.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Download Result File'),
        content: Text('Do you want to download "$fileName"?'),
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
      progressText.value = 'Downloading: $fileName';
      final bytes = await appwriteStorage.getFileDownload(
        bucketId: materialsBucketId,
        fileId: fileId,
      );

      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: _baseFileName(fileName),
          bytes: bytes,
          fileExtension: _fileExt(fileName),
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
        final targetFile = File('${targetDir.path}/${_safePathName(fileName)}');
        await targetFile.writeAsBytes(bytes, flush: true);
      }
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      progressText.dispose();
      _showMsg('Downloaded: $fileName');
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      progressText.dispose();
      _showMsg('Failed to download file: $e');
    }
  }

  Future<void> _loadTeachers() async {
    setState(() => _loadingTeachers = true);
    try {
      final result = await _apiService.getAllTeachers();
      if (!mounted) return;
      if (result['success'] == true) {
        final rows = (result['teachers'] as List? ?? [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        setState(() => _teachers = rows);
        final urls = await _loadTeacherProfileImages(rows);
        if (mounted) {
          setState(() => _teacherProfileImageUrlByEmail = urls);
        }
      } else {
        _showMsg(result['message'] ?? 'Failed to load teachers');
      }
    } catch (e) {
      debugPrint('Error loading teachers: $e');
    } finally {
      if (mounted) setState(() => _loadingTeachers = false);
    }
  }

  String _sanitizeTeacherEmail(String email) {
    return email.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  }

  String _teacherInitialsFromName(String name) {
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

  String _teacherImageUrlFromFileId(String fileId) {
    return '$appwriteEndpoint/storage/buckets/$materialsBucketId/files/$fileId/view?project=$appwriteProjectId';
  }

  Future<Map<String, String>> _loadTeacherProfileImages(
    List<Map<String, dynamic>> teachers,
  ) async {
    final emailToPrefix = <String, String>{};
    for (final teacher in teachers) {
      final email = (teacher['email'] ?? '').toString().trim().toLowerCase();
      if (email.isEmpty) continue;
      emailToPrefix[email] =
          'teacher_profile__${_sanitizeTeacherEmail(email)}__';
    }
    if (emailToPrefix.isEmpty) return <String, String>{};

    try {
      final files = await appwriteStorage.listFiles(
        bucketId: materialsBucketId,
        queries: [Query.limit(500)],
      );

      final latestFileByEmail = <String, appwrite_models.File>{};
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
        urls[email] = _teacherImageUrlFromFileId(file.$id);
      });
      return urls;
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<void> _loadNotifications() async {
    if (_email.isEmpty) return;
    setState(() => _loadingNotifications = true);
    final result = await _apiService.getNotifications(_email);
    if (!mounted) return;
    if (result['success'] == true) {
      setState(() {
        _notifications = List<Map<String, dynamic>>.from(
          result['notifications'] ?? [],
        );
        _unreadCount = result['unread_count'] ?? 0;
      });
    }
    setState(() => _loadingNotifications = false);
  }

  Future<void> _refreshNotificationsBadge() async {
    await _loadNotifications();
  }

  Future<void> _markNotificationRead(
    String? id, {
    bool markAll = false,
    VoidCallback? onUpdate,
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(markAll ? 'Mark All as Read' : 'Mark as Read'),
        content: Text(
          markAll
              ? 'Do you want to mark all notifications as read?'
              : 'Do you want to mark this notification as read?',
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
    if (confirm != true) return;

    final result = await _apiService.markNotificationRead(
      id: id,
      email: _email,
      markAll: markAll,
    );
    if (result['success'] == true) {
      await _loadNotifications();
      if (onUpdate != null) onUpdate();
    }
  }

  Future<void> _markNotificationReadSilently(
    String? id, {
    bool markAll = false,
    VoidCallback? onUpdate,
  }) async {
    final result = await _apiService.markNotificationRead(
      id: id,
      email: _email,
      markAll: markAll,
    );
    if (result['success'] == true) {
      await _loadNotifications();
      if (onUpdate != null) onUpdate();
    }
  }

  Future<void> _clearNotifications({VoidCallback? onUpdate}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Notifications'),
        content: const Text(
          'Are you sure you want to delete all notifications?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final result = await _apiService.deleteNotifications(_email);
    if (result['success'] == true) {
      await _loadNotifications();
      if (onUpdate != null) onUpdate();
      _showMsg('Notifications cleared');
    } else {
      _showMsg(result['message'] ?? 'Action failed');
    }
  }

  void _showMsg(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _toggleEnrollment(Map<String, dynamic> course) async {
    final isEnrolled = ((course['is_enrolled'] ?? 0).toString() == '1');
    if (isEnrolled) return;
    final courseId = int.tryParse((course['course_id'] ?? 0).toString()) ?? 0;
    final result = await _apiService.enrollCourse(
      email: _email,
      courseId: courseId,
    );
    if (result['success'] == true) {
      await _loadCourses();
      await _loadResults();
      _showMsg('Enrolled successfully');
    } else {
      _showMsg(result['message'] ?? 'Action failed');
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
      role: 'student',
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
      role: 'student',
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
        role: 'student',
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

  @override
  Widget build(BuildContext context) {
    final selectedCount = _selectedResultFileIds.length;
    final visibleIds = _visibleResultFileIds();
    final allVisibleSelected =
        visibleIds.isNotEmpty &&
        visibleIds.every(_selectedResultFileIds.contains);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        title: Text(
          _selectedTab == 1 && _resultSelectionMode
              ? '$selectedCount selected'
              : 'Student Panel',
        ),
        actions: [
          if (_selectedTab == 1 && _resultSelectionMode)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  '$selectedCount selected',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          if (_selectedTab == 1 && _resultSelectionMode)
            IconButton(
              icon: Icon(
                allVisibleSelected
                    ? Icons.check_box
                    : Icons.check_box_outline_blank,
              ),
              onPressed: _toggleSelectAllVisibleResults,
              tooltip: allVisibleSelected ? 'Unselect all' : 'Select all',
            ),
          if (_selectedTab == 1 && _resultSelectionMode)
            IconButton(
              icon: const Icon(Icons.download),
              onPressed: _selectedResultFileIds.isEmpty
                  ? null
                  : _downloadSelectedResults,
              tooltip: 'Download selected',
            ),
          if (_selectedTab == 1 && _resultSelectionMode)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _toggleResultSelectionMode,
              tooltip: 'Close selection',
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Badge(
              isLabelVisible: _unreadCount > 0,
              label: Text(_unreadCount.toString()),
              child: IconButton(
                icon: const Icon(Icons.notifications_outlined),
                onPressed: _showNotificationSheet,
                tooltip: 'Notifications',
              ),
            ),
          ),
        ],
      ),
      body: _buildSelectedSection(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) {
          setState(() {
            _selectedTab = index;
            if (index != 1) {
              _resultSelectionMode = false;
              _selectedResultFileIds.clear();
            }
          });
          // Refresh teachers each time tab is opened so latest profile photos appear
          if (index == 2) {
            _loadTeachers();
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.menu_book), label: 'Courses'),
          NavigationDestination(icon: Icon(Icons.assessment), label: 'Results'),
          NavigationDestination(icon: Icon(Icons.school), label: 'Teachers'),
          NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }

  Widget _buildSelectedSection() {
    if (_selectedTab == 0) return _buildCoursesTab();
    if (_selectedTab == 1) return _buildResultsTab();
    if (_selectedTab == 2) return _buildTeachersTab();
    return _buildProfileTab();
  }

  Widget _buildCoursesTab() {
    if (_loadingCourses) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_courses.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async {
          await _loadCourses();
          await _refreshNotificationsBadge();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 250),
            Center(
              child: Text('No courses available for your faculty/session.'),
            ),
          ],
        ),
      );
    }
    final filterKeys = _studentCourseFilterKeys();
    final visibleCourses = _filteredStudentCourses();

    return RefreshIndicator(
      onRefresh: () async {
        await _loadCourses();
        await _refreshNotificationsBadge();
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: 1 + (visibleCourses.isEmpty ? 1 : visibleCourses.length),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: filterKeys.contains(_selectedStudentCourseFilter)
                            ? _selectedStudentCourseFilter
                            : 'all',
                        decoration: const InputDecoration(
                          labelText: 'Courses',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        items: filterKeys
                            .map(
                              (key) => DropdownMenuItem<String>(
                                value: key,
                                child: Text(
                                  _studentCourseLabel(key),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _selectedStudentCourseFilter = value);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: _selectedStudentEnrollmentFilter,
                        decoration: const InputDecoration(
                          labelText: 'Enrollment',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('All')),
                          DropdownMenuItem(
                            value: 'enrolled',
                            child: Text('Enrolled'),
                          ),
                          DropdownMenuItem(
                            value: 'unenrolled',
                            child: Text('Unenrolled'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(
                            () => _selectedStudentEnrollmentFilter = value,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          if (visibleCourses.isEmpty) {
            return const Padding(
              padding: EdgeInsets.only(top: 100),
              child: Center(
                child: Text('No courses available for this filter.'),
              ),
            );
          }

          final c = visibleCourses[index - 1];
          final enrolled = _isStudentCourseEnrolled(c);
          return Card(
            child: ListTile(
              title: Text('${c['course_code']} - ${c['course_name']}'),
              subtitle: Text(
                'Session: ${c['session']} | Teacher: ${c['teacher_name']}',
              ),
              trailing: ElevatedButton(
                onPressed: enrolled ? null : () => _toggleEnrollment(c),
                child: Text(enrolled ? 'Enrolled' : 'Enroll'),
              ),
              onTap: enrolled
                  ? () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => StudentCourseDetailPage(
                            course: c,
                            studentEmail: _email,
                            apiService: _apiService,
                          ),
                        ),
                      );
                    }
                  : () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            '⚠️ Please enroll in this course first to access its content.',
                          ),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    },
            ),
          );
        },
      ),
    );
  }

  Widget _buildResultsTab() {
    if (_loadingResults) {
      return const Center(child: CircularProgressIndicator());
    }
    final filterKeys = _resultCourseFilterKeys();
    final visibleResults = _filteredResults();
    return RefreshIndicator(
      onRefresh: () async {
        await _loadResults();
        unawaited(_loadCourses());
        unawaited(_loadProfile());
        unawaited(_refreshNotificationsBadge());
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: 1 + (visibleResults.isEmpty ? 1 : visibleResults.length),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  menuMaxHeight: 280,
                  borderRadius: BorderRadius.circular(12),
                  value: filterKeys.contains(_selectedResultCourseFilter)
                      ? _selectedResultCourseFilter
                      : 'all',
                  decoration: const InputDecoration(
                    labelText: 'Courses',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: filterKeys
                      .map(
                        (key) => DropdownMenuItem<String>(
                          value: key,
                          child: Row(
                            children: [
                              if (_resultCourseKeyIsPrivate(key)) ...[
                                Icon(
                                  Icons.block,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                              ],
                              Expanded(
                                child: Text(
                                  _resultCourseLabel(key),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  selectedItemBuilder: (context) => filterKeys
                      .map(
                        (key) => Align(
                          alignment: Alignment.centerLeft,
                          child: Row(
                            children: [
                              if (_resultCourseKeyIsPrivate(key)) ...[
                                Icon(
                                  Icons.block,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                              ],
                              Expanded(
                                child: Text(
                                  _resultCourseLabel(key),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _selectedResultCourseFilter = value;
                      _resultSelectionMode = false;
                      _selectedResultFileIds.clear();
                    });
                  },
                ),
              ),
            );
          }

          if (visibleResults.isEmpty) {
            return const Padding(
              padding: EdgeInsets.only(top: 100),
              child: Center(
                child: Text('No result files available for this filter.'),
              ),
            );
          }

          final r = visibleResults[index - 1];
          final fileId = (r['file_id'] ?? '').toString();
          final isSelected = _selectedResultFileIds.contains(fileId);
          final isHighlighted =
              fileId.isNotEmpty && fileId == _highlightedResultFileId;
          final courseCode = (r['course_code'] ?? '').toString().trim();
          final courseName = (r['course_name'] ?? '').toString().trim();
          final courseLabel = courseCode.isEmpty && courseName.isEmpty
              ? 'Unknown Course'
              : courseCode.isEmpty
              ? courseName
              : courseName.isEmpty
              ? courseCode
              : '$courseCode ($courseName)';
          final isPrivate =
              (r['is_private'] == true) || (r['is_private']?.toString() == '1');
          return Card(
            color: isHighlighted ? Colors.transparent : null,
            elevation: isHighlighted ? 0 : null,
            shape: isHighlighted
                ? RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Colors.green, width: 2),
                  )
                : null,
            child: ListTile(
              leading: _resultSelectionMode
                  ? Checkbox(
                      value: isSelected,
                      onChanged: fileId.isEmpty
                          ? null
                          : (_) => _toggleResultFileSelection(fileId),
                    )
                  : const Icon(Icons.assessment_outlined),
              trailing: _resultSelectionMode
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SizedBox(
                        width: 40,
                        child: Align(
                          alignment: const Alignment(0, 0.2),
                          child: IconButton(
                            icon: const Icon(Icons.download),
                            tooltip: 'Download',
                            onPressed: fileId.isEmpty
                                ? null
                                : () => _downloadSingleResult(
                                    fileId: fileId,
                                    fileName: (r['file_name'] ?? '').toString(),
                                  ),
                          ),
                        ),
                      ),
                    ),
              title: Text((r['file_name'] ?? '').toString()),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Size: ${(r['file_size'] ?? '').toString()}'),
                  Text('Uploaded: ${(r['uploaded_at'] ?? '').toString()}'),
                  Row(
                    children: [
                      if (isPrivate) ...[
                        Icon(
                          Icons.block,
                          color: Theme.of(context).colorScheme.onSurface,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          courseLabel,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              isThreeLine: true,
              selected: isSelected,
              onLongPress: fileId.isEmpty
                  ? null
                  : () => _enterResultSelectionMode(fileId),
              onTap: _resultSelectionMode && fileId.isNotEmpty
                  ? () => _toggleResultFileSelection(fileId)
                  : null,
            ),
          );
        },
      ),
    );
  }

  Widget _buildTeachersTab() {
    if (_loadingTeachers) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_teachers.isEmpty) {
      return const Center(child: Text('No teachers found in the system.'));
    }
    return RefreshIndicator(
      onRefresh: () async {
        await _loadTeachers();
        await _refreshNotificationsBadge();
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: _teachers.length,
        itemBuilder: (context, index) {
          final t = _teachers[index];
          final teacherName = (t['name'] ?? '').toString();
          final teacherInitials = _teacherInitialsFromName(teacherName);
          final teacherEmail = (t['email'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          final teacherImageUrl =
              _teacherProfileImageUrlByEmail[teacherEmail] ?? '';
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.green.withOpacity(0.1),
                backgroundImage: teacherImageUrl.isNotEmpty
                    ? NetworkImage(teacherImageUrl)
                    : null,
                child: teacherImageUrl.isNotEmpty
                    ? null
                    : (teacherInitials.isNotEmpty
                          ? Text(
                              teacherInitials,
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : const Icon(Icons.person, color: Colors.green)),
              ),
              title: Text(teacherName),
              subtitle: Text(t['email'] ?? ''),
              trailing: const Icon(Icons.chevron_right, size: 16),
              onTap: () {
                final teacherName = (t['name'] ?? 'Teacher Profile').toString();
                final teacherInitials = _teacherInitialsFromName(teacherName);
                final teacherEmail = (t['email'] ?? 'N/A').toString();
                final teacherPhone = (t['phone'] ?? 'N/A').toString();
                final teacherImageUrl =
                    _teacherProfileImageUrlByEmail[(t['email'] ?? '')
                        .toString()
                        .trim()
                        .toLowerCase()] ??
                    '';
                Future<void> copyValue(String label, String value) async {
                  final trimmed = value.trim();
                  if (trimmed.isEmpty || trimmed.toLowerCase() == 'n/a') {
                    _showMsg('No $label to copy');
                    return;
                  }
                  await Clipboard.setData(ClipboardData(text: trimmed));
                  _showMsg('$label copied');
                }

                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                    contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                    actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    title: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.green.withOpacity(0.12),
                          backgroundImage: teacherImageUrl.isNotEmpty
                              ? NetworkImage(teacherImageUrl)
                              : null,
                          child: teacherImageUrl.isNotEmpty
                              ? null
                              : (teacherInitials.isNotEmpty
                                    ? Text(
                                        teacherInitials,
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
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            teacherName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Theme.of(context).colorScheme.surface,
                            border: Border.all(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                          child: Column(
                            children: [
                              InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => copyValue('Email', teacherEmail),
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
                                          teacherEmail,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Icon(
                                        Icons.copy_rounded,
                                        size: 16,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => copyValue('Phone', teacherPhone),
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
                                          teacherPhone,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Icon(
                                        Icons.copy_rounded,
                                        size: 16,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
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
    );
  }

  Widget _buildProfileTab() {
    if (_loadingProfile) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: () async {
        await _loadProfile();
        await _refreshNotificationsBadge();
      },
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
            onEdit: () {},
            trailing: const SizedBox.shrink(),
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

  Future<void> _showNotificationSheet() async {
    await _loadNotifications();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return _buildNotificationSheetContent(
            onUpdate: () => setSheetState(() {}),
          );
        },
      ),
    );
  }

  Widget _buildNotificationSheetContent({required VoidCallback onUpdate}) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              width: 40,
              height: 5,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Notifications',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueAccent,
                      ),
                    ),
                    Text(
                      'Your updates and alerts',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                  ],
                ),
                if (_notifications.isNotEmpty)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.delete_sweep,
                          color: Colors.redAccent,
                        ),
                        onPressed: () =>
                            _clearNotifications(onUpdate: onUpdate),
                        tooltip: 'Clear All',
                      ),
                      if (_unreadCount > 0)
                        TextButton.icon(
                          onPressed: () => _markNotificationRead(
                            null,
                            markAll: true,
                            onUpdate: onUpdate,
                          ),
                          icon: const Icon(
                            Icons.done_all,
                            size: 16,
                            color: Colors.blueAccent,
                          ),
                          label: const Text(
                            'Mark all read',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          if (_unreadCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
              child: Row(
                children: [
                  Text(
                    '$_unreadCount Unread Message${_unreadCount > 1 ? 's' : ''}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blueAccent,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: _loadingNotifications && _notifications.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () async {
                      await _loadNotifications();
                      onUpdate();
                    },
                    child: _notifications.isEmpty
                        ? ListView(
                            children: const [
                              SizedBox(height: 100),
                              Icon(
                                Icons.notifications_off_outlined,
                                size: 80,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 16),
                              Center(
                                child: Text(
                                  'No notifications yet',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: _notifications.length,
                            separatorBuilder: (ctx, idx) =>
                                const Divider(height: 1),
                            itemBuilder: (ctx, idx) {
                              final n = _notifications[idx];
                              final bool isUnread = n['is_read'] == false;
                              return ListTile(
                                visualDensity: VisualDensity.comfortable,
                                leading: CircleAvatar(
                                  backgroundColor: isUnread
                                      ? Colors.blue.withOpacity(0.1)
                                      : Colors.grey.withOpacity(0.1),
                                  child: Icon(
                                    _getNotificationIcon(n['type']),
                                    color: isUnread ? Colors.blue : Colors.grey,
                                  ),
                                ),
                                title: Text(
                                  n['title'] ?? 'No Title',
                                  style: TextStyle(
                                    fontWeight: isUnread
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    fontSize: 14,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text(
                                      n['message'] ?? '',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _formatTimestamp(n['created_at']),
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: isUnread
                                    ? Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: Colors.blue,
                                          shape: BoxShape.circle,
                                        ),
                                      )
                                    : null,
                                onTap: () {
                                  if (_notificationBaseType(n['type']) ==
                                      'result') {
                                    _openResultFromNotification(
                                      n,
                                      onUpdate: onUpdate,
                                      closeSheet: true,
                                    );
                                    return;
                                  }
                                  _showNotificationDetail(
                                    n,
                                    onUpdate: onUpdate,
                                  );
                                },
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  IconData _getNotificationIcon(dynamic type) {
    switch (_notificationBaseType(type)) {
      case 'attendance':
        return Icons.event_available_outlined;
      case 'course_launch':
        return Icons.new_releases_outlined;
      case 'material':
        return Icons.description_outlined;
      case 'enrollment':
        return Icons.how_to_reg_outlined;
      case 'block_status':
        return Icons.block_flipped;
      case 'assignment':
        return Icons.assignment_outlined;
      case 'result':
        return Icons.assessment_outlined;
      case 'discussion':
        return Icons.forum_outlined;
      case 'alert':
        return Icons.warning_amber_rounded;
      default:
        return Icons.notifications_none;
    }
  }

  String _notificationBaseType(dynamic type) {
    final raw = (type ?? '').toString().toLowerCase();
    if (raw.startsWith('result|')) return 'result';
    return raw;
  }

  String _resultFileIdFromNotificationType(dynamic type) {
    final raw = (type ?? '').toString();
    const marker = 'result|';
    if (!raw.toLowerCase().startsWith(marker)) return '';
    return raw.substring(marker.length).trim();
  }

  Future<void> _openResultFromNotification(
    Map<String, dynamic> notification, {
    VoidCallback? onUpdate,
    bool closeSheet = false,
  }) async {
    final fileId = _resultFileIdFromNotificationType(notification['type']);
    final wasUnread =
        notification['is_read'] == false ||
        notification['is_read']?.toString() == '0';

    if (closeSheet && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    if (mounted) {
      setState(() {
        _selectedTab = 1;
        _resultSelectionMode = false;
        _selectedResultFileIds.clear();
      });
    }

    await _loadResults();
    if (!mounted) return;

    Map<String, dynamic>? target;
    if (fileId.isNotEmpty) {
      for (final row in _results) {
        if ((row['file_id'] ?? '').toString() == fileId) {
          target = row;
          break;
        }
      }
    }

    setState(() {
      _selectedTab = 1;
      _resultSelectionMode = false;
      _selectedResultFileIds.clear();
      if (target != null) {
        _selectedResultCourseFilter = _resultCourseKey(target);
        _highlightedResultFileId = (target['file_id'] ?? '').toString();
      } else {
        _highlightedResultFileId = '';
      }
    });

    _resultHighlightTimer?.cancel();
    if (target != null && _highlightedResultFileId.isNotEmpty) {
      final activeFileId = _highlightedResultFileId;
      _resultHighlightTimer = Timer(const Duration(seconds: 1), () {
        if (!mounted) return;
        if (_highlightedResultFileId == activeFileId) {
          setState(() => _highlightedResultFileId = '');
        }
      });
    } else {
      _showMsg('Result file not found. Pull to refresh and try again.');
    }

    if (wasUnread) {
      await _markNotificationReadSilently(
        notification['id'].toString(),
        onUpdate: closeSheet ? null : onUpdate,
      );
    }
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return '';
    try {
      final raw = timestamp.toString().trim();
      final parsed = DateTime.parse(raw);
      final now = DateTime.now();
      final candidates = <DateTime>[
        parsed,
        parsed.toLocal(),
        parsed.add(const Duration(hours: 11)),
        parsed.subtract(const Duration(hours: 11)),
      ];
      DateTime dt = candidates.first;
      Duration best = now.difference(dt).abs();
      for (final candidate in candidates.skip(1)) {
        final current = now.difference(candidate).abs();
        if (current < best) {
          best = current;
          dt = candidate;
        }
      }
      final diff = now.difference(dt);

      if (diff.isNegative) {
        return 'Just now';
      }

      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return timestamp.toString();
    }
  }

  Future<void> _showNotificationDetail(
    Map<String, dynamic> n, {
    VoidCallback? onUpdate,
  }) async {
    final String type = _notificationBaseType(n['type']);
    final int courseId = int.tryParse(n['course_id']?.toString() ?? '0') ?? 0;
    final bool wasUnread =
        n['is_read'] == false || n['is_read']?.toString() == '0';
    final course = _courses.firstWhere(
      (c) => int.tryParse(c['course_id']?.toString() ?? '0') == courseId,
      orElse: () => {},
    );
    final bool isCourseEnrolled =
        course.isNotEmpty && (course['is_enrolled'] ?? 0).toString() == '1';
    final courseCode = (course['course_code'] ?? '').toString();
    final courseName = (course['course_name'] ?? '').toString();
    final courseLabel = [
      courseCode,
      courseName,
    ].where((value) => value.trim().isNotEmpty).join(' - ');
    final bool isDiscussion = type == 'discussion';
    final dialogTitle = isDiscussion
        ? (n['title'] ?? 'Notification').toString()
        : (courseLabel.isNotEmpty
              ? courseLabel
              : (n['title'] ?? 'Notification').toString());

    bool handledByAction = false;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(dialogTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(n['message'] ?? '', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 20),
            Text(
              'Received: ${_formatTimestamp(n['created_at'])}',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (type == 'course_launch' && courseId > 0)
            ElevatedButton.icon(
              icon: const Icon(Icons.how_to_reg, size: 16),
              label: const Text('Enroll Now'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              onPressed: isCourseEnrolled
                  ? null
                  : () async {
                      Navigator.pop(context);
                      final course = _courses.firstWhere(
                        (c) =>
                            int.tryParse(c['course_id']?.toString() ?? '0') ==
                            courseId,
                        orElse: () => {},
                      );
                      if (course.isNotEmpty) {
                        await _toggleEnrollment(course);
                      } else {
                        _showMsg(
                          'Course not found in your list. Try refreshing.',
                        );
                      }
                    },
            ),
          if (type == 'attendance' && courseId > 0)
            ElevatedButton.icon(
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Open Course'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(context);
                final course = _courses.firstWhere(
                  (c) =>
                      int.tryParse(c['course_id']?.toString() ?? '0') ==
                      courseId,
                  orElse: () => {},
                );
                if (course.isNotEmpty &&
                    (course['is_enrolled'] ?? 0).toString() == '1') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StudentCourseDetailPage(
                        course: course,
                        studentEmail: _email,
                        apiService: _apiService,
                      ),
                    ),
                  );
                } else {
                  _showMsg('Enroll in this course first.');
                }
              },
            ),
          if (type == 'result')
            ElevatedButton.icon(
              icon: const Icon(Icons.assessment_outlined, size: 16),
              label: const Text('Open Result'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                handledByAction = true;
                Navigator.pop(context);
                await _openResultFromNotification(n, onUpdate: onUpdate);
              },
            ),
        ],
      ),
    );

    if (wasUnread && !handledByAction) {
      await _markNotificationReadSilently(
        n['id'].toString(),
        onUpdate: onUpdate,
      );
    }
  }
}

class StudentCourseDetailPage extends StatefulWidget {
  final Map<String, dynamic> course;
  final String studentEmail;
  final ApiService apiService;
  const StudentCourseDetailPage({
    super.key,
    required this.course,
    required this.studentEmail,
    required this.apiService,
  });
  @override
  State<StudentCourseDetailPage> createState() =>
      _StudentCourseDetailPageState();
}

class _StudentCourseDetailPageState extends State<StudentCourseDetailPage> {
  bool _loadingClassmates = true;
  bool _loadingAttendance = true;
  bool _showAttendanceHistory = false;
  Timer? _attendanceTicker;
  List<Map<String, dynamic>> _classmates = [];
  Map<String, String>? _classmateProfileImageUrlByEmail;
  List<Map<String, dynamic>> _attendanceSessions = [];
  Set<int> _markedSessionIds = {};
  int get _courseId =>
      int.tryParse((widget.course['course_id'] ?? 0).toString()) ?? 0;

  String get _courseScope {
    final values = [
      widget.course['course_code'],
      widget.course['course_id'],
      widget.course['id'],
      widget.course['courseId'],
      widget.course['course_name'],
    ];
    final raw = values
        .map((v) => (v ?? '').toString().trim())
        .firstWhere(
          (value) => value.isNotEmpty,
          orElse: () => 'course_$_courseId',
        );
    return raw.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_').toLowerCase();
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

  Future<void> _loadAll() async {
    await Future.wait([_loadClassmates(), _loadAttendanceSessions()]);
  }

  Future<void> _showAttendanceReport(Map<String, dynamic> session) async {
    final sessionId = int.tryParse(session['id']?.toString() ?? '') ?? 0;
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
                          'Batchmate Attendance',
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
                child: FutureBuilder<Map<String, dynamic>>(
                  future: widget.apiService.getSessionAttendanceReport(
                    sessionId: sessionId,
                    courseId: _courseId,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError ||
                        snapshot.data?['success'] != true) {
                      return Center(
                        child: Text(
                          snapshot.data?['message'] ?? 'Failed to load report',
                        ),
                      );
                    }
                    final report = (snapshot.data!['report'] as List)
                        .where(
                          (r) => ((r['is_blocked'] ?? 0).toString() != '1'),
                        )
                        .toList();
                    final total = report.length;
                    final attended = report
                        .where((r) => r['attended'] == true)
                        .length;
                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildStatChip('Total', total, Colors.blue),
                              _buildStatChip('Present', attended, Colors.green),
                              _buildStatChip(
                                'Absent',
                                total - attended,
                                Colors.red,
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            controller: controller,
                            itemCount: report.length,
                            itemBuilder: (context, index) {
                              final r = report[index];
                              final hasAttended = r['attended'] == true;
                              return ListTile(
                                leading: Stack(
                                  children: [
                                    CircleAvatar(
                                      backgroundImage:
                                          _classmateProfileImageUrlByEmail
                                                  ?.containsKey(
                                                    (r['email'] ?? '')
                                                        .toString()
                                                        .trim()
                                                        .toLowerCase(),
                                                  ) ==
                                              true
                                          ? NetworkImage(
                                              _classmateProfileImageUrlByEmail![(r['email'] ??
                                                      '')
                                                  .toString()
                                                  .trim()
                                                  .toLowerCase()]!,
                                            )
                                          : null,
                                      backgroundColor: hasAttended
                                          ? Colors.green.withOpacity(0.1)
                                          : Colors.red.withOpacity(0.1),
                                      child:
                                          _classmateProfileImageUrlByEmail
                                                  ?.containsKey(
                                                    (r['email'] ?? '')
                                                        .toString()
                                                        .trim()
                                                        .toLowerCase(),
                                                  ) !=
                                              true
                                          ? Text(
                                              _studentInitialsFromName(
                                                r['name'] ?? '',
                                              ),
                                              style: TextStyle(
                                                color: hasAttended
                                                    ? Colors.green
                                                    : Colors.red,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
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
                                subtitle: Text(r['email'] ?? ''),
                                trailing: hasAttended
                                    ? Text(
                                        _formatMarkedTime(r['time']),
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 12,
                                        ),
                                      )
                                    : const Text(
                                        'ABSENT',
                                        style: TextStyle(
                                          color: Colors.red,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10,
                                        ),
                                      ),
                              );
                            },
                          ),
                        ),
                      ],
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

  Widget _buildStatChip(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            value.toString(),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }

  Future<void> _loadClassmates() async {
    setState(() => _loadingClassmates = true);
    final result = await widget.apiService.getBatchStudents(_courseId);
    if (!mounted) return;
    if (result['success'] == true) {
      final rows = (result['students'] as List? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .where(
            (student) =>
                (student['is_enrolled'] ?? 0).toString() == '1' &&
                (student['is_blocked'] ?? 0).toString() != '1',
          )
          .toList();
      final avatarMap = await _loadClassmateProfileImages(rows);
      if (!mounted) return;
      setState(() {
        _classmates = rows;
        _classmateProfileImageUrlByEmail = avatarMap;
      });
    }
    setState(() => _loadingClassmates = false);
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

  Future<Map<String, String>> _loadClassmateProfileImages(
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

      final latestFileByEmail = <String, appwrite_models.File>{};
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
        }
      }

      final out = <String, String>{};
      latestFileByEmail.forEach((email, file) {
        out[email] = _studentImageUrlFromFileId(file.$id);
      });
      return out;
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
      // Check attendance status for these sessions
      if (rows.isNotEmpty) {
        final sessionIds = rows
            .map((s) => int.tryParse(s['id'].toString()) ?? 0)
            .toList();
        final statusResult = await widget.apiService.getAttendanceStatus(
          email: widget.studentEmail,
          sessionIds: sessionIds,
        );
        if (statusResult['success'] == true) {
          final marked = List<int>.from(statusResult['marked_sessions'] ?? []);
          setState(() => _markedSessionIds = marked.toSet());
        }
      }
    }
    setState(() => _loadingAttendance = false);
  }

  Future<void> _markAttendance(int sessionId) async {
    final result = await widget.apiService.markAttendance(
      sessionId: sessionId,
      email: widget.studentEmail,
    );
    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? 'Attendance marked!')),
      );
      setState(() {
        _markedSessionIds.add(sessionId);
        _showAttendanceHistory = true;
      });
      await _loadAttendanceSessions();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? 'Action failed')),
      );
    }
  }

  Future<void> _markAttendanceWithQr(int sessionId, String qrData) async {
    final result = await widget.apiService.markQrAttendance(
      sessionId: sessionId,
      email: widget.studentEmail,
      qrCode: qrData,
    );
    if (!mounted) return;
    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Attendance marked!'),
          backgroundColor: Colors.green,
        ),
      );
      setState(() {
        _markedSessionIds.add(sessionId);
        _showAttendanceHistory = true;
      });
      await _loadAttendanceSessions();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'QR Verification Failed'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showQrScanDialog(int sessionId) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (context) => _QrScannerDialog(
        sessionId: sessionId,
        onQrScanned: (qrData) => _markAttendanceWithQr(sessionId, qrData),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
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
              Tab(text: 'Classmates'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildAttendance(),
            CourseDiscussionSection(
              courseId: _courseId,
              courseName: (widget.course['course_name'] ?? '').toString(),
              userEmail: widget.studentEmail,
              userRole: 'student',
              userName: '',
              apiService: widget.apiService,
            ),
            StudentAssignmentSection(
              courseId: _courseId,
              apiService: widget.apiService,
              teacherName: (widget.course['teacher_name'] ?? '').toString(),
              userEmail: widget.studentEmail,
              userName: '',
            ),
            _buildMaterials(),
            _buildClassmates(),
          ],
        ),
      ),
    );
  }

  Widget _buildClassmates() {
    if (_loadingClassmates) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_classmates.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadClassmates,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Center(child: Text('No classmates enrolled yet.')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadClassmates,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        itemCount: _classmates.length,
        itemBuilder: (context, index) {
          final s = _classmates[index];
          final name = (s['name'] ?? '').toString();
          final email = (s['email'] ?? '').toString();
          final safeEmail = email.trim().toLowerCase();
          final classmateAvatarMap =
              _classmateProfileImageUrlByEmail ?? const <String, String>{};
          final profileImageUrl = classmateAvatarMap[safeEmail] ?? '';
          final initials = _studentInitialsFromName(name);
          final isMe = email.toLowerCase() == widget.studentEmail.toLowerCase();
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.blueAccent.withOpacity(0.12),
                  backgroundImage: profileImageUrl.isNotEmpty
                      ? NetworkImage(profileImageUrl)
                      : null,
                  child: profileImageUrl.isNotEmpty
                      ? null
                      : Text(
                          initials.isNotEmpty ? initials : '?',
                          style: const TextStyle(
                            color: Colors.blueAccent,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: isMe
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                              ),
                            ),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.blueAccent.withOpacity(0.4),
                                ),
                              ),
                              child: const Text(
                                'You',
                                style: TextStyle(
                                  color: Colors.blueAccent,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMaterials() {
    return StudentCourseMaterialsSection(
      courseId: _courseId,
      courseScope: _courseScope,
      studentEmail: widget.studentEmail,
      courseName: (widget.course['course_name'] ?? '').toString(),
    );
  }

  Widget _buildAttendance() {
    if (_loadingAttendance) {
      return const Center(child: CircularProgressIndicator());
    }
    final deviceNow = DateTime.now();
    final totalSessions = _attendanceSessions
        .where((s) => s['is_private'].toString() != '1')
        .length;
    final attendedCount = _markedSessionIds.length;
    final double percentage = totalSessions > 0
        ? (attendedCount / totalSessions) * 100
        : 0.0;

    final filtered = _attendanceSessions.where((s) {
      try {
        final end = DateTime.parse(s['session_end']?.toString() ?? '');
        final st = DateTime.parse(s['session_date']?.toString() ?? '');
        final isPrivate = s['is_private'].toString() == '1';
        final sessionId = int.tryParse(s['id'].toString()) ?? 0;
        final isMarked = _markedSessionIds.contains(sessionId);
        if (_showAttendanceHistory) {
          // History tab shows expired sessions OR marked sessions
          return deviceNow.isAfter(end) ||
              deviceNow.isAtSameMomentAs(end) ||
              isMarked;
        } else {
          // Active tab shows ongoing sessions AND not marked yet
          return deviceNow.isAfter(st) &&
              deviceNow.isBefore(end) &&
              !isPrivate &&
              !isMarked;
        }
      } catch (_) {
        return false;
      }
    }).toList();
    return Column(
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade800, Colors.blue.shade600],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 65,
                    height: 65,
                    child: CircularProgressIndicator(
                      value: percentage / 100,
                      strokeWidth: 8,
                      backgroundColor: Colors.white.withOpacity(0.2),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.white,
                      ),
                    ),
                  ),
                  Text(
                    '${percentage.toStringAsFixed(0)}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Attendance Overview',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'You attended $attendedCount out of $totalSessions sessions',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        percentage >= 75
                            ? 'Good Standing'
                            : (percentage >= 60
                                  ? 'Needs Improvement'
                                  : 'At Risk'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () =>
                      setState(() => _showAttendanceHistory = false),
                  icon: const Icon(Icons.dashboard),
                  label: const Text('Active'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 45),
                    backgroundColor: !_showAttendanceHistory
                        ? Colors.green
                        : Colors.grey.shade300,
                    foregroundColor: !_showAttendanceHistory
                        ? Colors.white
                        : Colors.black54,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () =>
                      setState(() => _showAttendanceHistory = true),
                  icon: const Icon(Icons.history),
                  label: const Text('History'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 45),
                    backgroundColor: _showAttendanceHistory
                        ? Colors.blueGrey
                        : Colors.grey.shade300,
                    foregroundColor: _showAttendanceHistory
                        ? Colors.white
                        : Colors.black54,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadAttendanceSessions,
            child: filtered.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 100),
                      Center(
                        child: Text(
                          _showAttendanceHistory
                              ? 'No attendance history found.'
                              : 'No active attendance sessions right now.',
                        ),
                      ),
                    ],
                  )
                : GridView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(8, 10, 8, 80),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.64,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 12,
                        ),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final s = filtered[index];
                      final sessionId = int.tryParse(s['id'].toString()) ?? 0;
                      final isMarked = _markedSessionIds.contains(sessionId);
                      final statusColor = isMarked ? Colors.green : Colors.red;
                      DateTime? st, en;
                      String dTime = "";
                      String dDate = "";
                      String durationText = "";
                      String remainingText = "";
                      try {
                        st = DateTime.parse(s['session_date'].toString());
                        en = DateTime.parse(s['session_end'].toString());
                        dDate =
                            "${st.year}-${st.month.toString().padLeft(2, '0')}-${st.day.toString().padLeft(2, '0')}";
                        String fmt(DateTime d) {
                          final h = d.hour > 12
                              ? d.hour - 12
                              : (d.hour == 0 ? 12 : d.hour);
                          final p = d.hour >= 12 ? 'PM' : 'AM';
                          return "${h.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} $p";
                        }

                        dTime = "${fmt(st)} - ${fmt(en)}";
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
                      final isDynamicQr = s['is_dynamic_qr'];
                      final bool isDynamicQrSession =
                          (isDynamicQr == 1 ||
                              isDynamicQr == '1' ||
                              isDynamicQr == true) ||
                          (s['qr_code_hex'] != null &&
                              s['qr_code_hex'].toString().isNotEmpty);
                      final bgColor = statusColor.withOpacity(0.08);
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
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                                                color: statusColor.withOpacity(
                                                  0.1,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                (_showAttendanceHistory
                                                        ? 'EXPIRED'
                                                        : 'ACTIVE')
                                                    .toUpperCase(),
                                                style: TextStyle(
                                                  color: statusColor,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              s['course_code']?.toString() ??
                                                  '',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: statusColor,
                                                fontSize: 16,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (isDynamicQrSession) ...[
                                            const Icon(
                                              Icons.qr_code_2,
                                              size: 20,
                                              color: Colors.black87,
                                            ),
                                            const SizedBox(width: 2),
                                          ],
                                          Container(
                                            margin: const EdgeInsets.only(left: 1, right: 0),
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.teal.withOpacity(0.12),
                                              border: Border.all(color: Colors.teal.shade300, width: 1),
                                              borderRadius: BorderRadius.circular(5),
                                            ),
                                            child: Text(
                                              '#$sessionId',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.teal.shade900,
                                              ),
                                            ),
                                          ),
                                          if (!_showAttendanceHistory)
                                            PopupMenuButton<String>(
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                              icon: const Icon(
                                                Icons.more_vert,
                                                color: Colors.black54,
                                                size: 20,
                                              ),
                                              onSelected: (val) {
                                                if (val == 'mark') {
                                                  if (isDynamicQrSession) {
                                                    _showQrScanDialog(
                                                      sessionId,
                                                    );
                                                  } else {
                                                    _markAttendance(sessionId);
                                                  }
                                                }
                                              },
                                              itemBuilder: (context) => [
                                                if (!isMarked)
                                                  PopupMenuItem(
                                                    value: 'mark',
                                                    child: ListTile(
                                                      dense: true,
                                                      leading: Icon(
                                                        isDynamicQrSession
                                                            ? Icons
                                                                  .qr_code_scanner
                                                            : Icons
                                                                  .check_circle_outline,
                                                        color: Colors.green,
                                                      ),
                                                      title: Text(
                                                        isDynamicQrSession
                                                            ? 'Scan QR'
                                                            : 'Give Attendance',
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  child: Text(
                                    s['course_name']?.toString() ?? "",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const Spacer(),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  child: Column(
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
                                const Spacer(),
                                Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.all(8),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                    horizontal: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: bgColor,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        dDate,
                                        style: TextStyle(
                                          color: statusColor,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        dTime,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: statusColor.withOpacity(0.9),
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
                                            color: statusColor.withOpacity(0.9),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                      if (remainingText.isNotEmpty) ...[
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
}

class _QrScannerDialog extends StatefulWidget {
  final int sessionId;
  final Function(String qrData) onQrScanned;

  const _QrScannerDialog({
    required this.sessionId,
    required this.onQrScanned,
  });

  @override
  State<_QrScannerDialog> createState() => _QrScannerDialogState();
}

class _QrScannerDialogState extends State<_QrScannerDialog> {
  MobileScannerController? _controller;
  bool _isCameraActive = false;
  bool _isProcessingScan = false;
  bool _isLoadingInCamera = false;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _startCamera() async {
    final status = await ph.Permission.camera.status;
    if (status.isGranted) {
      _activateScanner();
    } else {
      if (!mounted) return;
      _showPermissionConfirmationDialog();
    }
  }

  void _activateScanner() {
    setState(() {
      _isCameraActive = true;
      _controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        facing: CameraFacing.back,
      );
    });
  }

  void _showPermissionConfirmationDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.camera_alt, color: Colors.teal),
            SizedBox(width: 8),
            Text('Camera Access Required', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: const Text(
          'Camera permission is required to scan the attendance QR code displayed on the teacher screen. Would you like to grant permission?',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final requested = await ph.Permission.camera.request();
              if (requested.isGranted) {
                _activateScanner();
              } else if (requested.isPermanentlyDenied) {
                ph.openAppSettings();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
            child: const Text('Allow Camera'),
          ),
        ],
      ),
    );
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessingScan) return;
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final rawValue = barcode.rawValue;
      if (rawValue != null && rawValue.isNotEmpty) {
        setState(() {
          _isProcessingScan = true;
          _isLoadingInCamera = true;
        });
        _controller?.stop();
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).pop();
        widget.onQrScanned(rawValue);
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'ScanQR',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 6),
            Text(
              'Align the QR code inside the frame to mark attendance',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.teal, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: _isCameraActive && _controller != null
                    ? Stack(
                        children: [
                          MobileScanner(
                            controller: _controller,
                            onDetect: _onDetect,
                            fit: BoxFit.cover,
                          ),
                          if (_isLoadingInCamera)
                            Container(
                              color: const Color(0xB3000000),
                              alignment: Alignment.center,
                              child: const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(
                                    color: Colors.tealAccent,
                                  ),
                                  SizedBox(height: 12),
                                  Text(
                                    'Verifying QR...',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      )
                    : Stack(
                        alignment: Alignment.center,
                        children: [
                          const Icon(
                            Icons.qr_code_scanner,
                            size: 100,
                            color: Colors.tealAccent,
                          ),
                          Positioned(
                            bottom: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Tap Scan to Open Camera',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 16),
            if (!_isCameraActive)
              ElevatedButton.icon(
                onPressed: _startCamera,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Scan'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              )
            else
              ElevatedButton.icon(
                onPressed: () {
                  _controller?.stop();
                  setState(() {
                    _isCameraActive = false;
                  });
                },
                icon: const Icon(Icons.videocam_off),
                label: const Text('Close Camera'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade700,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
