<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once 'db_config.php';

if ($conn->connect_error) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Database connection failed']);
    exit();
}

$data = json_decode(file_get_contents('php://input'), true);
$courseId = (int)($data['course_id'] ?? 0);
$email = trim(strtolower((string)($data['email'] ?? '')));
$role = trim(strtolower((string)($data['role'] ?? '')));

if ($courseId <= 0) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Course ID is required']);
    exit();
}

if ($email === '' || !in_array($role, ['teacher', 'student'], true)) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Valid email and role are required']);
    exit();
}

$courseStmt = $conn->prepare('SELECT c.faculty_code, c.session, t.name AS teacher_name, LOWER(t.email) AS teacher_email FROM courses c JOIN teachers t ON c.teacher_id = t.id WHERE c.id = ? LIMIT 1');
if (!$courseStmt) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Prepare failed: ' . $conn->error]);
    exit();
}
$courseStmt->bind_param('i', $courseId);
$courseStmt->execute();
$courseResult = $courseStmt->get_result();
if (!$courseResult || $courseResult->num_rows === 0) {
    $courseStmt->close();
    http_response_code(404);
    echo json_encode(['success' => false, 'message' => 'Course not found']);
    exit();
}
$courseRow = $courseResult->fetch_assoc();
$courseStmt->close();

$teacherEmail = trim(strtolower((string)($courseRow['teacher_email'] ?? '')));
$teacherName = trim((string)($courseRow['teacher_name'] ?? ''));
$facultyCode = trim((string)($courseRow['faculty_code'] ?? ''));
$session = trim((string)($courseRow['session'] ?? ''));

if ($teacherEmail === '') {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Teacher account not found for this course']);
    exit();
}

if ($role === 'teacher') {
    if ($email !== $teacherEmail) {
        http_response_code(403);
        echo json_encode(['success' => false, 'message' => 'Access denied for this course']);
        exit();
    }
} else {
    $accessStmt = $conn->prepare('SELECT 1 FROM enrollments WHERE course_id = ? AND LOWER(student_email) = ? AND (is_blocked IS NULL OR is_blocked = 0) LIMIT 1');
    if (!$accessStmt) {
        http_response_code(500);
        echo json_encode(['success' => false, 'message' => 'Prepare failed: ' . $conn->error]);
        exit();
    }
    $accessStmt->bind_param('is', $courseId, $email);
    $accessStmt->execute();
    $accessResult = $accessStmt->get_result();
    if (!$accessResult || $accessResult->num_rows === 0) {
        $accessStmt->close();
        http_response_code(403);
        echo json_encode(['success' => false, 'message' => 'Access denied for this course']);
        exit();
    }
    $accessStmt->close();
}

$studentTable = null;
if (isset($facultyMap[$facultyCode])) {
    $studentTable = $facultyMap[$facultyCode]['table'];
}

if (!$studentTable) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Invalid faculty configuration']);
    exit();
}

$emailPattern = '%';
if (preg_match('/^20(\d{2})-/', $session, $matches)) {
    $batch = $matches[1];
    $emailPattern = 'ug' . $batch . '%';
}

$studentsStmt = $conn->prepare("SELECT s.name, LOWER(s.email) AS email FROM enrollments e JOIN $studentTable s ON e.student_email = s.email WHERE e.course_id = ? AND e.student_email LIKE ? AND (e.is_blocked IS NULL OR e.is_blocked = 0) ORDER BY s.name ASC");
if (!$studentsStmt) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Prepare failed: ' . $conn->error]);
    exit();
}
$studentsStmt->bind_param('is', $courseId, $emailPattern);
$studentsStmt->execute();
$studentsResult = $studentsStmt->get_result();

$students = [];
while ($row = $studentsResult->fetch_assoc()) {
    $students[] = [
        'name' => trim((string)($row['name'] ?? 'Student')),
        'email' => trim(strtolower((string)($row['email'] ?? ''))),
    ];
}

$studentsStmt->close();
$conn->close();

echo json_encode([
    'success' => true,
    'teacher' => [
        'name' => $teacherName,
        'email' => $teacherEmail,
    ],
    'students' => $students,
]);
?>
