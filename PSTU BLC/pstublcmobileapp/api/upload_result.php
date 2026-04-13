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

$teacherEmail = trim(strtolower($_POST['teacher_email'] ?? ''));
$courseId = (int)($_POST['course_id'] ?? 0);

if (empty($teacherEmail) || $courseId <= 0 || empty($_FILES['result_file'])) {
    http_response_code(400);
    logActivity($conn, $teacherEmail, 'teacher', 'result_upload_failed', 'Required fields missing');
    echo json_encode(['success' => false, 'message' => 'Required fields missing']);
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

$tStmt = $conn->prepare("SELECT id FROM teachers WHERE email = ?");
$tStmt->bind_param('s', $teacherEmail);
$tStmt->execute();
$tRes = $tStmt->get_result();
$teacher = $tRes->fetch_assoc();
$tStmt->close();

if (!$teacher) {
    http_response_code(404);
    logActivity($conn, $teacherEmail, 'teacher', 'result_upload_failed', 'Teacher not found');
    echo json_encode(['success' => false, 'message' => 'Teacher not found']);
    exit();
}

$teacherId = (int)$teacher['id'];

$cStmt = $conn->prepare("SELECT id, course_code, course_name, session FROM courses WHERE id = ? AND teacher_id = ?");
$cStmt->bind_param('ii', $courseId, $teacherId);
$cStmt->execute();
$cRes = $cStmt->get_result();
$course = $cRes->fetch_assoc();
$cStmt->close();

if (!$course) {
    http_response_code(403);
    logActivity($conn, $teacherEmail, 'teacher', 'result_upload_failed', 'Unauthorized or invalid course');
    echo json_encode(['success' => false, 'message' => 'Unauthorized or invalid course']);
    exit();
}

$file = $_FILES['result_file'];
$ext = strtolower(pathinfo($file['name'], PATHINFO_EXTENSION));
$allowed = ['pdf', 'doc', 'docx'];

if (!in_array($ext, $allowed)) {
    http_response_code(400);
    logActivity($conn, $teacherEmail, 'teacher', 'result_upload_failed', 'Invalid file type');
    echo json_encode(['success' => false, 'message' => 'Only PDF, DOC, DOCX files are allowed']);
    exit();
}

$uploadDir = '../uploads/results/';
if (!is_dir($uploadDir)) {
    @mkdir($uploadDir, 0777, true);
}

$newFileName = time() . '_' . preg_replace('/[^a-zA-Z0-9._-]/', '_', $file['name']);
$targetPath = $uploadDir . $newFileName;

if (!move_uploaded_file($file['tmp_name'], $targetPath)) {
    http_response_code(500);
    logActivity($conn, $teacherEmail, 'teacher', 'result_upload_failed', 'File move/upload failed');
    echo json_encode(['success' => false, 'message' => 'Upload failed']);
    exit();
}

$isPrivate = 1;
$stmt = $conn->prepare("INSERT INTO course_results (course_id, teacher_id, file_name, file_path, file_type, file_size, is_private) VALUES (?, ?, ?, ?, ?, ?, ?)");
$stmt->bind_param('iisssii', $courseId, $teacherId, $file['name'], $newFileName, $file['type'], $file['size'], $isPrivate);

if (!$stmt->execute()) {
    @unlink($targetPath);
    http_response_code(500);
    logActivity($conn, $teacherEmail, 'teacher', 'result_upload_failed', 'Database error while inserting result');
    echo json_encode(['success' => false, 'message' => 'Database error']);
    $stmt->close();
    exit();
}
$stmt->close();

logActivity($conn, $teacherEmail, 'teacher', 'result_upload', "Course ID: $courseId, File: " . $file['name']);

echo json_encode([
    'success' => true,
    'message' => 'Result uploaded successfully (default: private)'
]);

$conn->close();
?>
