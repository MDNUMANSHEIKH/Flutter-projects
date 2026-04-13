import 'package:flutter/material.dart';
import 'package:pstublc/widgets/course_materials_section.dart';

class StudentCourseMaterialsSection extends StatelessWidget {
  final int courseId;
  final String courseScope;
  final String studentEmail;
  final String courseName;

  const StudentCourseMaterialsSection({
    super.key,
    required this.courseId,
    required this.courseScope,
    required this.studentEmail,
    this.courseName = '',
  });

  @override
  Widget build(BuildContext context) {
    return CourseMaterialsSection(
      courseId: courseId,
      courseScope: courseScope,
      userEmail: studentEmail,
      userRole: 'student',
      canDeleteAny: false,
      canUpload: true,
      courseName: courseName,
    );
  }
}
