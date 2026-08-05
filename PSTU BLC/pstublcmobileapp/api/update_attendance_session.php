<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once 'db_config.php';
require_once 'logger.php';

$data = json_decode(file_get_contents("php://input"), true);
$id = $data['id'] ?? null;
$session_date = $data['session_date'] ?? null;
$session_end = $data['session_end'] ?? null;
$is_private = $data['is_private'] ?? null;

if (!$id || !$session_date || !$session_end) {
    logActivity($conn, null, 'teacher', 'attendance_session_update_failed', 'Missing required fields');
    echo json_encode(['success' => false, 'message' => 'Missing required fields']);
    exit();
}

if ($is_private !== null) {
    // Reset notified = 0 when toggled so active transition can notify un-marked students
    $sql = "UPDATE attendance_sessions SET session_date = ?, session_end = ?, is_private = ?, notified = 0 WHERE id = ?";
    $stmt = $conn->prepare($sql);
    $stmt->bind_param("ssii", $session_date, $session_end, $is_private, $id);
} else {
    $sql = "UPDATE attendance_sessions SET session_date = ?, session_end = ? WHERE id = ?";
    $stmt = $conn->prepare($sql);
    $stmt->bind_param("ssi", $session_date, $session_end, $id);
}

if ($stmt->execute()) {
    logActivity($conn, null, 'teacher', 'attendance_session_update', "Session ID: $id");

    require_once 'attendance_notify_helper.php';
    checkAndNotifyActiveSessions($conn);

    echo json_encode(['success' => true, 'message' => 'Attendance session updated successfully']);
} else {
    logActivity($conn, null, 'teacher', 'attendance_session_update_failed', 'Failed for session ID: ' . $id);
    echo json_encode(['success' => false, 'message' => 'Failed to update attendance session']);
}

$stmt->close();
$conn->close();
?>
