class Course {
  final int id;
  final String courseCode;
  final String courseName;
  final String session;
  final String facultyCode;
  final int teacherId;
  final String status;
  final bool isPrivate;

  Course({
    required this.id,
    required this.courseCode,
    required this.courseName,
    required this.session,
    required this.facultyCode,
    required this.teacherId,
    required this.status,
    required this.isPrivate,
  });

  factory Course.fromJson(Map<String, dynamic> json) {
    return Course(
      id: json['id'] is String ? int.parse(json['id']) : json['id'],
      courseCode: json['course_code'] ?? '',
      courseName: json['course_name'] ?? '',
      session: json['session'] ?? '',
      facultyCode: json['faculty_code'] ?? '',
      teacherId: json['teacher_id'] is String
          ? int.parse(json['teacher_id'])
          : json['teacher_id'],
      status: json['status'] ?? 'Public',
      isPrivate: (json['is_private'] == 1 || json['is_private'] == true),
    );
  }
}
