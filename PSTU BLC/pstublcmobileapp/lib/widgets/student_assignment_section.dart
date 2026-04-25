import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pstublc/services/api_service.dart';
import 'package:pstublc/widgets/assignment_comment_section.dart';
import 'package:pstublc/widgets/assignment_submission_section.dart';

class StudentAssignmentSection extends StatefulWidget {
  final int courseId;
  final ApiService apiService;
  final String teacherName;
  final String userEmail;
  final String userName;

  const StudentAssignmentSection({
    super.key,
    required this.courseId,
    required this.apiService,
    required this.teacherName,
    required this.userEmail,
    required this.userName,
  });

  @override
  State<StudentAssignmentSection> createState() => _StudentAssignmentSectionState();
}

class _StudentAssignmentSectionState extends State<StudentAssignmentSection> {
  bool _loading = true;
  bool _showHistory = false;
  List<_StudentAssignmentItem> _assignments = [];
  Timer? _countdownTimer;

  DateTime _assignmentDeadline(DateTime dueDate) {
    return DateTime(
      dueDate.year,
      dueDate.month,
      dueDate.day,
      23,
      59,
      59,
    );
  }

  bool _isAssignmentActive(_StudentAssignmentItem assignment) {
    final now = DateTime.now();
    final deadline = _assignmentDeadline(assignment.dueDate);
    return !now.isAfter(deadline);
  }

  String _formatRemainingTime(_StudentAssignmentItem assignment) {
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

  Future<void> _loadAssignments() async {
    setState(() => _loading = true);
    final result = await widget.apiService.getAssignments(
      widget.courseId,
      studentEmail: widget.userEmail,
    );
    if (!mounted) return;

    if (result['success'] == true) {
      final rows = (result['assignments'] as List? ?? [])
          .map((item) => _StudentAssignmentItem.fromJson(Map<String, dynamic>.from(item as Map)))
          .where((item) => !item.isPrivate)
          .toList();
      setState(() => _assignments = rows);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? 'Failed to load assignments')),
      );
    }

    setState(() => _loading = false);
  }

  @override
  void initState() {
    super.initState();
    _loadAssignments();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _openAssignmentDetails(_StudentAssignmentItem assignment) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _StudentAssignmentDetailPage(
          assignment: assignment,
          courseId: widget.courseId,
          apiService: widget.apiService,
          teacherName: widget.teacherName,
          userEmail: widget.userEmail,
          userName: widget.userName,
          formatFeedDate: _formatFeedDate,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _assignments.where((assignment) {
      final isActive = _isAssignmentActive(assignment);
      return _showHistory ? !isActive : isActive;
    }).toList();

    final submittedCount = _assignments.where((a) => a.isTurnedIn).length;
    final totalCount = _assignments.length;
    final missingCount = _assignments.where((a) => !_isAssignmentActive(a) && !a.isTurnedIn).length;
    final notSubmittedCount = _assignments.where((a) => _isAssignmentActive(a) && !a.isTurnedIn).length;
    
    final double percentage = totalCount > 0 ? (submittedCount / totalCount) * 100 : 0.0;

    return Column(
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.green.shade800, Colors.green.shade600],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.green.withOpacity(0.3),
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
                      'Assignment Overview',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Submitted $submittedCount out of $totalCount assignments',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildSmallStatChip('Missing: $missingCount', Colors.red.shade100),
                        const SizedBox(width: 8),
                        _buildSmallStatChip('Pending: $notSubmittedCount', Colors.blue.shade100),
                      ],
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
                  onPressed: () => setState(() => _showHistory = false),
                  icon: const Icon(Icons.dashboard),
                  label: const Text('Active'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 45),
                    backgroundColor: !_showHistory
                        ? Colors.green
                        : Colors.grey.shade300,
                    foregroundColor: !_showHistory
                        ? Colors.white
                        : Colors.black54,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => setState(() => _showHistory = true),
                  icon: const Icon(Icons.history),
                  label: const Text('History'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 45),
                    backgroundColor: _showHistory
                        ? Colors.blueGrey
                        : Colors.grey.shade300,
                    foregroundColor: _showHistory
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
            onRefresh: _loadAssignments,
            child: _loading
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 200),
                      Center(child: CircularProgressIndicator()),
                    ],
                  )
                : filtered.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 120),
                          Center(
                            child: Text(
                              _showHistory
                                  ? 'No history assignments'
                                  : 'No active assignments',
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 18),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final assignment = filtered[index];
                          final teacherName = widget.teacherName.trim().isEmpty
                              ? 'Teacher'
                              : widget.teacherName.trim();
                          
                          final isActive = _isAssignmentActive(assignment);
                          final isSubmitted = assignment.isTurnedIn;
                          final isMissing = !isActive && !isSubmitted;

                          Color cardColor = const Color(0xFFE8ECE5);
                          Color iconColor = Colors.blueGrey;
                          String statusLabel = 'Not submitted';
                          Color labelColor = Colors.blueGrey;
                          Color borderColor = const Color(0xFFBDE3C7);

                          if (isSubmitted) {
                            cardColor = Colors.green.shade50;
                            iconColor = Colors.green;
                            statusLabel = 'Submitted';
                            labelColor = Colors.green;
                            borderColor = Colors.green.shade200;
                          } else if (isMissing) {
                            cardColor = Colors.red.shade50;
                            iconColor = Colors.red;
                            statusLabel = 'Missing';
                            labelColor = Colors.red;
                            borderColor = Colors.red.shade200;
                          }

                          return InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _openAssignmentDetails(assignment),
                            child: Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              elevation: 0,
                              color: cardColor,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(color: borderColor),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: iconColor,
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
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  '$teacherName posted a new assignment: ${assignment.title}',
                                                  style: const TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: labelColor.withOpacity(0.1),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  statusLabel,
                                                  style: TextStyle(
                                                    color: labelColor,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
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
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isMissing ? Colors.red : Colors.black54,
                                              fontWeight: isMissing ? FontWeight.bold : FontWeight.normal,
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
                      ),
          ),
        ),
      ],
    );
  }

  Widget _buildSmallStatChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _StudentAssignmentItem {
  final int id;
  final String title;
  final String description;
  final DateTime dueDate;
  final bool isPrivate;
  final bool isTurnedIn;

  const _StudentAssignmentItem({
    required this.id,
    required this.title,
    required this.description,
    required this.dueDate,
    required this.isPrivate,
    required this.isTurnedIn,
  });

  static DateTime _parseDueDate(dynamic value) {
    final raw = (value ?? '').toString().trim();
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw);
    if (match != null) {
      final year = int.tryParse(match.group(1) ?? '');
      final month = int.tryParse(match.group(2) ?? '');
      final day = int.tryParse(match.group(3) ?? '');
      if (year != null && month != null && day != null) {
        return DateTime(year, month, day);
      }
    }

    final parsed = DateTime.tryParse(raw);
    if (parsed != null) {
      return DateTime(parsed.year, parsed.month, parsed.day);
    }

    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  factory _StudentAssignmentItem.fromJson(Map<String, dynamic> json) {
    return _StudentAssignmentItem(
      id: int.tryParse((json['id'] ?? '').toString()) ?? 0,
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      dueDate: _parseDueDate(json['due_date']),
      isPrivate: (json['is_private']?.toString() ?? '0') == '1',
      isTurnedIn: (json['is_turned_in'] == 1 || json['is_turned_in'] == true || json['is_turned_in'] == '1'),
    );
  }
}

