import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pstublc/services/api_service.dart';
import 'package:pstublc/widgets/assignment_comment_section.dart';
import 'package:pstublc/widgets/assignment_submission_section.dart';
import 'package:pstublc/config/appwrite_storage.dart';

class TeacherAssignmentSection extends StatefulWidget {
  final int courseId;
  final String teacherEmail;
  final String teacherName;
  final Map<String, String>? studentProfileImageUrlByEmail;

  const TeacherAssignmentSection({
    super.key,
    required this.courseId,
    required this.teacherEmail,
    required this.teacherName,
    this.studentProfileImageUrlByEmail,
  });

  @override
  State<TeacherAssignmentSection> createState() =>
      _TeacherAssignmentSectionState();
}

class _TeacherAssignmentSectionState extends State<TeacherAssignmentSection> {
  final ApiService _apiService = ApiService();
  bool _loading = true;
  bool _showAssignmentHistory = false;
  bool _showStudentDetails = false;
  bool _isDialogVisible = false;
  List<_AssignmentItem> _assignments = [];
  Future<Map<String, dynamic>>? _studentOverviewFuture;
  Timer? _countdownTimer;
  DateTime _assignmentDeadline(DateTime dueDate) {
    if (dueDate.hour == 0 && dueDate.minute == 0 && dueDate.second == 0) {
      return DateTime(dueDate.year, dueDate.month, dueDate.day, 23, 59, 59);
    }
    return dueDate;
  }

  bool _isAssignmentActive(_AssignmentItem assignment) {
    final now = DateTime.now();
    final deadline = _assignmentDeadline(assignment.dueDate);
    return !now.isAfter(deadline);
  }

  String _formatRemainingTime(_AssignmentItem assignment) {
    final now = DateTime.now();
    final deadline = _assignmentDeadline(assignment.dueDate);
    final diff = deadline.difference(now);
    if (diff.isNegative) {
      return 'Expired';
    }

    final totalSeconds = diff.inSeconds;
    final days = totalSeconds ~/ 86400;
    final hours = (totalSeconds % 86400) ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');

    if (days > 0) {
      return '${days}d ${hours}h ${mm}m ${ss}s left';
    }
    return '${hours}h ${mm}m ${ss}s left';
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _formatDateTime(DateTime date) {
    return '${_formatDate(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
  }

  String _formatFeedDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Aprl',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final now = DateTime.now();
    final base = '${date.day} ${months[date.month - 1]}';
    if (date.year == now.year) {
      return base;
    }
    return '$base ${date.year}';
  }

