import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String _defaultBaseUrl =
      'http://192.168.0.110/MobileApp/pstublcmobileapp/api';
  static final ValueNotifier<bool> databaseErrorNotifier = ValueNotifier(false);

  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  Future<String> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('apiBaseUrl') ?? _defaultBaseUrl;
  }

  Future<void> setBaseUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('apiBaseUrl', value.trim());
  }

  Future<Uri> _uri(String path) async {
    final base = await getBaseUrl();
    final normalized = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    return Uri.parse('$normalized/$path');
  }

  Future<Map<String, dynamic>> _postJson(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await http.post(
        await _uri(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      _trackDatabaseErrorFromResponse(data);
      return data;
    } catch (e) {
      _setDatabaseError(true);
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> _postForm(
    String endpoint,
    Map<String, String> body,
  ) async {
    try {
      final response = await http.post(await _uri(endpoint), body: body);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      _trackDatabaseErrorFromResponse(data);
      return data;
    } catch (e) {
      _setDatabaseError(true);
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final data = await _postJson('login.php', {
      'email': email.trim().toLowerCase(),
      'password': password,
    });
    if (data['success'] == true) {
      await _saveUserSession(data, email.trim().toLowerCase());
    }
    return data;
  }

  Future<Map<String, dynamic>> signup(Map<String, dynamic> userData) async {
    return _postJson('signup.php', userData);
  }

  Future<Map<String, dynamic>> resetPassword(String email, String newPassword) {
    return _postJson('reset_password.php', {
      'email': email.trim().toLowerCase(),
      'new_password': newPassword,
    });
  }

  Future<Map<String, dynamic>> getProfile(String role, String email) async {
    final endpoint = role == 'student'
        ? 'get_student_profile.php'
        : 'get_teacher_profile.php';
    return _postForm(endpoint, {'email': email});
  }

  Future<Map<String, dynamic>> updateProfileField({
    required String role,
    required String email,
    required String field,
    required String value,
  }) async {
    final endpoint = role == 'student'
        ? 'update_student_profile.php'
        : 'update_teacher_profile.php';
    final res = await _postForm(endpoint, {
      'email': email,
      'field': field,
      'value': value,
    });
    if (res['success'] == true && field == 'email') {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userEmail', value.trim().toLowerCase());
    }
    return res;
  }

  Future<Map<String, dynamic>> changePassword({
    required String role,
    required String email,
    required String currentPassword,
    required String newPassword,
  }) {
    final endpoint = role == 'student'
        ? 'update_student_profile.php'
        : 'update_teacher_profile.php';
    return _postForm(endpoint, {
      'email': email,
      'current_password': currentPassword,
      'new_password': newPassword,
    });
  }

  Future<Map<String, dynamic>> deleteAccount({
    required String role,
    required String email,
    required String password,
  }) {
    final endpoint = role == 'student'
        ? 'delete_student_account.php'
        : 'delete_teacher_account.php';
    return _postForm(endpoint, {'email': email, 'password': password});
  }

  Future<Map<String, dynamic>> getTeacherCourses(String email) {
    return _postJson('get_courses.php', {'email': email});
  }

  Future<Map<String, dynamic>> getStudentCourses(String email) {
    return _postJson('get_student_courses.php', {'email': email});
  }

  Future<Map<String, dynamic>> getCourseMetaByScopes({
    required String email,
    required List<String> scopes,
  }) {
    return _postJson('get_course_meta_by_scopes.php', {
      'email': email,
      'scopes': scopes,
    });
  }

  Future<Map<String, dynamic>> getAllStudents() async {
    try {
      final response = await http.get(await _uri('get_all_students.php'));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      _trackDatabaseErrorFromResponse(data);
      return data;
    } catch (e) {
      _setDatabaseError(true);
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> getAllTeachers() async {
    try {
      final response = await http.get(await _uri('get_all_teachers.php'));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      _trackDatabaseErrorFromResponse(data);
      return data;
    } catch (e) {
      _setDatabaseError(true);
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> createAttendanceSession({
    required int courseId,
    required String teacherEmail,
    required String sessionDate,
    required String sessionEnd,
  }) {
    return _postJson('create_attendance_session.php', {
      'course_id': courseId,
      'teacher_email': teacherEmail,
      'session_date': sessionDate,
      'session_end': sessionEnd,
    });
  }

  Future<Map<String, dynamic>> deleteAttendanceSession(int sessionId) {
    return _postJson('delete_attendance_session.php', {'id': sessionId});
  }

  Future<Map<String, dynamic>> updateAttendanceSession({
    required int id,
    required String sessionDate,
    required String sessionEnd,
    int? isPrivate,
  }) {
    final Map<String, dynamic> body = {
      'id': id,
      'session_date': sessionDate,
      'session_end': sessionEnd,
    };
    if (isPrivate != null) {
      body['is_private'] = isPrivate;
    }
    return _postJson('update_attendance_session.php', body);
  }

  Future<Map<String, dynamic>> getAttendanceSessions(int courseId) {
    return _get('get_attendance_sessions.php', {
      'course_id': courseId.toString(),
    });
  }

  Future<Map<String, dynamic>> markAttendance({
    required int sessionId,
    required String email,
  }) {
    return _postJson('mark_attendance.php', {
      'session_id': sessionId,
      'email': email,
    });
  }

  Future<Map<String, dynamic>> getAttendanceStatus({
    required String email,
    required List<int> sessionIds,
  }) {
    return _postJson('get_attendance_status.php', {
      'email': email,
      'session_ids': sessionIds,
    });
  }

  Future<Map<String, dynamic>> getSessionAttendanceReport({
    required int sessionId,
    required int courseId,
  }) {
    return _postJson('get_attendance_report.php', {
      'session_id': sessionId,
      'course_id': courseId,
    });
  }

  Future<Map<String, dynamic>> getCourseAttendanceOverview(int courseId) {
    return _postJson('get_course_attendance_overview.php', {
      'course_id': courseId,
    });
  }

  Future<Map<String, dynamic>> toggleManualAttendance({
    required int sessionId,
    required String email,
    required bool present,
  }) {
    return _postJson('toggle_manual_attendance.php', {
      'session_id': sessionId,
      'email': email,
      'present': present,
    });
  }

  Future<Map<String, dynamic>> toggleStudentBlock({
    required int courseId,
    required String email,
    required bool block,
  }) {
    return _postJson('toggle_student_block.php', {
      'course_id': courseId,
      'student_email': email,
      'block': block,
    });
  }

  Future<Map<String, dynamic>> createCourse({
    required String email,
    required String code,
    required String name,
    required String session,
    required String faculty,
    bool isPrivate = true,
  }) {
    return _postJson('create_course.php', {
      'email': email,
      'course_code': code,
      'course_name': name,
      'session': session,
      'faculty': faculty,
      'is_private': isPrivate ? 1 : 0,
    });
  }

  Future<Map<String, dynamic>> updateCourse({
    required int courseId,
    required String email,
    required String code,
    required String name,
    required String session,
    required String faculty,
  }) {
    return _postJson('update_course.php', {
      'course_id': courseId,
      'email': email,
      'course_code': code,
      'course_name': name,
      'session': session,
      'faculty': faculty,
    });
  }

  Future<Map<String, dynamic>> deleteCourse({
    required int courseId,
    required String email,
    required String password,
  }) {
    return _postJson('delete_course.php', {
      'course_id': courseId,
      'email': email,
      'password': password,
    });
  }

  Future<Map<String, dynamic>> toggleCourseVisibility({
    required int courseId,
    required bool isPrivate,
  }) {
    return _postJson('toggle_course_visibility.php', {
      'course_id': courseId,
      'is_private': isPrivate ? 1 : 0,
    });
  }

  Future<Map<String, dynamic>> enrollCourse({
    required String email,
    required int courseId,
  }) {
    return _postJson('enroll_course.php', {
      'email': email,
      'course_id': courseId,
    });
  }

  Future<Map<String, dynamic>> unEnrollCourse({
    required String email,
    required int courseId,
  }) {
    return _postJson('unenroll_course.php', {
      'email': email,
      'course_id': courseId,
    });
  }

  Future<Map<String, dynamic>> getEnrolledStudents(int courseId) {
    return _postJson('get_enrolled_students.php', {'course_id': courseId});
  }

  Future<Map<String, dynamic>> getBatchStudents(int courseId) {
    return _postJson('get_batch_students.php', {'course_id': courseId});
  }

  Future<Map<String, dynamic>> getCourseMaterials(int courseId) {
    return _postJson('get_course_materials.php', {'course_id': courseId});
  }

  Future<Map<String, dynamic>> getCourseDiscussionMessages({
    required int courseId,
    required String email,
    required String role,
  }) {
    return _postJson('get_course_discussion_messages.php', {
      'course_id': courseId,
      'email': email.trim().toLowerCase(),
      'role': role.trim().toLowerCase(),
    });
  }

  Future<Map<String, dynamic>> sendCourseDiscussionMessage({
    required int courseId,
    required String email,
    required String role,
    required String senderName,
    required String message,
  }) {
    return _postJson('send_course_discussion_message.php', {
      'course_id': courseId,
      'email': email.trim().toLowerCase(),
      'role': role.trim().toLowerCase(),
      'sender_name': senderName,
      'message': message,
    });
  }

  Future<Map<String, dynamic>> updateCourseDiscussionMessage({
    required int messageId,
    required String email,
    required String role,
    required String message,
  }) {
    return _postJson('update_course_discussion_message.php', {
      'message_id': messageId,
      'email': email.trim().toLowerCase(),
      'role': role.trim().toLowerCase(),
      'message': message,
    });
  }

  Future<Map<String, dynamic>> deleteCourseDiscussionMessage({
    required int messageId,
    required String email,
    required String role,
  }) {
    return _postJson('delete_course_discussion_message.php', {
      'message_id': messageId,
      'email': email.trim().toLowerCase(),
      'role': role.trim().toLowerCase(),
    });
  }

  Future<Map<String, dynamic>> notifyCourseStudents({
    required int courseId,
    required String title,
    required String message,
    required String type,
    String excludeEmail = '',
    String actorEmail = '',
    String actorRole = 'system',
  }) {
    return _postJson('notify_course_students.php', {
      'course_id': courseId,
      'title': title,
      'message': message,
      'type': type,
      'exclude_email': excludeEmail,
      'actor_email': actorEmail,
      'actor_role': actorRole,
    });
  }

  Future<Map<String, dynamic>> notifyResultToStudent({
    required String studentEmail,
    required int courseId,
    required String title,
    required String message,
    required String fileId,
    String actorEmail = '',
    String actorRole = 'teacher',
  }) {
    return _postJson('notify_result_to_student.php', {
      'student_email': studentEmail.trim().toLowerCase(),
      'course_id': courseId,
      'title': title,
      'message': message,
      'file_id': fileId,
      'actor_email': actorEmail,
      'actor_role': actorRole,
    });
  }

  Future<Map<String, dynamic>> getCourseResults(int courseId) {
    return _postJson('get_course_results.php', {'course_id': courseId});
  }

  Future<Map<String, dynamic>> getStudentResults(String email) {
    return _postJson('get_student_results.php', {
      'email': email.trim().toLowerCase(),
    });
  }

  Future<Map<String, dynamic>> toggleResultVisibility({
    required int resultId,
    required String teacherEmail,
    required bool isPrivate,
  }) {
    return _postJson('toggle_result_visibility.php', {
      'result_id': resultId,
      'teacher_email': teacherEmail.trim().toLowerCase(),
      'is_private': isPrivate ? 1 : 0,
    });
  }

  Future<Map<String, dynamic>> uploadMaterial({
    required String teacherEmail,
    required int courseId,
    required File file,
    CancelToken? cancelToken,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    try {
      final base = await getBaseUrl();
      final normalized = base.endsWith('/')
          ? base.substring(0, base.length - 1)
          : base;

      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(minutes: 5),
          receiveTimeout: const Duration(minutes: 5),
          responseType: ResponseType.json,
        ),
      );

      final fileLength = await file.length();
      final fileName = file.path.split(Platform.pathSeparator).last;

      final formData = FormData.fromMap({
        'teacher_email': teacherEmail,
        'course_id': courseId.toString(),
        'material': MultipartFile.fromStream(
          () => file.openRead(),
          fileLength,
          filename: fileName,
        ),
      });

      final response = await dio.post(
        '$normalized/upload_material.php',
        data: formData,
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
      );

      if (response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        _trackDatabaseErrorFromResponse(data);
        return data;
      }
      if (response.data is String) {
        final data = jsonDecode(response.data as String) as Map<String, dynamic>;
        _trackDatabaseErrorFromResponse(data);
        return data;
      }
      return {'success': false, 'message': 'Unexpected server response'};
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        return {
          'success': false,
          'canceled': true,
          'message': 'Upload canceled',
        };
      }
      _setDatabaseError(true);
      return {
        'success': false,
        'message': e.response?.data is Map<String, dynamic>
            ? e.response!.data['message'] ?? 'Upload failed'
            : 'Connection error: ${e.message}',
      };
    } catch (e) {
      _setDatabaseError(true);
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> uploadCourseResult({
    required String teacherEmail,
    required int courseId,
    required File file,
    CancelToken? cancelToken,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    try {
      final base = await getBaseUrl();
      final normalized = base.endsWith('/')
          ? base.substring(0, base.length - 1)
          : base;

      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(minutes: 5),
          receiveTimeout: const Duration(minutes: 5),
          responseType: ResponseType.json,
        ),
      );

      final fileLength = await file.length();
      final fileName = file.path.split(Platform.pathSeparator).last;

      final formData = FormData.fromMap({
        'teacher_email': teacherEmail,
        'course_id': courseId.toString(),
        'result_file': MultipartFile.fromStream(
          () => file.openRead(),
          fileLength,
          filename: fileName,
        ),
      });

      final response = await dio.post(
        '$normalized/upload_result.php',
        data: formData,
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
      );

      if (response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        _trackDatabaseErrorFromResponse(data);
        return data;
      }
      if (response.data is String) {
        final data = jsonDecode(response.data as String) as Map<String, dynamic>;
        _trackDatabaseErrorFromResponse(data);
        return data;
      }
      return {'success': false, 'message': 'Unexpected server response'};
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        return {
          'success': false,
          'canceled': true,
          'message': 'Upload canceled',
        };
      }
      _setDatabaseError(true);
      return {
        'success': false,
        'message': e.response?.data is Map<String, dynamic>
            ? ((e.response!.data as Map<String, dynamic>)['message'] ??
                  'Upload failed')
            : 'Upload error: ${e.message}',
      };
    } catch (e) {
      _setDatabaseError(true);
      return {'success': false, 'message': 'Upload error: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteMaterial({
    required int materialId,
    required String teacherEmail,
  }) {
    return _postJson('delete_material.php', {
      'material_id': materialId,
      'teacher_email': teacherEmail,
    });
  }

  Future<void> _saveUserSession(
    Map<String, dynamic> data,
    String loginEmail,
  ) async {
    final role = (data['role'] ?? 'teacher').toString();
    final email = (data['email'] ?? loginEmail).toString();
    final name = (data['name'] ?? '').toString();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', true);
    await prefs.setString('userRole', role);
    await prefs.setString('userName', name);
    await prefs.setString('userEmail', email);
    if (data['faculty'] != null) {
      await prefs.setString('facultyCode', data['faculty']['code'] ?? '');
      await prefs.setString('facultyName', data['faculty']['name'] ?? '');
    }
  }

  Future<Map<String, String?>> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'role': prefs.getString('userRole'),
      'email': prefs.getString('userEmail'),
      'name': prefs.getString('userName'),
      'facultyCode': prefs.getString('facultyCode'),
      'facultyName': prefs.getString('facultyName'),
    };
  }

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('isLoggedIn') ?? false;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    final savedBaseUrl = prefs.getString('apiBaseUrl');

    final email = prefs.getString('userEmail');
    final role = prefs.getString('userRole');
    if (email != null) {
      await _postJson('signout.php', {
        'email': email,
        'role': role ?? 'student',
      });
    }

    await prefs.clear();
    if (savedBaseUrl != null) {
      await prefs.setString('apiBaseUrl', savedBaseUrl);
    }
  }

  Future<String?> getUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('userRole');
  }

  Future<Map<String, dynamic>> getNotifications(String email) {
    return _get('get_notifications.php', {'email': email.trim().toLowerCase()});
  }

  Future<Map<String, dynamic>> markNotificationRead({
    required String? id,
    required String email,
    bool markAll = false,
  }) {
    return _postJson('mark_notification_read.php', {
      'id': id,
      'email': email.trim().toLowerCase(),
      'mark_all': markAll,
    });
  }

  Future<Map<String, dynamic>> deleteNotifications(String email) {
    return _postJson('delete_notifications.php', {
      'email': email.trim().toLowerCase(),
    });
  }

  Future<Map<String, dynamic>> _get(
    String endpoint,
    Map<String, String> params,
  ) async {
    try {
      final base = await _uri(endpoint);
      final finalUri = base.replace(queryParameters: params);
      final response = await http.get(finalUri);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      _trackDatabaseErrorFromResponse(data);
      return data;
    } catch (e) {
      _setDatabaseError(true);
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  void _setDatabaseError(bool value) {
    if (databaseErrorNotifier.value != value) {
      databaseErrorNotifier.value = value;
    }
  }

  bool _isDatabaseConnectionMessage(String message) {
    final msg = message.toLowerCase();
    return msg.contains('connection error') ||
        msg.contains('database connection failed') ||
        msg.contains('socketexception');
  }

  void _trackDatabaseErrorFromResponse(Map<String, dynamic> data) {
    if (data['success'] == true) {
      _setDatabaseError(false);
      return;
    }
    final message = (data['message'] ?? '').toString();
    if (_isDatabaseConnectionMessage(message)) {
      _setDatabaseError(true);
    } else {
      _setDatabaseError(false);
    }
  }
}
