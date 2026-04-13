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

date_default_timezone_set('Asia/Dhaka');

if ($conn->connect_error) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Database connection failed']);
    exit();
}

function ensureDiscussionEditColumns(mysqli $conn): bool {
    $isEditedCheck = $conn->query("SHOW COLUMNS FROM course_discussion_messages LIKE 'is_edited'");
    if ($isEditedCheck && $isEditedCheck->num_rows === 0) {
        if (!$conn->query("ALTER TABLE course_discussion_messages ADD COLUMN is_edited TINYINT(1) NOT NULL DEFAULT 0 AFTER message")) {
            return false;
        }
    }

    $editedAtCheck = $conn->query("SHOW COLUMNS FROM course_discussion_messages LIKE 'edited_at'");
    if ($editedAtCheck && $editedAtCheck->num_rows === 0) {
        if (!$conn->query("ALTER TABLE course_discussion_messages ADD COLUMN edited_at DATETIME NULL AFTER is_edited")) {
            return false;
        }
    }

    return true;
}

$data = json_decode(file_get_contents('php://input'), true);
$messageId = (int)($data['message_id'] ?? 0);
$email = trim(strtolower((string)($data['email'] ?? '')));
$role = trim(strtolower((string)($data['role'] ?? '')));
$message = trim((string)($data['message'] ?? ''));

if ($messageId <= 0) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Message ID is required']);
    exit();
}

if ($email === '' || !in_array($role, ['teacher', 'student'], true)) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Valid email and role are required']);
    exit();
}

if ($message === '') {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Message cannot be empty']);
    exit();
}

if (!ensureDiscussionEditColumns($conn)) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Failed to prepare discussion table for edits']);
    exit();
}

$editedAt = date('Y-m-d H:i:s');

$stmt = $conn->prepare('UPDATE course_discussion_messages SET message = ?, is_edited = 1, edited_at = ? WHERE id = ? AND LOWER(sender_email) = ? AND sender_role = ?');
if (!$stmt) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Prepare failed: ' . $conn->error]);
    exit();
}

$stmt->bind_param('ssiss', $message, $editedAt, $messageId, $email, $role);

if (!$stmt->execute()) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Failed to update message: ' . $stmt->error]);
    $stmt->close();
    $conn->close();
    exit();
}

if ($stmt->affected_rows <= 0) {
    echo json_encode(['success' => false, 'message' => 'Message not found or no changes made']);
    $stmt->close();
    $conn->close();
    exit();
}

$stmt->close();

$fetchStmt = $conn->prepare('SELECT id, course_id, sender_email, sender_name, sender_role, message, created_at, is_edited, edited_at FROM course_discussion_messages WHERE id = ? LIMIT 1');
if (!$fetchStmt) {
    echo json_encode(['success' => true, 'message' => 'Message updated']);
    $conn->close();
    exit();
}

$fetchStmt->bind_param('i', $messageId);
$fetchStmt->execute();
$result = $fetchStmt->get_result();
$row = $result ? $result->fetch_assoc() : null;

if ($row) {
    echo json_encode([
        'success' => true,
        'message' => 'Message updated successfully',
        'data' => [
            'id' => (int)$row['id'],
            'course_id' => (int)$row['course_id'],
            'sender_email' => $row['sender_email'],
            'sender_name' => $row['sender_name'],
            'sender_role' => $row['sender_role'],
            'message' => $row['message'],
            'created_at' => $row['created_at'],
            'is_edited' => (int)$row['is_edited'] === 1,
            'edited_at' => $row['edited_at'],
        ],
    ]);
} else {
    echo json_encode(['success' => true, 'message' => 'Message updated successfully']);
}

$fetchStmt->close();
$conn->close();
?>