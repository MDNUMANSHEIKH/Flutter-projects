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
$messageId = (int)($data['message_id'] ?? 0);
$email = trim(strtolower((string)($data['email'] ?? '')));
$role = trim(strtolower((string)($data['role'] ?? '')));

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

$stmt = $conn->prepare('DELETE FROM course_discussion_messages WHERE id = ? AND LOWER(sender_email) = ? AND sender_role = ?');
if (!$stmt) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Prepare failed: ' . $conn->error]);
    exit();
}

$stmt->bind_param('iss', $messageId, $email, $role);

if (!$stmt->execute()) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Failed to delete message: ' . $stmt->error]);
    $stmt->close();
    $conn->close();
    exit();
}

if ($stmt->affected_rows <= 0) {
    echo json_encode(['success' => false, 'message' => 'Message not found or not allowed']);
} else {
    echo json_encode(['success' => true, 'message' => 'Message deleted successfully']);
}

$stmt->close();
$conn->close();
?>