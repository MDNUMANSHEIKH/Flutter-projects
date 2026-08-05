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
require_once 'attendance_notify_helper.php';

$course_id = $_GET['course_id'] ?? null;
if (!$course_id) {
    // try post
    $data = json_decode(file_get_contents("php://input"), true);
    $course_id = $data['course_id'] ?? null;
}

if (!$course_id) {
    echo json_encode(['success' => false, 'message' => 'Missing course_id']);
    exit();
}

checkAndNotifyActiveSessions($conn);

$sql = "SELECT 
    A.id, A.course_id, A.session_date, A.session_end, A.created_at, A.is_private, A.is_dynamic_qr, A.qr_interval, A.qr_code_hex,
    T.name AS teacher_name, 
    F.faculty_name, 
    C.course_code, C.course_name, C.session
FROM attendance_sessions A
JOIN courses C ON A.course_id = C.id
JOIN teachers T ON C.teacher_id = T.id
JOIN faculties F ON C.faculty_code = F.faculty_code
WHERE A.course_id = ?
ORDER BY A.session_date DESC";
$stmt = $conn->prepare($sql);
$stmt->bind_param("i", $course_id);
$stmt->execute();
$result = $stmt->get_result();

$sessions = [];
while ($row = $result->fetch_assoc()) {
    $sessions[] = $row;
}

echo json_encode([
    'success' => true,
    'sessions' => $sessions
]);

$stmt->close();
$conn->close();
?>
