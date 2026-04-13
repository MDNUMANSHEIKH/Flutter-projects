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

if ($conn->connect_error) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Database connection failed']);
    exit();
}

$conn->query("CREATE TABLE IF NOT EXISTS course_results (
    id INT AUTO_INCREMENT PRIMARY KEY,
    course_id INT NOT NULL,
    teacher_id INT NOT NULL,
    file_name VARCHAR(255) NOT NULL,
    file_path VARCHAR(255) NOT NULL,
    file_type VARCHAR(120) DEFAULT NULL,
    file_size INT DEFAULT 0,
    is_private TINYINT(1) NOT NULL DEFAULT 1,
    uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_course_id (course_id),
    INDEX idx_teacher_id (teacher_id)
)");

$colCheck = $conn->query("SHOW COLUMNS FROM course_results LIKE 'is_private'");
if ($colCheck && $colCheck->num_rows === 0) {
    $conn->query("ALTER TABLE course_results ADD COLUMN is_private TINYINT(1) NOT NULL DEFAULT 1 AFTER file_size");
}

$data = json_decode(file_get_contents('php://input'), true);
$resultId = (int)($data['result_id'] ?? 0);
$teacherEmail = trim(strtolower($data['teacher_email'] ?? ''));
$isPrivate = (int)($data['is_private'] ?? 1) === 1 ? 1 : 0;

if ($resultId <= 0 || empty($teacherEmail)) {
    http_response_code(400);
    logActivity($conn, $teacherEmail, 'teacher', 'result_visibility_toggle_failed', 'result_id and teacher_email are required');
    echo json_encode(['success' => false, 'message' => 'result_id and teacher_email are required']);
    exit();
}

$tStmt = $conn->prepare("SELECT id FROM teachers WHERE email = ?");
$tStmt->bind_param('s', $teacherEmail);
$tStmt->execute();
$tRes = $tStmt->get_result();
$teacher = $tRes->fetch_assoc();
$tStmt->close();

if (!$teacher) {
    http_response_code(404);
    logActivity($conn, $teacherEmail, 'teacher', 'result_visibility_toggle_failed', 'Teacher not found');
    echo json_encode(['success' => false, 'message' => 'Teacher not found']);
    exit();
}

$teacherId = (int)$teacher['id'];

$checkSql = "SELECT r.id, r.course_id, c.course_code, c.course_name
             FROM course_results r
             INNER JOIN courses c ON c.id = r.course_id
             WHERE r.id = ? AND r.teacher_id = ?";
$checkStmt = $conn->prepare($checkSql);
$checkStmt->bind_param('ii', $resultId, $teacherId);
$checkStmt->execute();
$checkRes = $checkStmt->get_result();
$row = $checkRes->fetch_assoc();
$checkStmt->close();

if (!$row) {
    http_response_code(403);
    logActivity($conn, $teacherEmail, 'teacher', 'result_visibility_toggle_failed', 'Unauthorized result file');
    echo json_encode(['success' => false, 'message' => 'Unauthorized result file']);
    exit();
}

$courseId = (int)$row['course_id'];

$updateStmt = $conn->prepare("UPDATE course_results SET is_private = ? WHERE id = ? AND teacher_id = ?");
$updateStmt->bind_param('iii', $isPrivate, $resultId, $teacherId);
$ok = $updateStmt->execute();
$updateStmt->close();

if (!$ok) {
    http_response_code(500);
    logActivity($conn, $teacherEmail, 'teacher', 'result_visibility_toggle_failed', 'Failed to update visibility');
    echo json_encode(['success' => false, 'message' => 'Failed to update visibility']);
    exit();
}

if ($isPrivate === 0) {
    $nSql = "INSERT INTO notifications (student_email, course_id, title, message, type)
             SELECT e.student_email, ?, ?, ?, 'result'
             FROM enrollments e
             WHERE e.course_id = ? AND IFNULL(e.is_blocked, 0) = 0";

    $notifTitle = 'Result Published: ' . ($row['course_code'] ?? 'Course');
    $notifMsg = 'A result file is now available for ' . ($row['course_code'] ?? '') . ' - ' . ($row['course_name'] ?? '') . '.';

    $nStmt = $conn->prepare($nSql);
    $nStmt->bind_param('issi', $courseId, $notifTitle, $notifMsg, $courseId);
    $nStmt->execute();
    $nStmt->close();
    logActivity($conn, $teacherEmail, 'teacher', 'result_publish', "Result ID: $resultId, Course ID: $courseId");
} else {
    logActivity($conn, $teacherEmail, 'teacher', 'result_private', "Result ID: $resultId, Course ID: $courseId");
}

echo json_encode([
    'success' => true,
    'message' => $isPrivate === 1 ? 'Result set to private' : 'Result published successfully'
]);

$conn->close();
?>
