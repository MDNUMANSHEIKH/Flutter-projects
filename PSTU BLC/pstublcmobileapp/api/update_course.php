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
require_once 'logger.php';

if ($conn->connect_error) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Database connection failed']);
    exit();
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Method not allowed']);
    exit();
}

$data = json_decode(file_get_contents("php://input"), true);
if (!$data) {
    $data = $_POST;
}

$email = trim(strtolower($data['email'] ?? ''));
$courseId = intval($data['course_id'] ?? 0);
$courseCode = trim($data['course_code'] ?? '');
$courseName = trim($data['course_name'] ?? '');
$session = trim($data['session'] ?? '');
$facultyName = strtoupper(trim($data['faculty'] ?? ''));

if (empty($email) || empty($courseId) || empty($courseCode) || empty($courseName) || empty($session) || empty($facultyName)) {
    http_response_code(400);
    logActivity($conn, $email, 'teacher', 'course_update_failed', 'All fields are required');
    echo json_encode(['success' => false, 'message' => 'All fields are required']);
    exit();
}

$facultyMap = [
    'AGRI' => '01',
    'CSE' => '02',
    'FBA' => '03',
    'FISHERIES' => '04',
    'NFS' => '05',
    'ESDM' => '06'
];

if (!isset($facultyMap[$facultyName])) {
    http_response_code(400);
    logActivity($conn, $email, 'teacher', 'course_update_failed', 'Invalid faculty selected');
    echo json_encode(['success' => false, 'message' => 'Invalid faculty selected']);
    exit();
}

$facultyCode = $facultyMap[$facultyName];

$teacherStmt = $conn->prepare("SELECT id FROM teachers WHERE LOWER(email) = ?");
$teacherStmt->bind_param('s', $email);
$teacherStmt->execute();
$teacherResult = $teacherStmt->get_result();
$teacher = $teacherResult->fetch_assoc();

if (!$teacher) {
    http_response_code(404);
    logActivity($conn, $email, 'teacher', 'course_update_failed', 'Teacher not found');
    echo json_encode(['success' => false, 'message' => 'Teacher not found']);
    exit();
}

$teacherId = $teacher['id'];

$stmt = $conn->prepare("UPDATE courses SET course_code = ?, course_name = ?, `session` = ?, faculty_code = ? WHERE id = ? AND teacher_id = ?");
if (!$stmt) {
    http_response_code(500);
    logActivity($conn, $email, 'teacher', 'course_update_failed', 'Prepare failed: ' . $conn->error);
    echo json_encode(['success' => false, 'message' => 'Prepare failed: ' . $conn->error]);
    exit();
}

$stmt->bind_param('ssssii', $courseCode, $courseName, $session, $facultyCode, $courseId, $teacherId);

if ($stmt->execute()) {
    if ($stmt->affected_rows > 0) {
        logActivity($conn, $email, 'teacher', 'course_update', "Course ID: $courseId");
        echo json_encode(['success' => true, 'message' => 'Course updated successfully']);
    } else {
        logActivity($conn, $email, 'teacher', 'course_update_no_change', "Course ID: $courseId");
        echo json_encode(['success' => false, 'message' => 'No changes were made. Did you change any values?']);
    }
} else {
    http_response_code(500);
    logActivity($conn, $email, 'teacher', 'course_update_failed', 'Update failed: ' . $stmt->error);
    echo json_encode(['success' => false, 'message' => 'Update failed: ' . $stmt->error]);
}

$stmt->close();
$conn->close();
?>
