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
date_default_timezone_set('Asia/Dhaka');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Method not allowed']);
    exit();
}

$data = json_decode(file_get_contents("php://input"), true);
$session_id = $data['session_id'] ?? null;
$email = trim(strtolower($data['email'] ?? ''));
$present = isset($data['present']) ? filter_var($data['present'], FILTER_VALIDATE_BOOLEAN) : null;

if (!$session_id || empty($email) || $present === null) {
    http_response_code(400);
    logActivity($conn, $email, 'teacher', 'attendance_manual_toggle_failed', 'session_id, email, and present are required');
    echo json_encode(['success' => false, 'message' => 'session_id, email, and present are required']);
    exit();
}

if ($present) {
    // Check if already present
    $checkSql = "SELECT id FROM attendance_records WHERE session_id = ? AND student_email = ?";
    $cStmt = $conn->prepare($checkSql);
    $cStmt->bind_param("is", $session_id, $email);
    $cStmt->execute();
    $checkRes = $cStmt->get_result();
    $isDuplicate = ($checkRes->num_rows > 0);
    $cStmt->close();

    if ($isDuplicate) {
        logActivity($conn, $email, 'teacher', 'attendance_manual_present', "Session ID: $session_id (already present)");
        echo json_encode(['success' => true, 'message' => 'Student already marked as present']);
    } else {
        $markSql = "INSERT INTO attendance_records (session_id, student_email) VALUES (?, ?)";
        $mStmt = $conn->prepare($markSql);
        $mStmt->bind_param("is", $session_id, $email);
        
        if ($mStmt->execute()) {
            logActivity($conn, $email, 'teacher', 'attendance_manual_present', "Session ID: $session_id");
            echo json_encode(['success' => true, 'message' => 'Student marked as present']);
        } else {
            http_response_code(500);
            logActivity($conn, $email, 'teacher', 'attendance_manual_toggle_failed', 'Failed to mark present: ' . $conn->error);
            echo json_encode(['success' => false, 'message' => 'Failed to mark present: ' . $conn->error]);
        }
        $mStmt->close();
    }
} else {
    // Mark as absent (Delete record)
    $sql = "DELETE FROM attendance_records WHERE session_id = ? AND student_email = ?";
    $stmt = $conn->prepare($sql);
    $stmt->bind_param("is", $session_id, $email);
    if ($stmt->execute()) {
        logActivity($conn, $email, 'teacher', 'attendance_manual_absent', "Session ID: $session_id");
        echo json_encode(['success' => true, 'message' => 'Student marked as absent']);
    } else {
        http_response_code(500);
        logActivity($conn, $email, 'teacher', 'attendance_manual_toggle_failed', 'Failed to mark absent: ' . $conn->error);
        echo json_encode(['success' => false, 'message' => 'Failed to mark absent: ' . $conn->error]);
    }
    $stmt->close();
}

$conn->close();
?>
