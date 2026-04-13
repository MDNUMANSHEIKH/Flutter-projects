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
$email = trim(strtolower($data['email'] ?? ''));

if (empty($email)) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Email is required']);
    exit();
}

$sql = "SELECT
            r.id,
            r.file_name,
            r.file_path,
            r.file_type,
            r.file_size,
            r.uploaded_at,
            c.id AS course_id,
            c.course_code,
            c.course_name,
            c.session,
            t.name AS teacher_name
        FROM enrollments e
        INNER JOIN courses c ON c.id = e.course_id
        INNER JOIN course_results r ON r.course_id = c.id
        LEFT JOIN teachers t ON t.id = c.teacher_id
        WHERE e.student_email = ?
          AND IFNULL(e.is_blocked, 0) = 0
                    AND IFNULL(r.is_private, 1) = 0
        ORDER BY r.uploaded_at DESC";

$stmt = $conn->prepare($sql);
$stmt->bind_param('s', $email);
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
