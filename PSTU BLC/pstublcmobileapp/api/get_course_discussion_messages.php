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

if ($role === 'teacher') {
    $stmt = $conn->prepare('SELECT 1 FROM courses c JOIN teachers t ON c.teacher_id = t.id WHERE c.id = ? AND LOWER(t.email) = ? LIMIT 1');
} else {
    $stmt = $conn->prepare('SELECT 1 FROM enrollments WHERE course_id = ? AND LOWER(student_email) = ? AND (is_blocked IS NULL OR is_blocked = 0) LIMIT 1');
}

if (!$stmt) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Prepare failed: ' . $conn->error]);
    exit();
}

$stmt->bind_param('is', $courseId, $email);
$stmt->execute();
$accessResult = $stmt->get_result();
$hasAccess = $accessResult && $accessResult->num_rows > 0;
$stmt->close();

if (!$hasAccess) {
    http_response_code(403);
    echo json_encode(['success' => false, 'message' => 'Access denied for this course']);
    exit();
}

$hasEditedColumns = false;
$editedCheck = $conn->query("SHOW COLUMNS FROM course_discussion_messages LIKE 'is_edited'");
if ($editedCheck && $editedCheck->num_rows > 0) {
    $hasEditedColumns = true;
}

$hasReplyColumns = false;
$replyIdCheck = $conn->query("SHOW COLUMNS FROM course_discussion_messages LIKE 'reply_to_message_id'");
$replySenderCheck = $conn->query("SHOW COLUMNS FROM course_discussion_messages LIKE 'reply_to_sender_name'");
$replyMessageCheck = $conn->query("SHOW COLUMNS FROM course_discussion_messages LIKE 'reply_to_message'");
if (
    $replyIdCheck && $replyIdCheck->num_rows > 0 &&
    $replySenderCheck && $replySenderCheck->num_rows > 0 &&
    $replyMessageCheck && $replyMessageCheck->num_rows > 0
) {
    $hasReplyColumns = true;
}

$sql = "SELECT id, course_id, sender_email, sender_name, sender_role, message, created_at" .
        ($hasReplyColumns ? ", reply_to_message_id, reply_to_sender_name, reply_to_message" : "") .
        ($hasEditedColumns ? ", is_edited, edited_at" : "") . "
        FROM course_discussion_messages
        WHERE course_id = ?
        ORDER BY created_at ASC, id ASC
        LIMIT 300";

$stmt = $conn->prepare($sql);
if (!$stmt) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Prepare failed: ' . $conn->error]);
    exit();
}

$stmt->bind_param('i', $courseId);
$stmt->execute();
$result = $stmt->get_result();

$messages = [];
while ($row = $result->fetch_assoc()) {
    $messages[] = [
        'id' => (int)$row['id'],
        'course_id' => (int)$row['course_id'],
        'sender_email' => $row['sender_email'],
        'sender_name' => $row['sender_name'],
        'sender_role' => $row['sender_role'],
        'message' => $row['message'],
        'reply_to_message_id' => $hasReplyColumns ? (isset($row['reply_to_message_id']) ? (int)$row['reply_to_message_id'] : null) : null,
        'reply_to_sender_name' => $hasReplyColumns ? ($row['reply_to_sender_name'] ?? null) : null,
        'reply_to_message' => $hasReplyColumns ? ($row['reply_to_message'] ?? null) : null,
        'created_at' => $row['created_at'],
        'is_edited' => $hasEditedColumns ? ((int)($row['is_edited'] ?? 0) === 1) : false,
        'edited_at' => $hasEditedColumns ? ($row['edited_at'] ?? null) : null,
    ];
}

echo json_encode(['success' => true, 'messages' => $messages]);

$stmt->close();
$conn->close();
?>