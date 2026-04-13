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

$data = json_decode(file_get_contents('php://input'), true);
$studentEmail = trim(strtolower((string)($data['student_email'] ?? '')));
$courseId = (int)($data['course_id'] ?? 0);
$title = trim((string)($data['title'] ?? 'Result Uploaded'));
$message = trim((string)($data['message'] ?? 'A new result file has been uploaded.'));
$fileId = trim((string)($data['file_id'] ?? ''));
$actorEmail = trim(strtolower((string)($data['actor_email'] ?? '')));
$actorRole = trim((string)($data['actor_role'] ?? 'teacher'));

if ($studentEmail === '') {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Student email is required']);
    exit();
}

if ($courseId <= 0) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Course ID is required']);
    exit();
}

$type = $fileId !== '' ? ('result|' . $fileId) : 'result';

$stmt = $conn->prepare(
    'INSERT INTO notifications (student_email, course_id, title, message, type) VALUES (?, ?, ?, ?, ?)'
);

if (!$stmt) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Prepare failed: ' . $conn->error]);
    exit();
}

$stmt->bind_param('sisss', $studentEmail, $courseId, $title, $message, $type);

if ($stmt->execute()) {
    logActivity($conn, $actorEmail ?: null, $actorRole ?: 'teacher', 'result_notify_student', "Course ID: $courseId, Student: $studentEmail");
    echo json_encode(['success' => true, 'message' => 'Result notification sent']);
} else {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Failed to send result notification: ' . $stmt->error]);
}

$stmt->close();
$conn->close();
?>
