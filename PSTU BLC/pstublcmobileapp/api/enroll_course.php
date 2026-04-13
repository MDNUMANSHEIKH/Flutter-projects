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
$course_id = intval($data['course_id'] ?? 0);

if (empty($email) || $course_id === 0) {
    http_response_code(400);
    logActivity($conn, $email, 'student', 'course_enroll_failed', 'Missing required fields');
    echo json_encode(['success' => false, 'message' => 'Missing required fields']);
    exit();
}

// 1. Check if blocked
$checkSql = "SELECT is_blocked FROM enrollments WHERE student_email = ? AND course_id = ?";
$checkStmt = $conn->prepare($checkSql);
$checkStmt->bind_param('si', $email, $course_id);
$checkStmt->execute();
$checkResult = $checkStmt->get_result();
$enr = $checkResult->fetch_assoc();
$checkStmt->close();

if ($enr && $enr['is_blocked'] == 1) {
    http_response_code(403);
    echo json_encode(['success' => false, 'message' => 'You are blocked from this course. Contact the teacher.']);
    exit();
}

$sql = "INSERT INTO enrollments (student_email, course_id, is_blocked) VALUES (?, ?, 0) 
        ON DUPLICATE KEY UPDATE is_blocked = 0";
$stmt = $conn->prepare($sql);
$stmt->bind_param('si', $email, $course_id);

if ($stmt->execute()) {
    logActivity($conn, $email, 'student', 'course_enroll', "Course ID: $course_id");
    
    // 3. Notify student
    $cSql = "SELECT course_code, course_name FROM courses WHERE id = ?";
    $cStmt = $conn->prepare($cSql);
    $cStmt->bind_param("i", $course_id);
    $cStmt->execute();
    $cRes = $cStmt->get_result()->fetch_assoc();
    $course_info = ($cRes['course_code'] ?? 'Course') . ": " . ($cRes['course_name'] ?? '');
    $cStmt->close();

    $nSql = "INSERT INTO notifications (student_email, course_id, title, message, type) VALUES (?, ?, ?, ?, 'enrollment')";
    $notif_title = "Enrolled Successfully";
    $notif_msg = "You have successfully enrolled in $course_info.";
    $nStmt = $conn->prepare($nSql);
    $nStmt->bind_param("siss", $email, $course_id, $notif_title, $notif_msg);
    $nStmt->execute();
    $nStmt->close();

    echo json_encode(['success' => true, 'message' => 'Enrolled successfully']);
} else {
    logActivity($conn, $email, 'student', 'course_enroll_failed', 'Enrollment failed: ' . $conn->error);
    echo json_encode(['success' => false, 'message' => 'Enrollment failed: ' . $conn->error]);
}

$stmt->close();
$conn->close();
?>
