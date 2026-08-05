import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dart_appwrite/dart_appwrite.dart';
import 'package:pstublc/config/appwrite_storage.dart';

class ApiService {
  static const String _defaultBaseUrl =
      'http://10.239.67.112/MobileApp/pstublcmobileapp/api';
  static final ValueNotifier<bool> databaseErrorNotifier = ValueNotifier(false);
  static final ValueNotifier<bool> noInternetNotifier = ValueNotifier(false);

  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  late final Account _account;

  ApiService._internal() {
    _account = Account(appwriteClient);
  }

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
      debugPrint('POST JSON: $endpoint - ${jsonEncode(body)}');
      final response = await http
          .post(
            await _uri(endpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      debugPrint('RESPONSE: ${response.statusCode} - ${response.body}');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      _trackDatabaseErrorFromResponse(data);
      return data;
    } on SocketException catch (e) {
      debugPrint('Network error: $e');
      _setNoInternet(true);
      return {'success': false, 'message': 'No internet connection'};
    } on http.ClientException catch (e) {
      debugPrint('Client error: $e');
      _setNoInternet(true);
      return {'success': false, 'message': 'No internet connection'};
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('timeout') ||
          msg.contains('connection refused') ||
          msg.contains('network is unreachable')) {
        _setNoInternet(true);
        return {'success': false, 'message': 'No internet connection'};
      }
      debugPrint('Error in _postJson: $e');
      _setDatabaseError(true);
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> _postForm(
    String endpoint,
    Map<String, String> body,
  ) async {
    try {
      debugPrint('POST FORM: $endpoint');
      final response = await http
          .post(await _uri(endpoint), body: body)
          .timeout(const Duration(seconds: 15));

      debugPrint('RESPONSE: ${response.statusCode} - ${response.body}');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      _trackDatabaseErrorFromResponse(data);
      return data;
    } on SocketException catch (e) {
      debugPrint('Network error: $e');
      _setNoInternet(true);
      return {'success': false, 'message': 'No internet connection'};
    } on http.ClientException catch (e) {
      debugPrint('Client error: $e');
      _setNoInternet(true);
      return {'success': false, 'message': 'No internet connection'};
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('timeout') ||
          msg.contains('connection refused') ||
          msg.contains('network is unreachable')) {
        _setNoInternet(true);
        return {'success': false, 'message': 'No internet connection'};
      }
      debugPrint('Error in _postForm: $e');
      _setDatabaseError(true);
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final data = await _postJson('login.php', {
      'email': email.trim().toLowerCase(),
      'password': password,
    });
    return data;
  }

  Future<Map<String, dynamic>> verifyOtp(String email, String otp) async {
    final data = await _postJson('verify_otp.php', {
      'email': email.trim().toLowerCase(),
      'otp': otp,
    });
    if (data['success'] == true) {
      await _saveUserSession(data, email.trim().toLowerCase());
    }
    return data;
  }

  Future<Map<String, dynamic>> resendOtp(String email) {
    return _postJson('resend_otp.php', {'email': email.trim().toLowerCase()});
  }

  // Appwrite OTP Methods
  Future<Map<String, dynamic>> sendAppwriteOtp(String email) async {
    try {
      debugPrint('Sending Appwrite OTP to: $email');
      // Use 'unique' as a placeholder, Appwrite will return the actual User ID (existing or new)
      final token = await _account
          .createEmailToken(
            userId: ID.unique(),
            email: email.trim().toLowerCase(),
          )
          .timeout(const Duration(seconds: 20));

      final actualUserId = token.userId;
      debugPrint(
        'Appwrite OTP sent successfully. Actual UserId: $actualUserId',
      );
      return {'success': true, 'userId': actualUserId};
    } catch (e) {
      debugPrint('Appwrite Error (sendOtp): $e');
      return {
        'success': false,
        'message': 'Failed to send OTP via Appwrite: $e',
      };
    }
  }

  Future<Map<String, dynamic>> verifyAppwriteOtp(
    String userId,
    String secret, {
    Map<String, dynamic>? userData,
  }) async {
    try {
      debugPrint('Verifying Appwrite OTP for $userId');
      await _account
          .createSession(userId: userId, secret: secret)
          .timeout(const Duration(seconds: 20));

      debugPrint('Appwrite verification success.');
      if (userData != null) {
        debugPrint('Saving session.');
        await _saveUserSession(userData, userData['email'] ?? '');
      }

      return {'success': true};
    } catch (e) {
      debugPrint('Appwrite Error (verifyOtp): $e');
      return {'success': false, 'message': 'Invalid or expired OTP: $e'};
    }
  }

  Future<Map<String, dynamic>> signup(Map<String, dynamic> data) {
    return _postJson('signup.php', data);
  }

  Future<Map<String, dynamic>> validateSignup(Map<String, dynamic> data) {
    final payload = Map<String, dynamic>.from(data);
    payload['validate_only'] = true;
    return _postJson('signup.php', payload);
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
    bool verifyOnly = false,
  }) {
    final endpoint = role == 'student'
        ? 'delete_student_account.php'
        : 'delete_teacher_account.php';
    return _postForm(endpoint, {
      'email': email.trim().toLowerCase(),
      'password': password,
      'verify_only': verifyOnly.toString(),
    });
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

  Future<Map<String, dynamic>> createAssignment({
    required int courseId,
    required String teacherEmail,
    required String title,
    required String dueDate,
    required String description,
    bool isPrivate = true,
  }) {
    return _postJson('create_assignment.php', {
      'course_id': courseId,
      'teacher_email': teacherEmail,
      'title': title,
      'due_date': dueDate,
      'description': description,
      'is_private': isPrivate ? 1 : 0,
    });
  }

  Future<Map<String, dynamic>> getAssignments(
    int courseId, {
    String? studentEmail,
  }) {
    final body = <String, dynamic>{'course_id': courseId};
    if (studentEmail != null) body['student_email'] = studentEmail;
    return _postJson('get_assignments.php', body);
  }

  Future<Map<String, dynamic>> deleteAssignment({
    required int id,
    required int courseId,
    required String teacherEmail,
  }) {
    return _postJson('delete_assignment.php', {
      'id': id,
      'course_id': courseId,
      'teacher_email': teacherEmail,
    });
  }

  Future<Map<String, dynamic>> updateAssignment({
    required int id,
    required int courseId,
    required String teacherEmail,
    String? title,
    String? dueDate,
    String? description,
    bool? isPrivate,
  }) {
    final body = <String, dynamic>{
      'id': id,
      'course_id': courseId,
      'teacher_email': teacherEmail,
    };
    if (title != null) body['title'] = title;
    if (dueDate != null) body['due_date'] = dueDate;
    if (description != null) body['description'] = description;
    if (isPrivate != null) body['is_private'] = isPrivate ? 1 : 0;
    return _postJson('update_assignment.php', body);
  }

  Future<Map<String, dynamic>> toggleAssignmentVisibility({
    required int id,
    required int courseId,
    required String teacherEmail,
    required bool isPrivate,
  }) {
    return _postJson('toggle_assignment_visibility.php', {
      'id': id,
      'course_id': courseId,
      'teacher_email': teacherEmail,
      'is_private': isPrivate ? 1 : 0,
    });
  }

  Future<Map<String, dynamic>> getAssignmentCommentMessages({
    required int assignmentId,
    required int courseId,
    required String email,
    required String role,
  }) {
    return _postJson('get_assignment_comment_messages.php', {
      'assignment_id': assignmentId,
      'course_id': courseId,
      'email': email.trim().toLowerCase(),
      'role': role.trim().toLowerCase(),
    });
  }

  Future<Map<String, dynamic>> sendAssignmentCommentMessage({
    required int assignmentId,
    required int courseId,
    required String email,
    required String role,
    required String senderName,
    required String message,
    String targetAudience = 'everyone',
    String? targetStudentEmail,
  }) {
    final body = <String, dynamic>{
      'assignment_id': assignmentId,
      'course_id': courseId,
      'email': email.trim().toLowerCase(),
      'role': role.trim().toLowerCase(),
      'sender_name': senderName,
      'message': message,
      'target_audience': targetAudience,
    };
    if (targetStudentEmail != null && targetStudentEmail.trim().isNotEmpty) {
      body['target_student_email'] = targetStudentEmail.trim().toLowerCase();
    }
    return _postJson('send_assignment_comment_message.php', body);
  }

  Future<Map<String, dynamic>> deleteAssignmentCommentMessages({
    required List<int> messageIds,
    required String email,
    required String role,
  }) {
    return _postJson('delete_assignment_comment_messages.php', {
      'message_ids': messageIds,
      'email': email.trim().toLowerCase(),
      'role': role.trim().toLowerCase(),
    });
  }

  Future<Map<String, dynamic>> submitAssignment({
    required int assignmentId,
    required String studentEmail,
    required List<String> fileIds,
    required List<String> fileNames,
  }) {
    return _postJson('submit_assignment.php', {
      'assignment_id': assignmentId,
      'student_email': studentEmail,
      'file_ids': fileIds,
      'file_names': fileNames,
    });
  }

  Future<Map<String, dynamic>> getAssignmentSubmissions({
    required int assignmentId,
    String? studentEmail,
  }) {
    final body = <String, dynamic>{'assignment_id': assignmentId};
    if (studentEmail != null) body['student_email'] = studentEmail;
    return _postJson('get_assignment_submissions.php', body);
  }

  Future<Map<String, dynamic>> deleteSubmissionFile({
    required int assignmentId,
    required String studentEmail,
    required String fileId,
  }) {
    return _postJson('delete_submission_file.php', {
      'assignment_id': assignmentId,
      'student_email': studentEmail,
      'file_id': fileId,
    });
  }

  Future<Map<String, dynamic>> updateSubmissionStatus({
    required int assignmentId,
    required String studentEmail,
    required bool isTurnedIn,
  }) {
    return _postJson('update_submission_status.php', {
      'assignment_id': assignmentId,
      'student_email': studentEmail,
      'is_turned_in': isTurnedIn ? 1 : 0,
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
    bool isDynamicQr = true,
    int qrInterval = 3,
  }) {
    return _postJson('create_attendance_session.php', {
      'course_id': courseId,
      'teacher_email': teacherEmail,
      'session_date': sessionDate,
      'session_end': sessionEnd,
      'is_dynamic_qr': isDynamicQr ? 1 : 0,
      'qr_interval': qrInterval,
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

  Future<Map<String, dynamic>> markQrAttendance({
    required int sessionId,
    required String email,
    required String qrCode,
  }) {
    return _postJson('mark_qr_attendance.php', {
      'session_id': sessionId,
      'email': email,
      'qr_code': qrCode,
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

  Future<Map<String, dynamic>> getCourseAssignmentOverview(int courseId) {
    return _postJson('get_course_assignment_overview.php', {
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

  Future<Map<String, dynamic>> getCourseRecipients({
    required int courseId,
    required String email,
    required String role,
  }) {
    return _postJson('get_course_recipients.php', {
      'course_id': courseId,
      'email': email.trim().toLowerCase(),
      'role': role.trim().toLowerCase(),
    });
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
    String targetAudience = 'everyone',
    String? targetStudentEmail,
    int? replyToMessageId,
    String? replyToSenderName,
    String? replyToMessage,
  }) {
    final body = <String, dynamic>{
      'course_id': courseId,
      'email': email.trim().toLowerCase(),
      'role': role.trim().toLowerCase(),
      'sender_name': senderName,
      'message': message,
      'target_audience': targetAudience,
    };
    if (targetStudentEmail != null && targetStudentEmail.trim().isNotEmpty) {
      body['target_student_email'] = targetStudentEmail.trim().toLowerCase();
    }
    if (replyToMessageId != null && replyToMessageId > 0) {
      body['reply_to_message_id'] = replyToMessageId;
      body['reply_to_sender_name'] = (replyToSenderName ?? '').trim();
      body['reply_to_message'] = (replyToMessage ?? '').trim();
    }
    return _postJson('send_course_discussion_message.php', body);
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
        final data =
            jsonDecode(response.data as String) as Map<String, dynamic>;
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
        final data =
            jsonDecode(response.data as String) as Map<String, dynamic>;
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
    final email = (data['email'] ?? loginEmail).toString().trim().toLowerCase();
    final name = (data['name'] ?? '').toString();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', true);
    await prefs.setString('userRole', role);
    await prefs.setString('userName', name);
    await prefs.setString(
      'userEmail',
      email.isNotEmpty ? email : loginEmail.trim().toLowerCase(),
    );

    // Handle both flat (student login) and nested (legacy) faculty format
    if (data['faculty_code'] != null) {
      await prefs.setString('facultyCode', data['faculty_code'].toString());
      await prefs.setString(
        'facultyName',
        (data['faculty_name'] ?? '').toString(),
      );
    } else if (data['faculty'] != null && data['faculty'] is Map) {
      final faculty = data['faculty'] as Map;
      await prefs.setString('facultyCode', (faculty['code'] ?? '').toString());
      await prefs.setString('facultyName', (faculty['name'] ?? '').toString());
    }

    debugPrint('Session saved: role=$role, email=$email, name=$name');
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
    if (noInternetNotifier.value) noInternetNotifier.value = false;
    if (databaseErrorNotifier.value != value) {
      databaseErrorNotifier.value = value;
    }
  }

  void _setNoInternet(bool value) {
    if (databaseErrorNotifier.value) databaseErrorNotifier.value = false;
    if (noInternetNotifier.value != value) {
      noInternetNotifier.value = value;
    }
  }

  bool _isDatabaseConnectionMessage(String message) {
    final msg = message.toLowerCase();
    return msg.contains('connection error') ||
        msg.contains('database connection failed') ||
        msg.contains('socketexception');
  }

  void _trackDatabaseErrorFromResponse(Map<String, dynamic> data) {
    // Clear any network errors when we get a valid response
    if (noInternetNotifier.value) noInternetNotifier.value = false;
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
