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
  TabController? _tabController;
  Timer? _refreshTimer;
  Timer? _highlightTimer;
  int? _editingMessageId;
  String _editingOriginalText = '';
  bool _loading = true;
  bool _sending = false;
  bool _canSubmit = false;
  bool _showScrollToBottom = false;
  bool _selectionMode = false;
  final Set<int> _selectedOwnMessageIds = <int>{};
  int? _replyToMessageId;
  String _replyToSenderName = '';
  String _replyToText = '';
  int? _highlightedMessageId;
  List<Map<String, dynamic>> _messages = [];
  Map<String, String> _avatarUrlByKey = {};

  @override
  void initState() {
    super.initState();
    _messageController.addListener(_onComposerChanged);
    _scrollController.addListener(_onScrollChanged);
    _loadMessages(stickToLatest: true);
    _refreshTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted) return;
      _loadMessages(silent: true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextController = DefaultTabController.maybeOf(context);
    if (_tabController == nextController) return;
    _tabController?.removeListener(_handleParentTabChange);
    _tabController = nextController;
    _tabController?.addListener(_handleParentTabChange);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _highlightTimer?.cancel();
    _tabController?.removeListener(_handleParentTabChange);
    _messageController.removeListener(_onComposerChanged);
    _scrollController.removeListener(_onScrollChanged);
    _messageController.dispose();
    _messageFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleParentTabChange() {
    final controller = _tabController;
    if (controller == null || !mounted) return;

    if (controller.index == 0 && !controller.indexIsChanging) {
      unawaited(
        _loadMessages(
          silent: false,
          scrollAnimated: false,
          stickToLatest: true,
        ),
      );
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

  void _highlightMessage(int messageId) {
    _highlightTimer?.cancel();
    if (!mounted) return;
    setState(() => _highlightedMessageId = messageId);
    _highlightTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted) return;
      if (_highlightedMessageId == messageId) {
        setState(() => _highlightedMessageId = null);
      }
    });
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

  void _clearReplyMode() {
    if (!mounted) return;
    setState(() {
      _replyToMessageId = null;
      _replyToSenderName = '';
      _replyToText = '';
    });
  }

  void _startReplyToMessage(Map<String, dynamic> msg) {
    final messageId = int.tryParse((msg['id'] ?? '').toString()) ?? 0;
    if (messageId <= 0) return;

    final senderName = (msg['sender_name'] ?? '').toString().trim();
    final senderRole = (msg['sender_role'] ?? '').toString().trim().toLowerCase();
    final senderEmail = (msg['sender_email'] ?? '').toString().trim().toLowerCase();
    final text = (msg['message'] ?? '').toString().trim();
    final isMe = senderEmail == widget.userEmail.trim().toLowerCase();

    setState(() {
      _editingMessageId = null;
      _editingOriginalText = '';
      _replyToMessageId = messageId;
      _replyToSenderName = isMe
          ? 'You'
          : (senderRole == 'teacher'
              ? 'Teacher'
              : (senderName.isNotEmpty ? senderName : 'Student'));
      _replyToText = text;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _messageFocusNode.requestFocus();
      _messageController.selection = TextSelection.fromPosition(
        TextPosition(offset: _messageController.text.length),
      );
    });
  }

  void _scrollToMessage(int messageId) {
    final findIndex = _buildTimelineItems().indexWhere((item) {
      if (item['type'] != 'message') return false;
      final data = item['data'] as Map<String, dynamic>?;
      if (data == null) return false;
      final id = int.tryParse((data['id'] ?? '').toString()) ?? 0;
      return id == messageId;
    });

    if (findIndex == -1) return;

    _highlightMessage(messageId);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      const estimatedRowHeight = 128.0;
      final targetOffset = (findIndex * estimatedRowHeight) - 100;
      final clampedTarget = targetOffset.clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.animateTo(
        clampedTarget,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );

      Future.delayed(const Duration(milliseconds: 420), () {
        if (!mounted) return;
        _highlightMessage(messageId);
      });
    });
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

  Future<void> _loadMessages({
    bool silent = false,
    bool scrollAnimated = false,
    bool stickToLatest = false,
  }) async {
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
      if (stickToLatest) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _scrollToBottom(animated: scrollAnimated);
        });
      }
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
            replyToMessageId: _replyToMessageId,
            replyToSenderName: _replyToSenderName,
            replyToMessage: _replyToText,
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
      _clearReplyMode();
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

  void _scrollToBottom({bool animated = true}) {
    if (!_scrollController.hasClients) return;
    if (animated) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
    if (_showScrollToBottom && mounted) {
      setState(() => _showScrollToBottom = false);
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
    final messageId = int.tryParse((msg['id'] ?? '').toString()) ?? 0;
    if (messageId <= 0) return;

    setState(() {
      if (!_selectionMode) {
        _selectedOwnMessageIds.clear();
      }
      _selectionMode = true;
      _selectedOwnMessageIds.add(messageId);
    });
  }

  void _toggleOwnMessageSelection(int messageId) {
    if (!_selectionMode) return;
    setState(() {
      if (_selectedOwnMessageIds.contains(messageId)) {
        _selectedOwnMessageIds.remove(messageId);
      } else {
        _selectedOwnMessageIds.add(messageId);
      }
      if (_selectedOwnMessageIds.isEmpty) {
        _selectionMode = false;
      }
    });
  }

  void _closeSelectionMode() {
    if (!_selectionMode) return;
    setState(() {
      _selectionMode = false;
      _selectedOwnMessageIds.clear();
    });
  }

  Map<String, dynamic>? _findMessageById(int messageId) {
    for (final row in _messages) {
      final rowId = int.tryParse((row['id'] ?? '').toString()) ?? 0;
      if (rowId == messageId) return row;
    }
    return null;
  }

  void _editSelectedMessage() {
    if (_selectedOwnMessageIds.length != 1) return;
    final selectedId = _selectedOwnMessageIds.first;
    final msg = _findMessageById(selectedId);
    if (msg == null) return;

    final currentText = (msg['message'] ?? '').toString();
    setState(() {
      _selectionMode = false;
      _selectedOwnMessageIds.clear();
      _replyToMessageId = null;
      _replyToSenderName = '';
      _replyToText = '';
      _editingMessageId = selectedId;
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
  }

  Future<void> _deleteSelectedMessages() async {
    if (_selectedOwnMessageIds.isEmpty) return;
    final count = _selectedOwnMessageIds.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message'),
        content: Text(
          count == 1
              ? 'Are you sure you want to delete this message?'
              : 'Are you sure you want to delete these $count messages?',
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
    if (confirm != true || !mounted) return;

    final ids = _selectedOwnMessageIds.toList();
    final deletedIds = <int>{};
    bool hasFailure = false;
    for (final id in ids) {
      final result = await widget.apiService.deleteCourseDiscussionMessage(
        messageId: id,
        email: widget.userEmail,
        role: widget.userRole,
      );
      if (result['success'] == true) {
        deletedIds.add(id);
      } else {
        hasFailure = true;
      }
    }
    if (!mounted) return;

    setState(() {
      _messages = _messages.where((row) {
        final rowId = int.tryParse((row['id'] ?? '').toString()) ?? 0;
        return !deletedIds.contains(rowId);
      }).toList();
      _selectedOwnMessageIds.removeWhere((id) => deletedIds.contains(id));
      if (_selectedOwnMessageIds.isEmpty) {
        _selectionMode = false;
      }
    });

    if (hasFailure) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Some messages could not be deleted')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
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
                                padding: EdgeInsets.fromLTRB(
                                  12,
                                  _selectionMode ? 74 : 12,
                                  12,
                                  18,
                                ),
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
                            final messageId = int.tryParse((msg['id'] ?? '').toString()) ?? 0;
                            final text = (msg['message'] ?? '').toString();
                            final replyToMessageId = int.tryParse(
                              (msg['reply_to_message_id'] ?? '').toString(),
                            ) ?? 0;
                            final replySender = (msg['reply_to_sender_name'] ?? '').toString().trim();
                            final replyText = (msg['reply_to_message'] ?? '').toString().trim();
                            final replySenderLower = replySender.toLowerCase();
                            final currentUserName = widget.userName.trim().toLowerCase();
                            final currentUserEmail = widget.userEmail.trim().toLowerCase();

                            Map<String, dynamic>? repliedMessage;
                            if (replyToMessageId > 0) {
                              for (final row in _messages) {
                                final rowId = int.tryParse((row['id'] ?? '').toString()) ?? 0;
                                if (rowId == replyToMessageId) {
                                  repliedMessage = row;
                                  break;
                                }
                              }
                            }

                            final repliedSenderRole =
                                (repliedMessage?['sender_role'] ?? '')
                                    .toString()
                                    .trim()
                                    .toLowerCase();
                            final repliedSenderEmail =
                                (repliedMessage?['sender_email'] ?? '')
                                    .toString()
                                    .trim()
                                    .toLowerCase();
                            final repliedSenderName =
                                (repliedMessage?['sender_name'] ?? '')
                                    .toString()
                                    .trim();
                            final isRepliedMessageDeleted =
                              replyToMessageId > 0 && repliedMessage == null;
                            final replyPreviewText = isRepliedMessageDeleted
                              ? 'Message deleted'
                              : replyText;

                            final targetIsCurrentUser = repliedSenderEmail.isNotEmpty
                                ? repliedSenderEmail == currentUserEmail
                                : (replySenderLower == 'you' ||
                                      (currentUserName.isNotEmpty &&
                                          (replySenderLower == currentUserName ||
                                              repliedSenderName.toLowerCase() == currentUserName)));

                            final repliedToLabel = targetIsCurrentUser
                                ? 'you'
                                : (repliedSenderRole == 'teacher' ||
                                      replySenderLower == 'teacher'
                                    ? 'Teacher'
                                    : (repliedSenderName.isNotEmpty
                                        ? repliedSenderName
                                        : (replySender.isNotEmpty ? replySender : 'message')));
                            final isEdited =
                              msg['is_edited'] == true ||
                              msg['is_edited']?.toString() == '1';
                            final createdAt = msg['created_at'];
                            final isMe = senderEmail.isNotEmpty && senderEmail == widget.userEmail.trim().toLowerCase();
                            final isSelectedOwn =
                              isMe && messageId > 0 && _selectedOwnMessageIds.contains(messageId);
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
                            final isHighlighted =
                              messageId > 0 && _highlightedMessageId == messageId;
                            final highlightedBubbleColor = isTeacher
                              ? Colors.green.withOpacity(0.24)
                              : Colors.blueAccent.withOpacity(0.22);
                            final highlightedBorderColor = isTeacher
                              ? Colors.green.withOpacity(0.55)
                              : Colors.blueAccent.withOpacity(0.45);

                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 140),
                              curve: Curves.easeOut,
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                              decoration: BoxDecoration(
                                color: isSelectedOwn
                                    ? Colors.blue.withOpacity(0.10)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                  mainAxisAlignment: rowAlign,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (!isMe) ...[
                                      GestureDetector(
                                        onTap: () {
                                          _showSenderProfile(
                                            avatarUrl: avatarUrl,
                                            name: senderName,
                                            email: senderEmail,
                                            role: senderRole,
                                          );
                                        },
                                        child: _buildAvatar(avatarUrl, senderName, senderRole),
                                      ),
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
                                              if (replyText.isNotEmpty) ...[
                                                const SizedBox(width: 8),
                                                const Icon(
                                                  Icons.reply_rounded,
                                                  size: 14,
                                                  color: Colors.black54,
                                                ),
                                                const SizedBox(width: 4),
                                                Flexible(
                                                  child: Text(
                                                    'replied to $repliedToLabel',
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w600,
                                                      color: Colors.black54,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Dismissible(
                                            key: ValueKey('discussion_swipe_${msg['id']}_${msg['created_at']}'),
                                            direction: _selectionMode
                                                ? DismissDirection.none
                                                : (isMe
                                                      ? DismissDirection.endToStart
                                                      : DismissDirection.startToEnd),
                                            dismissThresholds: const {
                                              DismissDirection.startToEnd: 0.28,
                                              DismissDirection.endToStart: 0.28,
                                            },
                                            confirmDismiss: (_) async {
                                              if (_selectionMode) return false;
                                              _startReplyToMessage(msg);
                                              return false;
                                            },
                                            background: Container(
                                              alignment: isMe
                                                  ? Alignment.centerRight
                                                  : Alignment.centerLeft,
                                              padding: const EdgeInsets.symmetric(horizontal: 18),
                                              child: Icon(
                                                Icons.reply_rounded,
                                                color: Colors.green.shade600,
                                                size: 22,
                                              ),
                                            ),
                                            child: replyText.isNotEmpty
                                                ? Column(
                                                    mainAxisSize: MainAxisSize.min,
                                                    crossAxisAlignment: align,
                                                    children: [
                                                      GestureDetector(
                                                        onTap: () {
                                                          final replyId = int.tryParse(
                                                            (msg['reply_to_message_id'] ?? '').toString(),
                                                          ) ?? 0;
                                                          if (replyId > 0) {
                                                            _scrollToMessage(replyId);
                                                          }
                                                        },
                                                        child: Container(
                                                          constraints: const BoxConstraints(maxWidth: 320),
                                                          padding: const EdgeInsets.all(12),
                                                          decoration: BoxDecoration(
                                                            color: Colors.grey.withOpacity(0.10),
                                                            borderRadius: BorderRadius.circular(14),
                                                            border: Border.all(
                                                              color: Colors.grey.withOpacity(0.20),
                                                            ),
                                                          ),
                                                          child: Column(
                                                            mainAxisSize: MainAxisSize.min,
                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                            children: [
                                                              Text(
                                                                replyPreviewText,
                                                                maxLines: 3,
                                                                overflow: TextOverflow.ellipsis,
                                                                style: TextStyle(
                                                                  fontSize: 13,
                                                                  height: 1.3,
                                                                  color: Colors.black54,
                                                                  fontStyle: isRepliedMessageDeleted
                                                                      ? FontStyle.italic
                                                                      : FontStyle.normal,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                      AnimatedSlide(
                                                        duration: const Duration(milliseconds: 180),
                                                        curve: Curves.easeOut,
                                                        offset: isHighlighted
                                                            ? const Offset(0, -0.055)
                                                            : const Offset(0, -0.04),
                                                        child: GestureDetector(
                                                          behavior: HitTestBehavior.opaque,
                                                          onTap: (_selectionMode && isMe)
                                                            ? () => _toggleOwnMessageSelection(messageId)
                                                              : null,
                                                          onLongPress: isMe
                                                              ? () => _showOwnMessageActions(msg)
                                                              : null,
                                                          child: AnimatedContainer(
                                                            duration: const Duration(milliseconds: 180),
                                                            curve: Curves.easeOut,
                                                            constraints: const BoxConstraints(maxWidth: 320),
                                                            padding: const EdgeInsets.all(12),
                                                            decoration: BoxDecoration(
                                                              color: isSelectedOwn
                                                                  ? Colors.blue.withOpacity(0.20)
                                                                  : (isHighlighted
                                                                        ? highlightedBubbleColor
                                                                        : bubbleColor),
                                                              borderRadius: BorderRadius.only(
                                                                topLeft: const Radius.circular(16),
                                                                topRight: const Radius.circular(16),
                                                                bottomLeft: Radius.circular(isMe ? 16 : 4),
                                                                bottomRight: Radius.circular(isMe ? 4 : 16),
                                                              ),
                                                              border: Border.all(
                                                                color: isSelectedOwn
                                                                    ? Colors.blue.withOpacity(0.46)
                                                                    : (isHighlighted
                                                                          ? highlightedBorderColor
                                                                          : borderColor),
                                                              ),
                                                            ),
                                                            child: Text(
                                                              text,
                                                              style: const TextStyle(
                                                                fontSize: 15,
                                                                height: 1.35,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  )
                                                : AnimatedSlide(
                                                    duration: const Duration(milliseconds: 180),
                                                    curve: Curves.easeOut,
                                                    offset: isHighlighted
                                                        ? const Offset(0, -0.03)
                                                        : Offset.zero,
                                                    child: GestureDetector(
                                                      behavior: HitTestBehavior.opaque,
                                                      onTap: (_selectionMode && isMe)
                                                        ? () => _toggleOwnMessageSelection(messageId)
                                                          : null,
                                                      onLongPress: isMe
                                                          ? () => _showOwnMessageActions(msg)
                                                          : null,
                                                      child: AnimatedContainer(
                                                        duration: const Duration(milliseconds: 180),
                                                        curve: Curves.easeOut,
                                                        constraints: const BoxConstraints(maxWidth: 320),
                                                        padding: const EdgeInsets.all(12),
                                                        decoration: BoxDecoration(
                                                          color: isSelectedOwn
                                                              ? Colors.blue.withOpacity(0.20)
                                                              : (isHighlighted
                                                                    ? highlightedBubbleColor
                                                                    : bubbleColor),
                                                          borderRadius: BorderRadius.only(
                                                            topLeft: const Radius.circular(16),
                                                            topRight: const Radius.circular(16),
                                                            bottomLeft: Radius.circular(isMe ? 16 : 4),
                                                            bottomRight: Radius.circular(isMe ? 4 : 16),
                                                          ),
                                                          border: Border.all(
                                                            color: isSelectedOwn
                                                                ? Colors.blue.withOpacity(0.46)
                                                                : (isHighlighted
                                                                      ? highlightedBorderColor
                                                                      : borderColor),
                                                          ),
                                                        ),
                                                        child: Text(
                                                          text,
                                                          style: const TextStyle(
                                                            fontSize: 15,
                                                            height: 1.35,
                                                          ),
                                                        ),
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
                                      GestureDetector(
                                        onTap: () {
                                          _showSenderProfile(
                                            avatarUrl: avatarUrl,
                                            name: senderName,
                                            email: senderEmail,
                                            role: senderRole,
                                          );
                                        },
                                        child: _buildAvatar(avatarUrl, senderName, senderRole),
                                      ),
                                    ],
                                  ],
                                ),
                            );
                                },
                              ),
                      ),
              ),
              if (_selectionMode)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.96),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.grey.withOpacity(0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${_selectedOwnMessageIds.length} selected',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.10),
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            tooltip: 'Delete',
                            onPressed: _selectedOwnMessageIds.isEmpty
                                ? null
                                : _deleteSelectedMessages,
                            iconSize: 18,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: _selectedOwnMessageIds.length == 1
                                ? Colors.grey.withOpacity(0.14)
                                : Colors.grey.withOpacity(0.08),
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            tooltip: 'Edit',
                            onPressed: _selectedOwnMessageIds.length == 1
                                ? _editSelectedMessage
                                : null,
                            iconSize: 18,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: Icon(
                              Icons.edit_outlined,
                              color: _selectedOwnMessageIds.length == 1
                                  ? Colors.black87
                                  : Colors.grey,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.10),
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            tooltip: 'Close',
                            onPressed: _closeSelectionMode,
                            iconSize: 18,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(Icons.close, color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 10,
                child: Center(
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 170),
                    scale: _showScrollToBottom && !_loading && _messages.isNotEmpty
                        ? 1
                        : 0,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 170),
                      opacity: _showScrollToBottom && !_loading && _messages.isNotEmpty
                          ? 1
                          : 0,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _scrollToBottom,
                          borderRadius: BorderRadius.circular(30),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            child: Icon(
                              Icons.arrow_downward_rounded,
                              color: Colors.black,
                              size: 44,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
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
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.green.withOpacity(0.22)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.edit_outlined, size: 15, color: Colors.green),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text(
                                        'Editing message',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _editingOriginalText,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
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
                        ),
                      if (_replyToMessageId != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.green.withOpacity(0.22)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.reply_rounded, size: 15, color: Colors.green),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Replying to ${_replyToSenderName.isNotEmpty ? _replyToSenderName : 'message'}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _replyToText,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Cancel reply',
                                  onPressed: _clearReplyMode,
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

  void _showSenderProfile({
    required String? avatarUrl,
    required String name,
    required String email,
    required String role,
  }) {
    final normalizedRole = role.trim().toLowerCase();
    final isTeacher = normalizedRole == 'teacher';
    final fallbackName = isTeacher ? 'Teacher' : 'Student';
    final finalName = name.trim().isNotEmpty
        ? name.trim()
        : (email.trim().toLowerCase() == widget.userEmail.trim().toLowerCase() &&
                  widget.userName.trim().isNotEmpty
              ? widget.userName.trim()
              : fallbackName);
    final finalEmail = email.trim().isNotEmpty ? email.trim() : 'Email not available';
    final initials = _initials(finalName, fallback: isTeacher ? 'T' : 'S');

    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
                                      errorBuilder: (context, error, stackTrace) => Center(
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