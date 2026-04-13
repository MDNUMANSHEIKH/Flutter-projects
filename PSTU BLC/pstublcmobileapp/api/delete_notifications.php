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
$email = trim(strtolower($data['email'] ?? ''));

if (empty($email)) {
    logActivity($conn, $email, 'student', 'notifications_clear_failed', 'Email is required');
    echo json_encode(['success' => false, 'message' => 'Email is required to clear notifications']);
    exit();
}

$sql = "DELETE FROM notifications WHERE student_email = ?";
$stmt = $conn->prepare($sql);
$stmt->bind_param("s", $email);

if ($stmt->execute()) {
    logActivity($conn, $email, 'student', 'notifications_cleared');
    echo json_encode(['success' => true, 'message' => 'Notifications cleared successfully']);
} else {
    logActivity($conn, $email, 'student', 'notifications_clear_failed', 'Database error: ' . $stmt->error);
    echo json_encode(['success' => false, 'message' => 'Database error: ' . $stmt->error]);
}

$stmt->close();
$conn->close();
?>
