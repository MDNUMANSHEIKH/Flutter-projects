import 'dart:async';

import 'package:dart_appwrite/dart_appwrite.dart';
import 'package:flutter/material.dart';
import 'package:pstublc/config/appwrite_storage.dart';
import 'package:pstublc/services/api_service.dart';

class CourseDiscussionSection extends StatefulWidget {
  final int courseId;
  final String courseName;
  final String userEmail;
  final String userRole;
  final String userName;
  final ApiService apiService;

  const CourseDiscussionSection({
    super.key,
    required this.courseId,
    required this.courseName,
    required this.userEmail,
    required this.userRole,
    required this.userName,
    required this.apiService,
  });

  @override
  State<CourseDiscussionSection> createState() => _CourseDiscussionSectionState();
}

class _CourseDiscussionSectionState extends State<CourseDiscussionSection> {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  Timer? _refreshTimer;
  int? _editingMessageId;
  String _editingOriginalText = '';
  bool _loading = true;
  bool _sending = false;
  bool _canSubmit = false;
  List<Map<String, dynamic>> _messages = [];
  Map<String, String> _avatarUrlByKey = {};

  @override
  void initState() {
    super.initState();
    _messageController.addListener(_onComposerChanged);
    _loadMessages();
    _refreshTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted) return;
      _loadMessages(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _messageController.removeListener(_onComposerChanged);
    _messageController.dispose();
    _messageFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onComposerChanged() {
    final text = _messageController.text.trim();
    final bool nextCanSubmit;
    if (_editingMessageId != null) {
      nextCanSubmit =
          text.isNotEmpty && text != _editingOriginalText.trim();
    } else {
      nextCanSubmit = text.isNotEmpty;
    }
    if (_canSubmit != nextCanSubmit && mounted) {
      setState(() => _canSubmit = nextCanSubmit);
    }
  }

  void _clearEditingMode() {
    if (!mounted) return;
    setState(() {
      _editingMessageId = null;
      _editingOriginalText = '';
    });
    _onComposerChanged();
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
      final parts = normalized.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
      if (parts.isNotEmpty) {
        if (parts.length == 1) {
          final one = parts.first;
          return one.length >= 2 ? one.substring(0, 2).toUpperCase() : one.substring(0, 1).toUpperCase();
        }
        return (parts[0][0] + parts[1][0]).toUpperCase();
      }
    }
    return fallback.isNotEmpty ? fallback.substring(0, fallback.length >= 2 ? 2 : 1).toUpperCase() : 'U';
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() => _loading = true);
    }
    final result = await widget.apiService.getCourseDiscussionMessages(
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
      setState(() {
        _messages = rows;
        _avatarUrlByKey = avatars;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToBottom();
      });
    } else {
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message'] ?? 'Failed to load discussion')),
        );
      }
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<Map<String, String>> _loadAvatars(List<Map<String, dynamic>> messages) async {
    final senderPrefixes = <String, String>{};
    for (final message in messages) {
      final role = (message['sender_role'] ?? '').toString().trim().toLowerCase();
      final email = (message['sender_email'] ?? '').toString().trim().toLowerCase();
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
          if (existing == null || file.$createdAt.compareTo(existing.$createdAt) > 0) {
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

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sending || !_canSubmit) return;
    setState(() => _sending = true);
    final isEditing = _editingMessageId != null;
    final editingId = _editingMessageId;
    final result = isEditing
        ? await widget.apiService.updateCourseDiscussionMessage(
            messageId: editingId!,
            email: widget.userEmail,
            role: widget.userRole,
            message: text,
          )
        : await widget.apiService.sendCourseDiscussionMessage(
            courseId: widget.courseId,
            email: widget.userEmail,
            role: widget.userRole,
            senderName: widget.userName,
            message: text,
          );
    if (!mounted) return;
    if (result['success'] == true) {
      if (isEditing && editingId != null) {
        final updatedFromApi =
            result['data'] is Map<String, dynamic>
            ? Map<String, dynamic>.from(result['data'] as Map<String, dynamic>)
            : null;
        setState(() {
          _messages = _messages.map((row) {
            final rowId = int.tryParse((row['id'] ?? '').toString()) ?? 0;
            if (rowId != editingId) return row;
            if (updatedFromApi != null) return updatedFromApi;
            return {
              ...row,
              'message': text,
              'is_edited': true,
              'edited_at': DateTime.now().toLocal().toIso8601String(),
            };
          }).toList();
        });
      }
      _messageController.clear();
      _clearEditingMode();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToBottom();
      });
      unawaited(_loadMessages(silent: true));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? 'Failed to send message')),
      );
    }
    if (mounted) {
      setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
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
    for (final msg in _messages) {
      final dayKey = _messageDayKey(msg['created_at']);
      if (dayKey.isNotEmpty && dayKey != lastDay) {
        items.add({
          'type': 'date',
          'label': _formatDateDivider(msg['created_at']),
          'dayKey': dayKey,
        });
        lastDay = dayKey;
      }
      items.add({
        'type': 'message',
        'data': msg,
      });
    }
    return items;
  }

  Future<void> _showOwnMessageActions(Map<String, dynamic> msg) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;

    final messageId = int.tryParse((msg['id'] ?? '').toString()) ?? 0;
    if (messageId <= 0) return;

    if (action == 'edit') {
      final currentText = (msg['message'] ?? '').toString();
      setState(() {
        _editingMessageId = messageId;
        _editingOriginalText = currentText;
      });
      _messageController
        ..text = currentText
        ..selection = TextSelection.fromPosition(
          TextPosition(offset: currentText.length),
        );
      _onComposerChanged();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _messageFocusNode.requestFocus();
      });
      return;
    }

    if (action == 'delete') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete message'),
          content: const Text('Are you sure you want to delete this message?'),
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
      if (confirm != true || !mounted) return;

      final result = await widget.apiService.deleteCourseDiscussionMessage(
        messageId: messageId,
        email: widget.userEmail,
        role: widget.userRole,
      );
      if (!mounted) return;

      if (result['success'] == true) {
        setState(() {
          _messages = _messages.where((row) {
            final rowId = int.tryParse((row['id'] ?? '').toString()) ?? 0;
            return rowId != messageId;
          }).toList();
        });
        if (_editingMessageId == messageId) {
          _messageController.clear();
          _clearEditingMode();
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message'] ?? 'Failed to delete message')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: () => _loadMessages(),
                  child: _messages.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 120),
                            Icon(Icons.chat_bubble_outline, size: 72, color: Colors.grey),
                            SizedBox(height: 12),
                            Center(child: Text('No discussion messages yet. Start the conversation.')),
                          ],
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                          itemCount: _buildTimelineItems().length,
                          itemBuilder: (context, index) {
                            final item = _buildTimelineItems()[index];
                            if (item['type'] == 'date') {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(color: Colors.green.withOpacity(0.22)),
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

                            final msg = Map<String, dynamic>.from(item['data'] as Map);
                            final senderEmail = (msg['sender_email'] ?? '').toString().trim().toLowerCase();
                            final senderRole = (msg['sender_role'] ?? '').toString().trim().toLowerCase();
                            final senderName = (msg['sender_name'] ?? '').toString().trim();
                            final text = (msg['message'] ?? '').toString();
                            final isEdited =
                              msg['is_edited'] == true ||
                              msg['is_edited']?.toString() == '1';
                            final createdAt = msg['created_at'];
                            final isMe = senderEmail.isNotEmpty && senderEmail == widget.userEmail.trim().toLowerCase();
                            final key = '$senderRole|$senderEmail';
                            final avatarUrl = _avatarUrlByKey[key];
                            final isTeacher = senderRole == 'teacher';
                            final bubbleColor = isTeacher
                                ? Colors.green.withOpacity(isMe ? 0.16 : 0.10)
                                : Colors.blueAccent.withOpacity(isMe ? 0.16 : 0.08);
                            final borderColor = isTeacher
                                ? Colors.green.withOpacity(0.18)
                                : Colors.blueAccent.withOpacity(0.16);
                            final align = isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
                            final rowAlign = isMe ? MainAxisAlignment.end : MainAxisAlignment.start;
                            final displayName = isMe
                              ? 'You'
                              : (isTeacher
                                  ? 'Teacher'
                                  : (senderName.isNotEmpty ? senderName : 'Student'));

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                mainAxisAlignment: rowAlign,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  if (!isMe) ...[
                                    _buildAvatar(avatarUrl, senderName, senderRole),
                                    const SizedBox(width: 10),
                                  ],
                                  Flexible(
                                    child: Column(
                                      crossAxisAlignment: align,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              displayName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Container(
                                          constraints: const BoxConstraints(maxWidth: 320),
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: bubbleColor,
                                            borderRadius: BorderRadius.only(
                                              topLeft: const Radius.circular(16),
                                              topRight: const Radius.circular(16),
                                              bottomLeft: Radius.circular(isMe ? 16 : 4),
                                              bottomRight: Radius.circular(isMe ? 4 : 16),
                                            ),
                                            border: Border.all(color: borderColor),
                                          ),
                                          child: InkWell(
                                            onLongPress: isMe
                                                ? () => _showOwnMessageActions(msg)
                                                : null,
                                            borderRadius: BorderRadius.circular(12),
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 2),
                                              child: Text(
                                                text,
                                                style: const TextStyle(fontSize: 15, height: 1.35),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              _formatTimestamp(createdAt),
                                              style: TextStyle(
                                                color: Colors.grey[600],
                                                fontSize: 11,
                                              ),
                                            ),
                                            if (isEdited) ...[
                                              const SizedBox(width: 6),
                                              Text(
                                                'edited',
                                                style: TextStyle(
                                                  color: Colors.grey[600],
                                                  fontSize: 11,
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isMe) ...[
                                    const SizedBox(width: 10),
                                    _buildAvatar(avatarUrl, senderName, senderRole),
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
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.18))),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_editingMessageId != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              const Text(
                                'Editing message',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black54,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                tooltip: 'Cancel edit',
                                onPressed: () {
                                  _messageController.clear();
                                  _clearEditingMode();
                                },
                                icon: const Icon(Icons.close, size: 18),
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                                constraints: const BoxConstraints(
                                  minHeight: 28,
                                  minWidth: 28,
                                ),
                              ),
                            ],
                          ),
                        ),
                      TextField(
                        controller: _messageController,
                        focusNode: _messageFocusNode,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        decoration: InputDecoration(
                          hintText: _editingMessageId != null
                              ? 'Edit message...'
                              : 'Write a message...',
                          filled: true,
                          fillColor: Colors.grey.withOpacity(0.08),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 0),
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: (_sending || !_canSubmit) ? null : _sendMessage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send_rounded, size: 20),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAvatar(String? avatarUrl, String name, String role) {
    final isTeacher = role == 'teacher';
    final initials = _initials(name, fallback: isTeacher ? 'T' : 'S');
    final bg = isTeacher ? Colors.green.withOpacity(0.12) : Colors.blueAccent.withOpacity(0.12);
    final fg = isTeacher ? Colors.green : Colors.blueAccent;
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
                    style: TextStyle(fontWeight: FontWeight.bold, color: fg, fontSize: 12),
                  ),
                )
              : Image.network(
                  avatarUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Center(
                      child: Text(
                        initials,
                        style: TextStyle(fontWeight: FontWeight.bold, color: fg, fontSize: 12),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}