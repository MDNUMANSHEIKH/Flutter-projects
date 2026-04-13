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

$data = json_decode(file_get_contents("php://input"), true);
$courseId = $data['course_id'] ?? '';

if (empty($courseId)) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Course ID is required']);
    exit();
}

$stmt = $conn->prepare("SELECT id, file_name, file_path, file_type, file_size, uploaded_at FROM course_materials WHERE course_id = ? ORDER BY uploaded_at DESC");
$stmt->bind_param('i', $courseId);
$stmt->execute();
$result = $stmt->get_result();

$materials = [];
while ($row = $result->fetch_assoc()) {
    $materials[] = $row;
}

echo json_encode(['success' => true, 'materials' => $materials]);

$stmt->close();
$conn->close();
?>
