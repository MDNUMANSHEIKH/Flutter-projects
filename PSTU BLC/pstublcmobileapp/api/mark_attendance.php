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

if (!$session_id || empty($email)) {
    http_response_code(400);
    logActivity($conn, $email, 'student', 'attendance_mark_failed', 'Missing session_id or email');
    echo json_encode(['success' => false, 'message' => 'session_id and email are required']);
    exit();
}

// 1. Verify session is still active and not private
$sql = "SELECT id, session_date, session_end, is_private FROM attendance_sessions WHERE id = ?";
$stmt = $conn->prepare($sql);
$stmt->bind_param("i", $session_id);
$stmt->execute();
$sessionRes = $stmt->get_result();
$session = $sessionRes->fetch_assoc();
$stmt->close();

if (!$session) {
    http_response_code(404);
    logActivity($conn, $email, 'student', 'attendance_mark_failed', "Session not found: $session_id");
    echo json_encode(['success' => false, 'message' => 'Attendance session not found']);
    exit();
}

if ($session['is_private'] == 1) {
    http_response_code(403);
    logActivity($conn, $email, 'student', 'attendance_mark_failed', "Session private: $session_id");
    echo json_encode(['success' => false, 'message' => 'This session is private']);
    exit();
}

$now = new DateTime();
$startTime = new DateTime($session['session_date']);
$endTime = new DateTime($session['session_end']);

$graceNow = clone $now;
$graceNow->modify('+5 minutes');

if ($graceNow < $startTime) {
    http_response_code(403);
    logActivity($conn, $email, 'student', 'attendance_mark_failed', "Session not started: $session_id");
    echo json_encode(['success' => false, 'message' => 'Session has not started yet']);
    exit();
}

if ($now > $endTime) {
    http_response_code(403);
    logActivity($conn, $email, 'student', 'attendance_mark_failed', "Session ended: $session_id");
    echo json_encode(['success' => false, 'message' => 'Session has already ended']);
    exit();
}

// 2. Check for duplicate marking
$checkSql = "SELECT id FROM attendance_records WHERE session_id = ? AND student_email = ?";
$cStmt = $conn->prepare($checkSql);
$cStmt->bind_param("is", $session_id, $email);
$cStmt->execute();
$checkRes = $cStmt->get_result();
$isDuplicate = ($checkRes->num_rows > 0);
$cStmt->close();

if ($isDuplicate) {
    logActivity($conn, $email, 'student', 'attendance_mark_duplicate', "Session ID: $session_id");
    echo json_encode(['success' => true, 'already_marked' => true, 'message' => 'Attendance already recorded']);
    exit();
}

// 3. Mark Attendance
$markSql = "INSERT INTO attendance_records (session_id, student_email) VALUES (?, ?)";
$mStmt = $conn->prepare($markSql);
$mStmt->bind_param("is", $session_id, $email);

if ($mStmt->execute()) {
    logActivity($conn, $email, 'student', 'attendance_mark', "Session ID: $session_id");
    echo json_encode(['success' => true, 'message' => 'Attendance marked successfully']);
} else {
    http_response_code(500);
    logActivity($conn, $email, 'student', 'attendance_mark_failed', 'Failed to record attendance: ' . $conn->error);
    echo json_encode(['success' => false, 'message' => 'Failed to record attendance: ' . $conn->error]);
}

$mStmt->close();
$conn->close();
?>
