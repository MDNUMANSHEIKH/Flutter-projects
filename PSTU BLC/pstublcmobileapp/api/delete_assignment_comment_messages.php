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
$messageIds = $data['message_ids'] ?? [];
$email = trim(strtolower((string)($data['email'] ?? '')));
$role = trim(strtolower((string)($data['role'] ?? '')));

if (empty($messageIds) || !is_array($messageIds)) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Message IDs are required as an array']);
    exit();
}

if ($email === '' || !in_array($role, ['teacher', 'student'], true)) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Valid email and role are required']);
    exit();
}

$idsString = implode(',', array_map('intval', $messageIds));

$sql = "DELETE FROM assignment_comment_messages WHERE id IN ($idsString) AND LOWER(sender_email) = ? AND sender_role = ?";
$stmt = $conn->prepare($sql);

if (!$stmt) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Prepare failed: ' . $conn->error]);
    exit();
}

$stmt->bind_param('ss', $email, $role);

if (!$stmt->execute()) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Failed to delete messages: ' . $stmt->error]);
    $stmt->close();
    $conn->close();
    exit();
}

$affected = $stmt->affected_rows;
if ($affected <= 0) {
    echo json_encode(['success' => false, 'message' => 'No messages were deleted. They may not exist or you may not have permission.']);
} else {
    echo json_encode(['success' => true, 'message' => "$affected message(s) deleted successfully"]);
}

$stmt->close();
$conn->close();
?>
