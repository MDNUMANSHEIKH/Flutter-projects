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

// Get ID from URL or JSON body
$data = json_decode(file_get_contents("php://input"), true);
$id = $data['id'] ?? ($_GET['id'] ?? null);

if (!$id) {
    logActivity($conn, null, 'teacher', 'attendance_session_delete_failed', 'Missing session ID');
    echo json_encode(['success' => false, 'message' => 'Missing session ID']);
    exit();
}

// Delete associated attendance records first
$delRecordsSql = "DELETE FROM attendance_records WHERE session_id = ?";
$recStmt = $conn->prepare($delRecordsSql);
$recStmt->bind_param("i", $id);
$recStmt->execute();
$recStmt->close();

$sql = "DELETE FROM attendance_sessions WHERE id = ?";
$stmt = $conn->prepare($sql);
$stmt->bind_param("i", $id);

if ($stmt->execute()) {
    logActivity($conn, null, 'teacher', 'attendance_session_delete', "Session ID: $id");
    echo json_encode(['success' => true, 'message' => 'Attendance session deleted successfully']);
} else {
    logActivity($conn, null, 'teacher', 'attendance_session_delete_failed', "Session ID: $id");
    echo json_encode(['success' => false, 'message' => 'Failed to delete attendance session']);
}

$stmt->close();
$conn->close();
?>
