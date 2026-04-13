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

$data = json_decode(file_get_contents("php://input"), true);
$courseId = trim($data['course_id'] ?? '');

if (empty($courseId)) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Course ID is required']);
    exit();
}

$fSql = "SELECT faculty_code, session FROM courses WHERE id = ?";
$fStmt = $conn->prepare($fSql);
$fStmt->bind_param('i', $courseId);
$fStmt->execute();
$fResult = $fStmt->get_result();
$courseData = $fResult->fetch_assoc();
$fStmt->close();

if (!$courseData) {
    http_response_code(404);
    echo json_encode(['success' => false, 'message' => 'Course not found']);
    exit();
}

$facultyCode = $courseData['faculty_code'];
$session = $courseData['session'];
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

$sql = "SELECT s.name, s.email, s.phone, e.enrolled_at 
        FROM enrollments e 
        JOIN $studentTable s ON e.student_email = s.email 
        WHERE e.course_id = ? AND e.student_email LIKE ? AND (e.is_blocked IS NULL OR e.is_blocked = 0)
        ORDER BY s.name ASC";

$stmt = $conn->prepare($sql);
if (!$stmt) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Prepare failed: ' . $conn->error]);
    exit();
}

$stmt->bind_param('is', $courseId, $emailPattern);
$stmt->execute();
$result = $stmt->get_result();

$students = [];
while ($row = $result->fetch_assoc()) {
    $students[] = $row;
}

echo json_encode(['success' => true, 'students' => $students]);

$stmt->close();
$conn->close();
?>
