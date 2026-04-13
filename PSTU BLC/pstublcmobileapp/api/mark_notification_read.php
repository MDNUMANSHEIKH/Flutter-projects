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

$data = json_decode(file_get_contents("php://input"), true);
$id = trim($data['id'] ?? '');
$email = trim(strtolower($data['email'] ?? ''));
$mark_all = (bool)($data['mark_all'] ?? false);

if (empty($id) && !$mark_all) {
    logActivity($conn, $email, 'student', 'notification_mark_read_failed', 'Notification ID or mark_all missing');
    echo json_encode(['success' => false, 'message' => 'Notification ID or mark_all is required']);
    exit();
}

if ($mark_all) {
    if (empty($email)) {
        logActivity($conn, $email, 'student', 'notification_mark_read_failed', 'Email is required for mark_all');
        echo json_encode(['success' => false, 'message' => 'Email is required to mark all as read']);
        exit();
    }
    $sql = "UPDATE notifications SET is_read = 1 WHERE student_email = ?";
    $stmt = $conn->prepare($sql);
    $stmt->bind_param("s", $email);
} else {
    $sql = "UPDATE notifications SET is_read = 1 WHERE id = ?";
    $stmt = $conn->prepare($sql);
    $stmt->bind_param("i", $id);
}

if ($stmt->execute()) {
    logActivity($conn, $email, 'student', 'notification_mark_read', $mark_all ? 'mark_all=true' : ('notification_id=' . $id));
    echo json_encode(['success' => true, 'message' => 'Notification(s) marked as read']);
} else {
    logActivity($conn, $email, 'student', 'notification_mark_read_failed', 'Database error: ' . $stmt->error);
    echo json_encode(['success' => false, 'message' => 'Database error: ' . $stmt->error]);
}

$stmt->close();
$conn->close();
?>
