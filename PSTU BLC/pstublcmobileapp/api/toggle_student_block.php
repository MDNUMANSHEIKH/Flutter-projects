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
$courseId = intval($data['course_id'] ?? 0);
$email = trim($data['student_email'] ?? '');
$block = isset($data['block']) ? ($data['block'] ? 1 : 0) : 0;

if ($courseId === 0 || empty($email)) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Missing required fields']);
    exit();
}

// 1. Check if record exists
$sqlCheck = "SELECT id FROM enrollments WHERE course_id = ? AND student_email = ?";
$stmtCheck = $conn->prepare($sqlCheck);
$stmtCheck->bind_param('is', $courseId, $email);
$stmtCheck->execute();
$resCheck = $stmtCheck->get_result();
$record = $resCheck->fetch_assoc();
$stmtCheck->close();

if ($record) {
    // Update existing record
    $sqlUpper = "UPDATE enrollments SET is_blocked = ? WHERE course_id = ? AND student_email = ?";
    $stmtUpper = $conn->prepare($sqlUpper);
    $stmtUpper->bind_param('iis', $block, $courseId, $email);
} else {
    // Create new record as blocked
    $sqlUpper = "INSERT INTO enrollments (course_id, student_email, is_blocked) VALUES (?, ?, ?)";
    $stmtUpper = $conn->prepare($sqlUpper);
    $stmtUpper->bind_param('isi', $courseId, $email, $block);
}

if ($stmtUpper->execute()) {
    $action = $block ? 'blocked' : 'unblocked';
    logActivity($conn, $email, 'teacher', 'student_block_toggle', "$action for course ID $courseId");

    // 2. Notify student
    $cSql = "SELECT course_code, course_name FROM courses WHERE id = ?";
    $cStmt = $conn->prepare($cSql);
    $cStmt->bind_param("i", $courseId);
    $cStmt->execute();
    $cRes = $cStmt->get_result()->fetch_assoc();
    $course_info = ($cRes['course_code'] ?? 'Course') . ": " . ($cRes['course_name'] ?? '');
    $cStmt->close();

    $nSql = "INSERT INTO notifications (student_email, course_id, title, message, type) VALUES (?, ?, ?, ?, 'block_status')";
    $notif_title = $block ? "Access Restricted" : "Access Restored";
    $notif_msg = "Your access to $course_info has been " . ($block ? "blocked" : "restored") . " by the teacher.";
    $nStmt = $conn->prepare($nSql);
    $nStmt->bind_param("siss", $email, $courseId, $notif_title, $notif_msg);
    $nStmt->execute();
    $nStmt->close();

    echo json_encode(['success' => true, 'message' => "Student successfully $action and notified"]);
} else {
    echo json_encode(['success' => false, 'message' => 'Failed to toggle block status: ' . $conn->error]);
}

$stmtUpper->close();
$conn->close();
?>
