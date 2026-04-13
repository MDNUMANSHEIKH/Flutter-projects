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
$courseId = (int)($data['course_id'] ?? 0);

if ($courseId <= 0) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Course ID is required']);
    exit();
}

$stmt = $conn->prepare("SELECT id, file_name, file_path, file_type, file_size, is_private, uploaded_at FROM course_results WHERE course_id = ? ORDER BY uploaded_at DESC");
$stmt->bind_param('i', $courseId);
$stmt->execute();
$result = $stmt->get_result();

$rows = [];
while ($row = $result->fetch_assoc()) {
    $rows[] = $row;
}

echo json_encode(['success' => true, 'results' => $rows]);

$stmt->close();
$conn->close();
?>