class _StudentAssignmentDetailPage extends StatefulWidget {
  final _StudentAssignmentItem assignment;
  final int courseId;
  final ApiService apiService;
  final String teacherName;
  final String userEmail;
  final String userName;
  final String Function(DateTime) formatFeedDate;

  const _StudentAssignmentDetailPage({
    required this.assignment,
    required this.courseId,
    required this.apiService,
    required this.teacherName,
    required this.userEmail,
    required this.userName,
    required this.formatFeedDate,
  });

  @override
  State<_StudentAssignmentDetailPage> createState() =>
      _StudentAssignmentDetailPageState();
}

class _StudentAssignmentDetailPageState
    extends State<_StudentAssignmentDetailPage> {
  int _selectedTab = 0;
  late _StudentAssignmentItem _currentAssignment;

  DateTime _assignmentDeadline(DateTime dueDate) {
    return DateTime(
      dueDate.year,
      dueDate.month,
      dueDate.day,
      23,
      59,
      59,
    );
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

  @override
  void initState() {
    super.initState();
    _currentAssignment = widget.assignment;
  }

  Future<void> _refreshAssignment() async {
    final result = await widget.apiService.getAssignments(widget.courseId);
    if (!mounted) return;

    if (result['success'] == true) {
      final rows = (result['assignments'] as List? ?? [])
          .map((item) => _StudentAssignmentItem.fromJson(Map<String, dynamic>.from(item as Map)))
          .where((item) => !item.isPrivate)
          .toList();

      final updated = rows.where((a) => a.id == _currentAssignment.id).toList();
      if (updated.isNotEmpty) {
        setState(() => _currentAssignment = updated.first);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_selectedTab == 0) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8E4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.date_range_outlined, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Last Date: ${widget.formatFeedDate(_currentAssignment.dueDate)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Remaining: ${_formatRemainingTime(_currentAssignment.dueDate)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF6EE),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFBDE3C7)),
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
                Text(
                  _currentAssignment.title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
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
                  _currentAssignment.description,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    } else if (_selectedTab == 1) {
      body = AssignmentCommentSection(
        assignmentId: _currentAssignment.id,
        courseId: widget.courseId,
        userEmail: widget.userEmail,
        userRole: 'student',
        userName: widget.userName,
        apiService: widget.apiService,
      );
    } else {
      body = AssignmentSubmissionSection(
        assignmentId: _currentAssignment.id,
        courseId: widget.courseId,
        userEmail: widget.userEmail,
        userRole: 'student',
        userName: widget.userName,
        apiService: widget.apiService,
        dueDate: _currentAssignment.dueDate,
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
                      onRefresh: _refreshAssignment,
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
                      onPressed: () => setState(() => _selectedTab = 0),
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
                      onPressed: () => setState(() => _selectedTab = 1),
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
                      onPressed: () => setState(() => _selectedTab = 2),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _selectedTab == 2
                            ? Colors.green
                            : Colors.white,
                        foregroundColor: _selectedTab == 2
                            ? Colors.white
                            : Colors.green,
                        side: const BorderSide(color: Colors.green),
                      ),
                      child: const Text('Submit'),
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
