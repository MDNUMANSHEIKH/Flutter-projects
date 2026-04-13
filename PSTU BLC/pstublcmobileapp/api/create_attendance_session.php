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

$course_id = $data['course_id'] ?? null;
$session_date = $data['session_date'] ?? null;
$session_end = $data['session_end'] ?? null;
$teacher_email = $data['teacher_email'] ?? 'unknown';

if (!$course_id || !$session_date || !$session_end) {
    echo json_encode(['success' => false, 'message' => 'Missing course_id, session_date, or session_end']);
    exit();
}

$pickedDate = new DateTime($session_date);
$pickedEndDate = new DateTime($session_end);
$now = new DateTime();

if ($pickedDate < $now->modify('-12 hours')) { // Using our 12h grace period from earlier
    echo json_encode(['success' => false, 'message' => 'Cannot schedule attendance too far in the past']);
    exit();
}

if ($pickedEndDate <= $pickedDate) {
    echo json_encode(['success' => false, 'message' => 'End time must be after start time']);
    exit();
}

$stmt = $conn->prepare("INSERT INTO attendance_sessions (course_id, session_date, session_end) VALUES (?, ?, ?)");
$stmt->bind_param("iss", $course_id, $session_date, $session_end);

if ($stmt->execute()) {
    $session_id = $stmt->insert_id;
    logActivity($conn, $teacher_email, 'teacher', 'create_attendance', "Course: $course_id, Range: $session_date to $session_end");
    
    // 1. Get Course Code/Name for notification title
    $cSql = "SELECT course_code, course_name FROM courses WHERE id = ?";
    $cStmt = $conn->prepare($cSql);
    $cStmt->bind_param("i", $course_id);
    $cStmt->execute();
    $cRes = $cStmt->get_result()->fetch_assoc();
    $course_info = ($cRes['course_code'] ?? 'Course') . ": " . ($cRes['course_name'] ?? '');
    $cStmt->close();

    // 2. Notify all enrolled students (including blocked ones? User said 'if any course for me or any attendance launched'). 
    // Usually, blocked students shouldn't get notifications.
    $nSql = "INSERT INTO notifications (student_email, course_id, title, message, type) 
             SELECT student_email, ?, ?, ?, 'attendance' 
             FROM enrollments 
             WHERE course_id = ? AND is_blocked = 0";
    
    $notif_title = "Attendance Session Started";
    $notif_msg = "A new attendance session has been launched for $course_info. Please mark your attendance.";
    
    $nStmt = $conn->prepare($nSql);
    $nStmt->bind_param("issi", $course_id, $notif_title, $notif_msg, $course_id);
    $nStmt->execute();
    $nStmt->close();

    echo json_encode(['success' => true, 'message' => 'Attendance session created and students notified']);
} else {
    echo json_encode(['success' => false, 'message' => 'Database error: ' . $stmt->error]);
}

$stmt->close();
$conn->close();
?>
