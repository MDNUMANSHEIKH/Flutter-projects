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

$is_dynamic_qr = (!empty($data['is_dynamic_qr'])) ? 1 : 0;
$qr_interval = null;
$qr_code_hex = null;

if ($is_dynamic_qr === 1) {
    $qr_interval = isset($data['qr_interval']) ? intval($data['qr_interval']) : 3;
    if ($qr_interval < 1) $qr_interval = 1;
    if ($qr_interval > 20) $qr_interval = 20;
    $qr_code_hex = bin2hex(random_bytes(24));
}

$stmt = $conn->prepare("INSERT INTO attendance_sessions (course_id, session_date, session_end, is_dynamic_qr, qr_interval, qr_code_hex) VALUES (?, ?, ?, ?, ?, ?)");
$stmt->bind_param("issiis", $course_id, $session_date, $session_end, $is_dynamic_qr, $qr_interval, $qr_code_hex);

if ($stmt->execute()) {
    $session_id = $stmt->insert_id;
    logActivity($conn, $teacher_email, 'teacher', 'create_attendance', "Course: $course_id, Range: $session_date to $session_end");
    
    require_once 'attendance_notify_helper.php';
    checkAndNotifyActiveSessions($conn);

    echo json_encode(['success' => true, 'message' => 'Attendance session created']);
} else {
    echo json_encode(['success' => false, 'message' => 'Database error: ' . $stmt->error]);
}

$stmt->close();
$conn->close();
?>
