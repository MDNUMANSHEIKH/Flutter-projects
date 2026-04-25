import 'dart:async';

import 'package:dart_appwrite/dart_appwrite.dart';
import 'package:flutter/material.dart';
import 'package:pstublc/config/appwrite_storage.dart';
import 'package:pstublc/services/api_service.dart';

class AssignmentCommentSection extends StatefulWidget {
  final int assignmentId;
  final int courseId;
  final String userEmail;
  final String userRole;
  final String userName;
  final ApiService apiService;

  const AssignmentCommentSection({
    super.key,
    required this.assignmentId,
    required this.courseId,
    required this.userEmail,
    required this.userRole,
    required this.userName,
    required this.apiService,
  });

  @override
  State<AssignmentCommentSection> createState() =>
      _AssignmentCommentSectionState();
}

class _AssignmentCommentSectionState extends State<AssignmentCommentSection> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _composerScrollController = ScrollController();
  Timer? _refreshTimer;

  final List<Map<String, String>> _recipientOptions = [];
  final Map<String, String> _userDirectory = {};
  List<Map<String, dynamic>> _comments = [];
  Map<String, String> _avatarUrlByKey = {};

  bool _loading = true;
  bool _loadingRecipients = true;
  bool _sending = false;
  bool _canSend = false;

  String _targetAudience = 'everyone';
  String _targetStudentEmail = '';
  String _selectedRecipientKey = 'everyone';
  final Set<int> _selectedMessageIds = {};
  bool _isSelectionMode = false;
  bool _showScrollToBottom = false;

  @override
  void initState() {
    super.initState();
    _messageController.addListener(_onComposerChanged);
    _scrollController.addListener(_onScrollChanged);
    _loadRecipients();
    _loadComments();
    _refreshTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted) return;
      unawaited(_loadComments(silent: true));
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _messageController.removeListener(_onComposerChanged);
    _scrollController.removeListener(_onScrollChanged);
    _messageController.dispose();
    _composerScrollController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onComposerChanged() {
    final nextCanSend = _messageController.text.trim().isNotEmpty;
    if (_canSend != nextCanSend && mounted) {
      setState(() => _canSend = nextCanSend);
    }
  }

  void _onScrollChanged() {
    if (!_scrollController.hasClients || !mounted) return;
    final remaining =
        _scrollController.position.maxScrollExtent - _scrollController.position.pixels;
    final shouldShow = remaining > 140;
    if (shouldShow != _showScrollToBottom) {
      setState(() => _showScrollToBottom = shouldShow);
    }
  }

  void _scrollToBottom({bool animated = true}) {
    if (!_scrollController.hasClients) return;
    if (animated) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  Future<void> _loadRecipients() async {
    final result = await widget.apiService.getCourseRecipients(
      courseId: widget.courseId,
      email: widget.userEmail,
      role: widget.userRole,
    );
    if (!mounted) return;

    if (result['success'] == true) {
      final teacher = result['teacher'] is Map
          ? Map<String, dynamic>.from(result['teacher'] as Map)
          : <String, dynamic>{};
      final teacherEmail = (teacher['email'] ?? '')
          .toString()
          .trim()
          .toLowerCase();

      final rows = (result['students'] as List? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      final myEmail = widget.userEmail.trim().toLowerCase();
      final myRole = widget.userRole.trim().toLowerCase();

      final options = <Map<String, String>>[
        {
          'key': 'everyone',
          'label': 'Everyone',
          'audience': 'everyone',
          'email': '',
        },
      ];

      final Map<String, String> newDirectory = {};

      final teacherName = (teacher['name'] ?? '').toString().trim();
      if (teacherEmail.isNotEmpty && teacherName.isNotEmpty) {
        newDirectory[teacherEmail] = teacherName;
      }

      if (teacherEmail.isNotEmpty && myRole == 'student') {
        options.add({
          'key': 'teacher|$teacherEmail',
          'label': teacherName.isNotEmpty ? 'Teacher($teacherName)' : 'Teacher',
          'audience': 'teacher',
          'email': teacherEmail,
        });
      }

      for (final student in rows) {
        final studentName = (student['name'] ?? '').toString().trim();
        final studentEmail = (student['email'] ?? '')
            .toString()
            .trim()
            .toLowerCase();

        if (studentEmail.isNotEmpty && studentName.isNotEmpty) {
          newDirectory[studentEmail] = studentName;
        }

        if (studentEmail.isEmpty || studentEmail == myEmail) continue;
        options.add({
          'key': 'student|$studentEmail',
          'label': studentName.isNotEmpty ? studentName : studentEmail,
          'audience': 'student',
          'email': studentEmail,
        });
      }

      setState(() {
        _userDirectory
          ..clear()
          ..addAll(newDirectory);
        _recipientOptions
          ..clear()
          ..addAll(options);
        _selectedRecipientKey = 'everyone';
        _targetAudience = 'everyone';
        _targetStudentEmail = '';
        _loadingRecipients = false;
      });
    } else {
      setState(() => _loadingRecipients = false);
    }
  }

  Future<void> _loadComments({bool silent = false}) async {
    if (!silent) {
      setState(() => _loading = true);
    }
    final result = await widget.apiService.getAssignmentCommentMessages(
      assignmentId: widget.assignmentId,
      courseId: widget.courseId,
      email: widget.userEmail,
      role: widget.userRole,
    );
    if (!mounted) return;

    if (result['success'] == true) {
      final rows = (result['messages'] as List? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      final avatars = await _loadAvatars(rows);
      if (!mounted) return;

      final bool stickToBottom = !_scrollController.hasClients ||
          (_scrollController.position.maxScrollExtent - _scrollController.position.pixels < 100);

      setState(() {
        _comments = rows;
        _avatarUrlByKey = avatars;
        if (!silent) _loading = false;
      });

      if (stickToBottom || !silent) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom(animated: silent);
        });
      }
    } else {
      if (!silent) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Failed to load comments'),
          ),
        );
      }
    }
  }



  String _formatTimestamp(dynamic value) {
    if (value == null) return '';
    try {
      final dt = DateTime.parse(value.toString()).toLocal();
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      return '${hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $period';
    } catch (_) {
      return value.toString();
    }
  }

  String _sanitizeEmail(String email) {
    return email.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  }

  String _profilePrefix(String role, String email) {
    final safeEmail = _sanitizeEmail(email);
    return '${role.trim().toLowerCase()}_profile__${safeEmail}__';
  }

  String _avatarUrlFromFileId(String fileId) {
    return '$appwriteEndpoint/storage/buckets/$materialsBucketId/files/$fileId/view?project=$appwriteProjectId';
  }

  String _initials(String name, {String fallback = ''}) {
    final normalized = name.trim();
    if (normalized.isNotEmpty) {
      final parts = normalized
          .split(RegExp(r'\s+'))
          .where((p) => p.isNotEmpty)
          .toList();
      if (parts.isNotEmpty) {
        if (parts.length == 1) {
          final one = parts.first;
          return one.length >= 2
              ? one.substring(0, 2).toUpperCase()
              : one.substring(0, 1).toUpperCase();
        }
        return (parts[0][0] + parts[1][0]).toUpperCase();
      }
    }
    return fallback.isNotEmpty
        ? fallback.substring(0, fallback.length >= 2 ? 2 : 1).toUpperCase()
        : 'U';
  }

  Future<Map<String, String>> _loadAvatars(
    List<Map<String, dynamic>> messages,
  ) async {
    final senderPrefixes = <String, String>{};
    for (final message in messages) {
      final role = (message['sender_role'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final email = (message['sender_email'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (email.isEmpty || (role != 'teacher' && role != 'student')) continue;
      senderPrefixes['$role|$email'] = _profilePrefix(role, email);
    }

    if (senderPrefixes.isEmpty) return <String, String>{};

    try {
      final files = await appwriteStorage.listFiles(
        bucketId: materialsBucketId,
        queries: [Query.limit(500)],
      );
      final latestByKey = <String, dynamic>{};
      for (final file in files.files) {
        for (final entry in senderPrefixes.entries) {
          final key = entry.key;
          final prefix = entry.value;
          if (!file.name.startsWith(prefix)) continue;
          final existing = latestByKey[key];
          if (existing == null ||
              file.$createdAt.compareTo(existing.$createdAt) > 0) {
            latestByKey[key] = file;
          }
          break;
        }
      }

      final urls = <String, String>{};
      latestByKey.forEach((key, file) {
        urls[key] = _avatarUrlFromFileId(file.$id);
      });
      return urls;
    } catch (_) {
      return <String, String>{};
    }
  }

  String _formatDateDivider(dynamic value) {
    if (value == null) return '';
    try {
      final dt = DateTime.parse(value.toString()).toLocal();
      const monthNames = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      final month = monthNames[dt.month - 1];
      final now = DateTime.now();
      if (dt.year == now.year) {
        return '${dt.day} $month';
      }
      return '${dt.day} $month ${dt.year}';
    } catch (_) {
      return value.toString();
    }
  }

  String _messageDayKey(dynamic value) {
    if (value == null) return '';
    try {
      final dt = DateTime.parse(value.toString()).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return value.toString();
    }
  }

  List<Map<String, dynamic>> _buildTimelineItems() {
    final items = <Map<String, dynamic>>[];
    String lastDay = '';
    for (final msg in _comments) {
      final dayKey = _messageDayKey(msg['created_at']);
      if (dayKey.isNotEmpty && dayKey != lastDay) {
        items.add({
          'type': 'date',
          'label': _formatDateDivider(msg['created_at']),
          'dayKey': dayKey,
        });
        lastDay = dayKey;
      }
      items.add({'type': 'message', 'data': msg});
    }
    return items;
  }

  Future<void> _sendComment() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sending || _loadingRecipients) return;

    setState(() => _sending = true);
    final result = await widget.apiService.sendAssignmentCommentMessage(
      assignmentId: widget.assignmentId,
      courseId: widget.courseId,
      email: widget.userEmail,
      role: widget.userRole,
      senderName: widget.userName,
      message: text,
      targetAudience: _targetAudience,
      targetStudentEmail: _targetAudience == 'student'
          ? _targetStudentEmail
          : null,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      final now = DateTime.now().toLocal().toIso8601String();
      final newRow = <String, dynamic>{
        'id': result['message_id'] ?? 0,
        'assignment_id': widget.assignmentId,
        'course_id': widget.courseId,
        'sender_email': widget.userEmail.trim().toLowerCase(),
        'sender_name': widget.userName,
        'sender_role': widget.userRole.trim().toLowerCase(),
        'target_audience': _targetAudience,
        'target_student_email': _targetAudience == 'student'
            ? _targetStudentEmail
            : null,
        'message': text,
        'created_at': now,
      };
      setState(() {
        _comments = [..._comments, newRow];
      });
      _messageController.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToBottom();
      });
      unawaited(_loadComments(silent: true));
      FocusScope.of(context).unfocus();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? 'Failed to send comment')),
      );
    }

    if (mounted) setState(() => _sending = false);
  }

  void _toggleMessageSelection(int id) {
    if (!mounted) return;
    setState(() {
      if (_selectedMessageIds.contains(id)) {
        _selectedMessageIds.remove(id);
        if (_selectedMessageIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedMessageIds.add(id);
        _isSelectionMode = true;
      }
    });
  }

  void _clearSelection() {
    if (!mounted) return;
    setState(() {
      _selectedMessageIds.clear();
      _isSelectionMode = false;
    });
  }

  Future<void> _deleteSelectedMessages() async {
    if (_selectedMessageIds.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Messages'),
        content: Text(
          'Are you sure you want to delete ${_selectedMessageIds.length} message(s)?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final idsToDelete = _selectedMessageIds.toList();
    _clearSelection();

    final result = await widget.apiService.deleteAssignmentCommentMessages(
      messageIds: idsToDelete,
      email: widget.userEmail,
      role: widget.userRole,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      setState(() {
        _comments.removeWhere((m) => idsToDelete.contains(m['id']));
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Failed to delete messages'),
        ),
      );
    }
  }

  String _displayName(Map<String, dynamic> msg) {
    final senderName = (msg['sender_name'] ?? '').toString().trim();
    final senderEmail = (msg['sender_email'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final senderRole = (msg['sender_role'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final me = senderEmail == widget.userEmail.trim().toLowerCase();

    if (me) return 'You';
    return _resolveSenderName(
      name: senderName,
      email: senderEmail,
      role: senderRole,
    );
  }

  bool _isRolePlaceholderName(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'teacher' ||
        normalized == 'student' ||
        normalized == 'user';
  }

  String _resolveSenderName({
    required String name,
    required String email,
    required String role,
  }) {
    final normalizedName = name.trim();
    final normalizedEmail = email.trim().toLowerCase();
    final myEmail = widget.userEmail.trim().toLowerCase();
    final myName = widget.userName.trim();

    String result = 'User';

    if (normalizedEmail.isNotEmpty &&
        _userDirectory.containsKey(normalizedEmail)) {
      result = _userDirectory[normalizedEmail]!;
    } else if (normalizedName.isNotEmpty &&
        !_isRolePlaceholderName(normalizedName)) {
      result = normalizedName;
    } else if (normalizedEmail.isNotEmpty &&
        normalizedEmail == myEmail &&
        myName.isNotEmpty &&
        !_isRolePlaceholderName(myName)) {
      result = myName;
    } else if (normalizedEmail.isNotEmpty) {
      result = normalizedEmail;
    }

    if (role.trim().toLowerCase() == 'teacher') {
      if (_isRolePlaceholderName(result) || result == normalizedEmail)
        return 'Teacher';
      return 'Teacher($result)';
    }

    return result;
  }

  String _targetLabelForMessage(Map<String, dynamic> msg) {
    final audience = (msg['target_audience'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final targetEmail = (msg['target_student_email'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final myEmail = widget.userEmail.trim().toLowerCase();
    if (audience == 'teacher') {
      final hit = _recipientOptions
          .where((item) => (item['audience'] ?? '') == 'teacher')
          .toList();
      if (hit.isNotEmpty) return 'To: ${hit.first['label']}';
      return 'To: Teacher';
    }
    if (audience == 'student') {
      if (targetEmail.isNotEmpty && targetEmail == myEmail) {
        return 'To: You';
      }
      final hit = _recipientOptions.where((item) {
        return (item['audience'] ?? '') == 'student' &&
            (item['email'] ?? '').toLowerCase() == targetEmail;
      }).toList();
      if (hit.isNotEmpty) return 'To: ${hit.first['label'] ?? targetEmail}';
      return 'To: Student';
    }
    return 'To: Everyone';
  }

  void _selectRecipient(String key) {
    final hit = _recipientOptions
        .where((item) => (item['key'] ?? '') == key)
        .toList();
    if (hit.isEmpty) return;
    final selected = hit.first;
    setState(() {
      _selectedRecipientKey = key;
      _targetAudience = (selected['audience'] ?? 'everyone').toLowerCase();
      _targetStudentEmail = (selected['email'] ?? '').trim().toLowerCase();
      if (_targetAudience != 'student') _targetStudentEmail = '';
    });
  }

  String _selectedRecipientLabel() {
    final hit = _recipientOptions
        .where((item) => (item['key'] ?? '') == _selectedRecipientKey)
        .toList();
    if (hit.isEmpty) return 'Everyone';
    final raw = (hit.first['label'] ?? 'Everyone').trim();
    return raw;
  }

  double _recipientMenuOffsetY() {
    final visibleItems = _recipientOptions
        .where((item) => (item['key'] ?? '') != _selectedRecipientKey)
        .length;
    final cappedVisibleItems = visibleItems > 10 ? 10 : visibleItems;
    final menuHeight = (cappedVisibleItems * 36.0) + 16.0;
    return -(menuHeight + 2.0);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadComments,
                child: _loading
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 180),
                          Center(child: CircularProgressIndicator()),
                        ],
                      )
                    : _comments.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 140),
                          Center(
                            child: Text(
                              'No comments yet. Start the conversation.',
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        itemCount: _buildTimelineItems().length,
                        itemBuilder: (context, index) {
                          final item = _buildTimelineItems()[index];
                          if (item['type'] == 'date') {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: Colors.green.withOpacity(0.22),
                                    ),
                                  ),
                                  child: Text(
                                    (item['label'] ?? '').toString(),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }

                          final msg = Map<String, dynamic>.from(
                            item['data'] as Map,
                          );
                          final msgId = (msg['id'] ?? 0) as int;
                          final senderRole = (msg['sender_role'] ?? '')
                              .toString()
                              .trim()
                              .toLowerCase();
                          final senderName = (msg['sender_name'] ?? '')
                              .toString()
                              .trim();
                          final senderEmail = (msg['sender_email'] ?? '')
                              .toString()
                              .trim()
                              .toLowerCase();
                          final isMe =
                              senderEmail ==
                              widget.userEmail.trim().toLowerCase();
                          final isTeacher = senderRole == 'teacher';
                          final key = '$senderRole|$senderEmail';
                          final avatarUrl = _avatarUrlByKey[key];
                          final displayName = _displayName(msg);
                          final text = (msg['message'] ?? '').toString();
                          final isSelected = _selectedMessageIds.contains(
                            msgId,
                          );

                          final bubbleColor = isTeacher
                              ? Colors.green.withOpacity(isMe ? 0.16 : 0.10)
                              : Colors.blueAccent.withOpacity(
                                  isMe ? 0.16 : 0.08,
                                );
                          final borderColor = isTeacher
                              ? Colors.green.withOpacity(0.18)
                              : Colors.blueAccent.withOpacity(0.16);

                          return Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 4,
                              horizontal: 12,
                            ),
                            color: isSelected
                                ? Colors.blue.withOpacity(0.10)
                                : Colors.transparent,
                            child: Row(
                              mainAxisAlignment: isMe
                                  ? MainAxisAlignment.end
                                  : MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (!isMe) ...[
                                  GestureDetector(
                                    onTap: () {
                                      if (_isSelectionMode) return;
                                      _showSenderProfile(
                                        avatarUrl: avatarUrl,
                                        name: senderName,
                                        email: senderEmail,
                                        role: senderRole,
                                      );
                                    },
                                      child: _buildAvatar(
                                        avatarUrl,
                                        displayName,
                                        senderRole,
                                      ),
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                Flexible(
                                  child: Column(
                                    crossAxisAlignment: isMe
                                        ? CrossAxisAlignment.end
                                        : CrossAxisAlignment.start,
                                    children: [
                                      Tooltip(
                                        message: senderEmail.isNotEmpty
                                            ? senderEmail
                                            : 'Unknown Email',
                                        child: Text(
                                          displayName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      GestureDetector(
                                        onLongPress: isMe
                                            ? () =>
                                                  _toggleMessageSelection(msgId)
                                            : null,
                                        onTap: _isSelectionMode && isMe
                                            ? () =>
                                                  _toggleMessageSelection(msgId)
                                            : null,
                                        child: Container(
                                          constraints: const BoxConstraints(
                                            maxWidth: 320,
                                          ),
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: bubbleColor,
                                            borderRadius: BorderRadius.only(
                                              topLeft: const Radius.circular(
                                                16,
                                              ),
                                              topRight: const Radius.circular(
                                                16,
                                              ),
                                              bottomLeft: Radius.circular(
                                                isMe ? 16 : 4,
                                              ),
                                              bottomRight: Radius.circular(
                                                isMe ? 4 : 16,
                                              ),
                                            ),
                                            border: Border.all(
                                              color: borderColor,
                                            ),
                                          ),
                                          child: Text(
                                            text,
                                            style: const TextStyle(
                                              fontSize: 15,
                                              height: 1.35,
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 6,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          if ((msg['target_audience'] ?? '')
                                                  .toString()
                                                  .toLowerCase() ==
                                              'student')
                                            Tooltip(
                                              message:
                                                  (msg['target_student_email'] ??
                                                          '')
                                                      .toString()
                                                      .isNotEmpty
                                                  ? msg['target_student_email']
                                                        .toString()
                                                  : 'Student Email',
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 3,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.orange
                                                      .withOpacity(0.12),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        999,
                                                      ),
                                                ),
                                                child: Text(
                                                  _targetLabelForMessage(msg),
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.orange,
                                                  ),
                                                ),
                                              ),
                                            )
                                          else if ((msg['target_audience'] ??
                                                      '')
                                                  .toString()
                                                  .toLowerCase() ==
                                              'teacher')
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 3,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.purple
                                                    .withOpacity(0.12),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                              child: Text(
                                                _targetLabelForMessage(msg),
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.purple,
                                                ),
                                              ),
                                            )
                                          else
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 3,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.green.withOpacity(
                                                  0.12,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                              child: const Text(
                                                'To: Everyone',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.green,
                                                ),
                                              ),
                                            ),
                                          Text(
                                            _formatTimestamp(msg['created_at']),
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.black54,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                if (isMe) ...[
                                  const SizedBox(width: 10),
                                  GestureDetector(
                                    onTap: () {
                                      if (_isSelectionMode) return;
                                      _showSenderProfile(
                                        avatarUrl: avatarUrl,
                                        name: senderName,
                                        email: senderEmail,
                                        role: senderRole,
                                      );
                                    },
                                    child: _buildAvatar(
                                      avatarUrl,
                                      widget.userName,
                                      senderRole,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ),
            SafeArea(
              top: false,
              bottom: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  border: Border(
                    top: BorderSide(color: Colors.grey.withOpacity(0.18)),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text(
                      'To',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      height: 48,
                      child: _loadingRecipients
                          ? Container(
                              width: 92,
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Center(
                                child: SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.green,
                                  ),
                                ),
                              ),
                            )
                          : PopupMenuButton<String>(
                              onSelected: _selectRecipient,
                              position: PopupMenuPosition.over,
                              offset: Offset(0, _recipientMenuOffsetY()),
                              constraints: const BoxConstraints(
                                minWidth: 110,
                                maxWidth: 140,
                                maxHeight: 376,
                              ),
                              itemBuilder: (context) {
                                final menuOptions = _recipientOptions
                                    .where(
                                      (item) =>
                                          (item['key'] ?? '') !=
                                          _selectedRecipientKey,
                                    )
                                    .toList();
                                return menuOptions
                                    .map(
                                      (item) => PopupMenuItem<String>(
                                        value: item['key'] ?? 'everyone',
                                        height: 36,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                        ),
                                        child:
                                            (item['email'] ?? '')
                                                .toString()
                                                .isNotEmpty
                                            ? Tooltip(
                                                message: item['email']
                                                    .toString(),
                                                child: Container(
                                                  width: double.infinity,
                                                  height: 36,
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: Text(
                                                    item['label'] ?? 'Everyone',
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                              )
                                            : Container(
                                                width: double.infinity,
                                                height: 36,
                                                alignment: Alignment.centerLeft,
                                                child: Text(
                                                  item['label'] ?? 'Everyone',
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                      ),
                                    )
                                    .toList();
                              },
                              child: Container(
                                constraints: const BoxConstraints(
                                  minWidth: 80,
                                  maxWidth: 110,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                alignment: Alignment.centerLeft,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        _selectedRecipientLabel(),
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.green[700],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.arrow_drop_down,
                                      size: 18,
                                      color: Colors.green[700],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: TextField(
                          controller: _messageController,
                          maxLines: 5,
                          minLines: 1,
                          decoration: const InputDecoration(
                            hintText: 'Write a comment...',
                            hintStyle: TextStyle(
                              fontSize: 14,
                              color: Colors.black,
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 13),
                          ),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: (_canSend && !_sending) ? _sendComment : null,
                      child: Container(
                        width: 54,
                        height: 48,
                        decoration: BoxDecoration(
                          color: _canSend
                              ? Colors.green[600]
                              : Colors.grey.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: _sending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  Icons.send_rounded,
                                  color: _canSend
                                      ? Colors.white
                                      : Colors.grey[400],
                                  size: 22,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_isSelectionMode)
          Positioned(
            top: 20,
            right: 20,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(30),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.grey.withOpacity(0.15)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        '${_selectedMessageIds.length} selected',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _deleteSelectedMessages,
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.red,
                        size: 20,
                      ),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _clearSelection,
                      icon: Icon(
                        Icons.close,
                        color: Colors.grey[600],
                        size: 20,
                      ),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
          ),
        // Scroll to bottom arrow
        Positioned(
          left: 0,
          right: 0,
          bottom: 72,
          child: Center(
            child: AnimatedScale(
              duration: const Duration(milliseconds: 170),
              scale: _showScrollToBottom && !_loading && _comments.isNotEmpty ? 1 : 0,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 170),
                opacity: _showScrollToBottom && !_loading && _comments.isNotEmpty ? 1 : 0,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _scrollToBottom(animated: true),
                    borderRadius: BorderRadius.circular(30),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.12),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                        border: Border.all(color: Colors.grey.withOpacity(0.1)),
                      ),
                      child: const Icon(
                        Icons.arrow_downward_rounded,
                        color: Colors.black87,
                        size: 26,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showSenderProfile({
    required String? avatarUrl,
    required String name,
    required String email,
    required String role,
  }) {
    final normalizedRole = role.trim().toLowerCase();
    final isTeacher = normalizedRole == 'teacher';
    final finalName = _resolveSenderName(name: name, email: email, role: role);
    final finalEmail = email.trim().isNotEmpty
        ? email.trim()
        : 'Email not available';
    final initials = _initials(finalName, fallback: isTeacher ? 'T' : 'S');

    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 32,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: SizedBox(
            width: 280,
            height: 220,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Stack(
                children: [
                  Positioned(
                    top: -6,
                    right: -6,
                    child: IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, size: 20),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: Colors.green.withOpacity(0.14),
                          child: ClipOval(
                            child: SizedBox(
                              width: 60,
                              height: 60,
                              child: avatarUrl == null
                                  ? Center(
                                      child: Text(
                                        initials,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: Colors.green,
                                          fontSize: 20,
                                        ),
                                      ),
                                    )
                                  : Image.network(
                                      avatarUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              Center(
                                                child: Text(
                                                  initials,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.green,
                                                    fontSize: 20,
                                                  ),
                                                ),
                                              ),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          finalName,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          finalEmail,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAvatar(String? avatarUrl, String name, String role) {
    final isTeacher = role == 'teacher';
    final initials = _initials(name, fallback: isTeacher ? 'T' : 'S');
    final bg = isTeacher
        ? Colors.green[100]
        : Colors.blue[100];
    final fg = isTeacher ? Colors.green[800] : Colors.blue[800];
    return CircleAvatar(
      radius: 18,
      backgroundColor: bg,
      child: ClipOval(
        child: SizedBox(
          width: 36,
          height: 36,
          child: avatarUrl == null
              ? Center(
                  child: Text(
                    initials,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: fg,
                      fontSize: 12,
                    ),
                  ),
                )
              : Image.network(
                  avatarUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Center(
                      child: Text(
                        initials,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: fg,
                          fontSize: 12,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
