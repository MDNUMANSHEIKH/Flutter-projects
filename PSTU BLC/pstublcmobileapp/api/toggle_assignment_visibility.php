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

$data = json_decode(file_get_contents('php://input'), true);
$id = (int)($data['id'] ?? 0);
$course_id = (int)($data['course_id'] ?? 0);
$teacher_email = trim(strtolower((string)($data['teacher_email'] ?? '')));
$is_private = (int)($data['is_private'] ?? -1);

if ($id <= 0 || $course_id <= 0 || $teacher_email === '' || ($is_private !== 0 && $is_private !== 1)) {
    echo json_encode(['success' => false, 'message' => 'Missing required fields']);
    exit();
}

$stmt = $conn->prepare("UPDATE `Assignment` SET is_private = ? WHERE id = ? AND course_id = ? AND LOWER(teacher_email) = ?");
if (!$stmt) {
    echo json_encode(['success' => false, 'message' => 'Prepare failed: ' . $conn->error]);
    exit();
}

$stmt->bind_param('iiis', $is_private, $id, $course_id, $teacher_email);

if ($stmt->execute()) {
    if ($stmt->affected_rows > 0) {
        $label = $is_private === 1 ? 'private' : 'public';
        logActivity($conn, $teacher_email, 'teacher', 'toggle_assignment_visibility', "Course: $course_id, Assignment ID: $id, Visibility: $label");
        echo json_encode(['success' => true, 'message' => 'Assignment visibility updated']);
    } else {
        echo json_encode(['success' => false, 'message' => 'Assignment not found or not allowed']);
    }
} else {
    echo json_encode(['success' => false, 'message' => 'Database error: ' . $stmt->error]);
}

$stmt->close();
$conn->close();
?>