  String _formatDateTimeWithAmPm(DateTime dateTime) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Aprl',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour12 = dateTime.hour == 0
        ? 12
        : (dateTime.hour > 12 ? dateTime.hour - 12 : dateTime.hour);
    final amPm = dateTime.hour >= 12 ? 'PM' : 'AM';
    return '${dateTime.day} ${months[dateTime.month - 1]} ${dateTime.year} ${hour12.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')} $amPm';
  }

  Future<void> _loadAssignments() async {
    setState(() => _loading = true);
    final result = await _apiService.getAssignments(widget.courseId);
    if (!mounted) return;

    if (result['success'] == true) {
      final rows = (result['assignments'] as List? ?? [])
          .map(
            (item) => _AssignmentItem.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
      setState(() => _assignments = rows);
    } else {
      _showMsg(result['message'] ?? 'Failed to load assignments');
    }

    setState(() => _loading = false);
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _showCreateAssignmentDialog() async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    DateTime? selectedDate = DateTime.now();
    bool isPrivate = true;

    _isDialogVisible = true;
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final canCreate =
                titleController.text.trim().isNotEmpty &&
                descriptionController.text.trim().isNotEmpty;
            return AlertDialog(
              title: const Text('Create Assignment'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => setDialogState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        hintText: 'Give the title of the assignment',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () async {
                        final now = DateTime.now();
                        final today = DateTime(now.year, now.month, now.day);
                        final picked = await showDatePicker(
                          context: dialogContext,
                          initialDate:
                              selectedDate != null &&
                                  selectedDate!.isBefore(today)
                              ? today
                              : (selectedDate ?? today),
                          firstDate: today,
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (picked != null) {
                          setDialogState(() => selectedDate = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Date',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.calendar_today),
                        ),
                        child: Text(
                          selectedDate == null
                              ? 'Select a date'
                              : _formatDate(selectedDate!),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: descriptionController,
                      maxLines: 4,
                      onChanged: (_) => setDialogState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        hintText: 'Give the description',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: isPrivate,
                      onChanged: (value) {
                        setDialogState(() => isPrivate = value ?? true);
                      },
                      title: const Text('Private'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: canCreate
                      ? () async {
                          final title = titleController.text.trim();
                          final description = descriptionController.text.trim();
                          if (title.isEmpty ||
                              description.isEmpty ||
                              selectedDate == null) {
                            _showMsg(
                              'Please fill title, date, and description',
                            );
                            return;
                          }

                          final result = await _apiService.createAssignment(
                            courseId: widget.courseId,
                            teacherEmail: widget.teacherEmail,
                            title: title,
                            dueDate: _formatDate(selectedDate!),
                            description: description,
                            isPrivate: isPrivate,
                          );

                          if (!mounted) return;

                          if (result['success'] == true) {
                            Navigator.pop(dialogContext, true);
                          } else {
                            _showMsg(
                              result['message'] ??
                                  'Failed to create assignment',
                            );
                          }
                        }
                      : null,
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
    _isDialogVisible = false;

    titleController.dispose();
    descriptionController.dispose();

    if (!mounted || created != true) return;

    _showMsg('Assignment created successfully');
    await _loadAssignments();
  }

  Future<void> _showEditAssignmentDialog(_AssignmentItem assignment) async {
    final originalTitle = assignment.title.trim();
    final originalDescription = assignment.description.trim();
    final originalDate = DateTime(
      assignment.dueDate.year,
      assignment.dueDate.month,
      assignment.dueDate.day,
    );

    final titleController = TextEditingController(text: originalTitle);
    final descriptionController = TextEditingController(
      text: originalDescription,
    );
    DateTime selectedDate = originalDate;

    _isDialogVisible = true;
    final updated = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final currentTitle = titleController.text.trim();
            final currentDescription = descriptionController.text.trim();
            final normalizedDate = DateTime(
              selectedDate.year,
              selectedDate.month,
              selectedDate.day,
            );
            final isTitleChanged = currentTitle != originalTitle;
            final isDescriptionChanged =
                currentDescription != originalDescription;
            final isDateChanged = !normalizedDate.isAtSameMomentAs(
              originalDate,
            );

            final canSave =
                currentTitle.isNotEmpty &&
                currentDescription.isNotEmpty &&
                (isTitleChanged || isDescriptionChanged || isDateChanged);
            return AlertDialog(
              title: const Text('Edit Assignment'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => setDialogState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        hintText: 'Give the title of the assignment',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () async {
                        final now = DateTime.now();
                        final today = DateTime(now.year, now.month, now.day);
                        final picked = await showDatePicker(
                          context: dialogContext,
                          initialDate: selectedDate.isBefore(today)
                              ? today
                              : selectedDate,
                          firstDate: today,
                          lastDate: DateTime.now().add(
                            const Duration(days: 3650),
                          ),
                        );
                        if (picked != null) {
                          setDialogState(() => selectedDate = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Date',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.calendar_today),
                        ),
                        child: Text(_formatDate(selectedDate)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      maxLines: 4,
                      onChanged: (_) => setDialogState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        hintText: 'Give the description',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: canSave
                      ? () async {
                          final title = titleController.text.trim();
                          final description = descriptionController.text.trim();
                          if (title.isEmpty || description.isEmpty) {
                            _showMsg('Please fill title and description');
                            return;
                          }
                          final normalizedDate = DateTime(
                            selectedDate.year,
                            selectedDate.month,
                            selectedDate.day,
                          );
                          final isTitleChanged = title != originalTitle;
                          final isDescriptionChanged =
                              description != originalDescription;
                          final isDateChanged = !normalizedDate
                              .isAtSameMomentAs(originalDate);

                          if (!isTitleChanged &&
                              !isDescriptionChanged &&
                              !isDateChanged) {
                            return;
                          }

                          if (isDateChanged) {
                            final now = DateTime.now();
                            final today = DateTime(
                              now.year,
                              now.month,
                              now.day,
                            );
                            if (normalizedDate.isBefore(today)) {
                              _showMsg('Past date is not allowed');
                              return;
                            }
                          }

                          final result = await _apiService.updateAssignment(
                            id: assignment.id,
                            courseId: widget.courseId,
                            teacherEmail: widget.teacherEmail,
                            title: isTitleChanged ? title : null,
                            dueDate: isDateChanged
                                ? _formatDate(normalizedDate)
                                : null,
                            description: isDescriptionChanged
                                ? description
                                : null,
                          );

                          if (!mounted) return;

                          if (result['success'] == true) {
                            Navigator.pop(dialogContext, true);
                          } else {
                            _showMsg(
                              result['message'] ??
                                  'Failed to update assignment',
                            );
                          }
                        }
                      : null,
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    _isDialogVisible = false;

    titleController.dispose();
    descriptionController.dispose();

    if (!mounted || updated != true) return;

    _showMsg('Assignment updated successfully');
    await _loadAssignments();
  }

  Future<void> _deleteAssignment(_AssignmentItem assignment) async {
    _isDialogVisible = true;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Assignment'),
        content: const Text('Are you sure you want to delete this assignment?'),
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
    _isDialogVisible = false;
    if (confirm != true) return;

    // Show loading state for deep deletion
    _showMsg('Deleting assignment and related files...');

    try {
      // 1. Fetch all submissions to get file IDs for Appwrite cleanup
      final subRes = await _apiService.getAssignmentSubmissions(
        assignmentId: assignment.id,
      );
      if (subRes['success'] == true) {
        final List submissions = subRes['submissions'] ?? [];
        for (final sub in submissions) {
          final List fileIds = sub['file_ids'] is List ? sub['file_ids'] : [];

          for (final fid in fileIds) {
            try {
              await appwriteStorage.deleteFile(
                bucketId: materialsBucketId,
                fileId: fid.toString(),
              );
            } catch (e) {
              debugPrint('Error deleting Appwrite file $fid: $e');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error during submission file cleanup: $e');
    }

    final result = await _apiService.deleteAssignment(
      id: assignment.id,
      courseId: widget.courseId,
      teacherEmail: widget.teacherEmail,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      _showMsg('Assignment deleted');
      await _loadAssignments();
    } else {
      _showMsg(result['message'] ?? 'Failed to delete assignment');
    }
  }

  Future<void> _toggleAssignmentVisibility({
    required _AssignmentItem assignment,
    required bool makePrivate,
  }) async {
    final result = await _apiService.toggleAssignmentVisibility(
      id: assignment.id,
      courseId: widget.courseId,
      teacherEmail: widget.teacherEmail,
      isPrivate: makePrivate,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      _showMsg(
        makePrivate ? 'Assignment set to private' : 'Assignment set to public',
      );
      await _loadAssignments();
    } else {
      _showMsg(result['message'] ?? 'Failed to update visibility');
    }
  }

  Future<void> _stopSubmission(_AssignmentItem assignment) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop Submission'),
        content: const Text(
          'Are you sure you want to stop submissions for this assignment?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final now = DateTime.now();
    // Use 1 minute ago to ensure it's considered expired immediately by logic
    final stopTime = now.subtract(const Duration(minutes: 1));

    final result = await _apiService.updateAssignment(
      id: assignment.id,
      courseId: widget.courseId,
      teacherEmail: widget.teacherEmail,
      dueDate: _formatDateTime(stopTime),
    );

    if (!mounted) return;

    if (result['success'] == true) {
      _showMsg('Submissions stopped');
      await _loadAssignments();
    } else {
      _showMsg(result['message'] ?? 'Failed to stop submissions');
    }
  }

  Future<void> _showResubmissionDialog(_AssignmentItem assignment) async {
    DateTime? selectedDate = DateTime.now().add(const Duration(days: 1));
    bool isPrivate = true;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Resubmission'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Set a new deadline to reactivate this assignment.'),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final now = DateTime.now();
                    final today = DateTime(now.year, now.month, now.day);
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate ?? today,
                      firstDate: today,
                      lastDate: DateTime(2101),
                    );
                    if (picked != null) {
                      setDialogState(() => selectedDate = picked);
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'New Due Date',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today),
                    ),
                    child: Text(_formatDate(selectedDate!)),
                  ),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  title: const Text('Private'),
                  value: isPrivate,
                  onChanged: (val) {
                    setDialogState(() => isPrivate = val ?? true);
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Reactivate'),
              ),
            ],
          );
        },
      ),
    );

    if (confirm != true || selectedDate == null) return;

    final result = await _apiService.updateAssignment(
      id: assignment.id,
      courseId: widget.courseId,
      teacherEmail: widget.teacherEmail,
      dueDate: _formatDate(selectedDate!),
      isPrivate: isPrivate,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      _showMsg('Assignment reactivated');
      await _loadAssignments();
    } else {
      _showMsg(result['message'] ?? 'Failed to reactivate assignment');
    }
  }

  void _toggleStudentDetails() {
    setState(() {
      _showStudentDetails = !_showStudentDetails;
    });
  }

  String _studentInitialsFromName(String name) {
    if (name.isEmpty) return '';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  Widget _buildStudentDetails() {
    _studentOverviewFuture ??= _apiService.getCourseAssignmentOverview(
      widget.courseId,
    );

    return FutureBuilder<Map<String, dynamic>>(
      future: _studentOverviewFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.only(top: 100),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || snapshot.data?['success'] != true) {
          return Center(
            child: Text(snapshot.data?['message'] ?? 'Failed to load details'),
          );
        }

        final data = snapshot.data!;
        final totalAssignments = data['total_assignments'] as int;
        final overview = data['overview'] as List;

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  Text(
                    '$totalAssignments',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  const Text(
                    'Total Assignments',
                    style: TextStyle(fontSize: 14, color: Colors.blue),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ...overview.map((student) {
              final name = student['name'].toString();
              final email = student['email'].toString().toLowerCase().trim();
              final submitted = student['total_submitted'] as int;
              final missed = student['total_missed'] as int;
              final percentage = student['score_percentage'] as int;
              final initials = _studentInitialsFromName(name);

              final imageUrl =
                  widget.studentProfileImageUrlByEmail?[email] ?? '';

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.blue.withOpacity(0.1),
                      backgroundImage: imageUrl.isNotEmpty
                          ? NetworkImage(imageUrl)
                          : null,
                      child: imageUrl.isEmpty
                          ? Text(
                              initials,
                              style: const TextStyle(
                                color: Colors.blue,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            email,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Submitted: $submitted',
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          'Missed: $missed',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '$percentage%',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Future<void> _showAssignmentOverview(_AssignmentItem assignment) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _TeacherAssignmentDetailPage(
          assignment: assignment,
          teacherName: widget.teacherName,
          formatFeedDate: _formatFeedDate,
          formatDateTimeWithAmPm: _formatDateTimeWithAmPm,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadAssignments();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_isDialogVisible) return;
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredAssignments = _assignments.where((assignment) {
      final isActive = _isAssignmentActive(assignment);
      if (_showAssignmentHistory) {
        return !isActive;
      }
      return isActive;
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadAssignments,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _showCreateAssignmentDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('Create Assignment'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 46),
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => setState(() {
                    _showAssignmentHistory = !_showAssignmentHistory;
                    _showStudentDetails = false;
                  }),
                  icon: Icon(
                    _showAssignmentHistory ? Icons.dashboard : Icons.history,
                  ),
                  label: Text(_showAssignmentHistory ? 'Active' : 'History'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 46),
                    backgroundColor: _showAssignmentHistory
                        ? Colors.blueAccent
                        : Colors.blueGrey,
                    foregroundColor: Colors.white,
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: _toggleStudentDetails,
            icon: const Icon(Icons.people_outline),
            label: const Text('Student Details'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 46),
              backgroundColor: const Color(0xFF673AB7),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_showStudentDetails)
            _buildStudentDetails()
          else if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 100),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (filteredAssignments.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 80),
              child: Center(
                child: Text(
                  _showAssignmentHistory
                      ? 'No history assignments yet.'
                      : 'No active assignments yet.',
                ),
              ),
            )
          else
            ...filteredAssignments.map(
              (assignment) => InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _showAssignmentOverview(assignment),
                child: Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  elevation: 0,
                  color: assignment.isPrivate
                      ? const Color(0xFFFBEAEA)
                      : const Color(0xFFE8ECE5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: assignment.isPrivate
                          ? const Color(0xFFE7B7B7)
                          : const Color(0xFFBDE3C7),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: assignment.isPrivate
                                    ? Colors.red
                                    : Colors.green,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.assignment_outlined,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'You posted a new assignment: ${assignment.title}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    assignment.isPrivate ? 'Private' : 'Public',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: assignment.isPrivate
                                          ? Colors.red
                                          : Colors.green,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Created: ${_formatDateTimeWithAmPm(assignment.createdAt)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Last Date: ${_formatFeedDate(assignment.dueDate)}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.black54,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Remaining: ${_formatRemainingTime(assignment)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert),
                              onSelected: (value) {
                                if (value == 'edit') {
                                  _showEditAssignmentDialog(assignment);
                                } else if (value == 'public') {
                                  _toggleAssignmentVisibility(
                                    assignment: assignment,
                                    makePrivate: false,
                                  );
                                } else if (value == 'private') {
                                  _toggleAssignmentVisibility(
                                    assignment: assignment,
                                    makePrivate: true,
                                  );
                                } else if (value == 'stop') {
                                  _stopSubmission(assignment);
                                } else if (value == 'reactivate') {
                                  _showResubmissionDialog(assignment);
                                } else if (value == 'delete') {
                                  _deleteAssignment(assignment);
                                }
                              },
                              itemBuilder: (context) => [
                                if (assignment.isPrivate)
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
                                  )
                                else
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
                                if (_isAssignmentActive(assignment))
                                  const PopupMenuItem(
                                    value: 'stop',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.stop_circle_outlined,
                                          size: 18,
                                          color: Colors.orange,
                                        ),
                                        SizedBox(width: 8),
                                        Text('Stop Submission'),
                                      ],
                                    ),
                                  )
                                else
                                  const PopupMenuItem(
                                    value: 'reactivate',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.restore,
                                          size: 18,
                                          color: Colors.blue,
                                        ),
                                        SizedBox(width: 8),
                                        Text('Resubmission'),
                                      ],
                                    ),
                                  ),
                                if (_isAssignmentActive(assignment))
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.edit_outlined,
                                          size: 18,
                                          color: Colors.blue,
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
                                        Icons.delete_outline,
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
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AssignmentItem {
  final int id;
  final int courseId;
  final String teacherEmail;
  final String title;
  final DateTime dueDate;
  final DateTime createdAt;
  final DateTime? editedAt;
  final bool isPrivate;
  final String description;

  const _AssignmentItem({
    required this.id,
    required this.courseId,
    required this.teacherEmail,
    required this.title,
    required this.dueDate,
    required this.createdAt,
    required this.editedAt,
    required this.isPrivate,
    required this.description,
  });

  static DateTime _parseDueDate(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) {
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day);
    }

    final parsed = DateTime.tryParse(raw);
    if (parsed != null) {
      return parsed;
    }

    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  factory _AssignmentItem.fromJson(Map<String, dynamic> json) {
    return _AssignmentItem(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      courseId: int.tryParse(json['course_id']?.toString() ?? '') ?? 0,
      teacherEmail: (json['teacher_email'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      dueDate: _parseDueDate(json['due_date']),
      createdAt:
          DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.now(),
      editedAt: DateTime.tryParse((json['edited_at'] ?? '').toString()),
      isPrivate: (json['is_private']?.toString() ?? '0') == '1',
      description: (json['description'] ?? '').toString(),
    );
  }
}

class _TeacherAssignmentDetailPage extends StatefulWidget {
  final _AssignmentItem assignment;
  final String teacherName;
  final String Function(DateTime) formatFeedDate;
  final String Function(DateTime) formatDateTimeWithAmPm;

  const _TeacherAssignmentDetailPage({
    required this.assignment,
    required this.teacherName,
    required this.formatFeedDate,
    required this.formatDateTimeWithAmPm,
  });

  @override
  State<_TeacherAssignmentDetailPage> createState() =>
      _TeacherAssignmentDetailPageState();
}

class _TeacherAssignmentDetailPageState
    extends State<_TeacherAssignmentDetailPage> {
  int _selectedTab = 0;
  late String _currentTitle;
  late String _currentDescription;
  late DateTime _currentDueDate;

  DateTime _assignmentDeadline(DateTime dueDate) {
    if (dueDate.hour == 0 && dueDate.minute == 0 && dueDate.second == 0) {
      return DateTime(dueDate.year, dueDate.month, dueDate.day, 23, 59, 59);
    }
    return dueDate;
  }

  String _formatRemainingTime(DateTime dueDate) {
    final now = DateTime.now();
    final deadline = _assignmentDeadline(dueDate);
    final diff = deadline.difference(now);

    if (diff.isNegative) {
      return 'Expired';
    }

    final totalSeconds = diff.inSeconds;
    final days = totalSeconds ~/ 86400;
    final hours = (totalSeconds % 86400) ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');

    if (days > 0) {
      return '${days}d ${hours}h ${mm}m ${ss}s left';
    }
    return '${hours}h ${mm}m ${ss}s left';
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _currentTitle = widget.assignment.title;
    _currentDescription = widget.assignment.description;
    _currentDueDate = widget.assignment.dueDate;
  }

  Future<void> _reloadAssignmentFromServer() async {
    final result = await ApiService().getAssignments(
      widget.assignment.courseId,
    );
    if (!mounted) return;
    if (result['success'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Failed to refresh assignment'),
        ),
      );
      return;
    }

    final rows = (result['assignments'] as List? ?? [])
        .map(
          (item) =>
              _AssignmentItem.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final refreshed = rows.firstWhere(
      (item) => item.id == widget.assignment.id,
      orElse: () => widget.assignment,
    );
    setState(() {
      _currentTitle = refreshed.title;
      _currentDescription = refreshed.description;
      _currentDueDate = refreshed.dueDate;
    });
  }

  Future<void> _saveAssignmentChanges({
    String? title,
    String? description,
    DateTime? dueDate,
  }) async {
    final normalizedTitle = title?.trim();
    final normalizedDescription = description?.trim();
    final result = await ApiService().updateAssignment(
      id: widget.assignment.id,
      courseId: widget.assignment.courseId,
      teacherEmail: widget.assignment.teacherEmail,
      title: normalizedTitle,
      dueDate: dueDate != null ? _formatDate(dueDate) : null,
      description: normalizedDescription,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      await _reloadAssignmentFromServer();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Assignment updated successfully')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Failed to update assignment'),
        ),
      );
    }
  }

  Future<void> _editTitle() async {
    String draftTitle = _currentTitle;
    final submitted = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Title'),
        content: TextFormField(
          autofocus: true,
          initialValue: _currentTitle,
          onChanged: (value) {
            draftTitle = value;
          },
          decoration: const InputDecoration(
            labelText: 'Title',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final value = draftTitle.trim();
              if (value.isEmpty) return;
              Navigator.pop(dialogContext, value);
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (submitted == null || submitted.isEmpty) return;
    final value = submitted.trim();
    if (value == _currentTitle) return;
    await _saveAssignmentChanges(title: value);
  }

  Future<void> _editDescription() async {
    String draftDescription = _currentDescription;
    final submitted = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Description'),
        content: TextFormField(
          autofocus: true,
          initialValue: _currentDescription,
          maxLines: 5,
          onChanged: (value) {
            draftDescription = value;
          },
          decoration: const InputDecoration(
            labelText: 'Description',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final value = draftDescription.trim();
              if (value.isEmpty) return;
              Navigator.pop(dialogContext, value);
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (submitted == null || submitted.isEmpty) return;
    final value = submitted.trim();
    if (value == _currentDescription) return;
    await _saveAssignmentChanges(description: value);
  }

  Future<void> _editDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _currentDueDate.isBefore(today) ? today : _currentDueDate,
      firstDate: today,
      lastDate: today.add(const Duration(days: 3650)),
    );
    if (picked == null) return;
    if (picked == _currentDueDate) return;
    await _saveAssignmentChanges(dueDate: picked);
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_selectedTab == 0) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8E4)),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(right: 45),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.date_range_outlined,
                        color: Colors.green,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Last Date: ${widget.formatFeedDate(_currentDueDate)}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Remaining: ${_formatRemainingTime(_currentDueDate)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: IconButton(
                  onPressed: _editDate,
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  color: Colors.green,
                  tooltip: 'Edit date',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Stack(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: widget.assignment.isPrivate
                      ? const Color(0xFFFDEBEC)
                      : const Color(0xFFEAF6EE),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: widget.assignment.isPrivate
                        ? const Color(0xFFE7B7B7)
                        : const Color(0xFFBDE3C7),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.assignment_outlined, color: Colors.green),
                        SizedBox(width: 8),
                        Text(
                          'Title',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.only(right: 40),
                      child: Text(
                        _currentTitle,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: IconButton(
                  onPressed: _editTitle,
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  color: Colors.green,
                  tooltip: 'Edit title',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Stack(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8E4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.description_outlined, color: Colors.green),
                        SizedBox(width: 8),
                        Text(
                          'Description',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _currentDescription,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: IconButton(
                  onPressed: _editDescription,
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  color: Colors.green,
                  tooltip: 'Edit description',
                ),
              ),
            ],
          ),
        ],
      );
    } else if (_selectedTab == 1) {
      body = AssignmentCommentSection(
        assignmentId: widget.assignment.id,
        courseId: widget.assignment.courseId,
        userEmail: widget.assignment.teacherEmail,
        userRole: 'teacher',
        userName: widget.teacherName.isNotEmpty
            ? widget.teacherName
            : 'Teacher',
        apiService: ApiService(),
      );
    } else {
      body = AssignmentSubmissionSection(
        assignmentId: widget.assignment.id,
        courseId: widget.assignment.courseId,
        userEmail: widget.assignment.teacherEmail,
        userRole: 'teacher',
        userName: widget.teacherName.isNotEmpty
            ? widget.teacherName
            : 'Teacher',
        apiService: ApiService(),
        dueDate: _currentDueDate,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Assignment Details'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: (_selectedTab == 1 || _selectedTab == 2)
                  ? body
                  : RefreshIndicator(
                      onRefresh: _reloadAssignmentFromServer,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                        children: [body],
                      ),
                    ),
            ),
            if (MediaQuery.of(context).viewInsets.bottom == 0)
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFE0E0E0))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() => _selectedTab = 0);
                          _reloadAssignmentFromServer();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _selectedTab == 0
                              ? Colors.green
                              : Colors.white,
                          foregroundColor: _selectedTab == 0
                              ? Colors.white
                              : Colors.green,
                          side: const BorderSide(color: Colors.green),
                        ),
                        child: const Text('Details'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() => _selectedTab = 1);
                          _reloadAssignmentFromServer();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _selectedTab == 1
                              ? Colors.green
                              : Colors.white,
                          foregroundColor: _selectedTab == 1
                              ? Colors.white
                              : Colors.green,
                          side: const BorderSide(color: Colors.green),
                        ),
                        child: const Text('Comments'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() => _selectedTab = 2);
                          _reloadAssignmentFromServer();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _selectedTab == 2
                              ? Colors.green
                              : Colors.white,
                          foregroundColor: _selectedTab == 2
                              ? Colors.white
                              : Colors.green,
                          side: const BorderSide(color: Colors.green),
                        ),
                        child: const Text('Submissions'),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
