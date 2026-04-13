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
require_once 'student_utils.php';

date_default_timezone_set('Asia/Dhaka');

if ($conn->connect_error) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Database connection failed']);
    exit();
}

$data = json_decode(file_get_contents('php://input'), true);
$courseId = (int)($data['course_id'] ?? 0);
$email = trim(strtolower((string)($data['email'] ?? '')));
$role = trim(strtolower((string)($data['role'] ?? '')));
$senderName = trim((string)($data['sender_name'] ?? ''));
$message = trim((string)($data['message'] ?? ''));

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

if ($message === '') {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Message is required']);
    exit();
}

if ($role === 'teacher') {
    $accessStmt = $conn->prepare('SELECT t.name FROM courses c JOIN teachers t ON c.teacher_id = t.id WHERE c.id = ? AND LOWER(t.email) = ? LIMIT 1');
} else {
    $studentTable = getStudentTable($email);
    if (!$studentTable) {
        http_response_code(400);
        echo json_encode(['success' => false, 'message' => 'Could not determine student table']);
        exit();
    }
    $accessStmt = $conn->prepare('SELECT s.name FROM enrollments e INNER JOIN ' . $studentTable . ' s ON LOWER(s.email) = LOWER(e.student_email) WHERE e.course_id = ? AND LOWER(e.student_email) = ? AND (e.is_blocked IS NULL OR e.is_blocked = 0) LIMIT 1');
}

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

$row = $accessResult->fetch_assoc();
$accessStmt->close();

if ($senderName === '') {
    $senderName = trim((string)($row['name'] ?? ''));
}

if ($senderName === '') {
    $senderName = $role === 'teacher' ? 'Teacher' : 'Student';
}

$createdAt = date('Y-m-d H:i:s');

$stmt = $conn->prepare('INSERT INTO course_discussion_messages (course_id, sender_email, sender_name, sender_role, message, created_at) VALUES (?, ?, ?, ?, ?, ?)');
if (!$stmt) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Prepare failed: ' . $conn->error]);
    exit();
}

$stmt->bind_param('isssss', $courseId, $email, $senderName, $role, $message, $createdAt);

if ($stmt->execute()) {
    echo json_encode([
        'success' => true,
        'message' => 'Message sent successfully',
        'message_id' => $stmt->insert_id,
    ]);
} else {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Failed to send message: ' . $stmt->error]);
}

$stmt->close();
$conn->close();
?>