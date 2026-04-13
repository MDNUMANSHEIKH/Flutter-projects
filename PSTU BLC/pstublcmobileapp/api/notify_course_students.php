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

$data = json_decode(file_get_contents('php://input'), true);
$courseId = (int)($data['course_id'] ?? 0);
$title = trim((string)($data['title'] ?? 'New Material'));
$message = trim((string)($data['message'] ?? 'A new course material has been uploaded.'));
$type = trim((string)($data['type'] ?? 'material'));
$excludeEmail = trim(strtolower((string)($data['exclude_email'] ?? '')));
$actorEmail = trim(strtolower((string)($data['actor_email'] ?? '')));
$actorRole = trim((string)($data['actor_role'] ?? 'system'));

if ($courseId <= 0) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Course ID is required']);
    exit();
}

$sql = "INSERT INTO notifications (student_email, course_id, title, message, type)
        SELECT e.student_email, ?, ?, ?, ?
        FROM enrollments e
        WHERE e.course_id = ? AND e.is_blocked = 0";
$params = [$courseId, $title, $message, $type, $courseId];
$types = 'isssi';

if ($excludeEmail !== '') {
    $sql .= " AND LOWER(e.student_email) <> ?";
    $params[] = $excludeEmail;
    $types .= 's';
}

$stmt = $conn->prepare($sql);
if (!$stmt) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Prepare failed: ' . $conn->error]);
    exit();
}

$stmt->bind_param($types, ...$params);

if ($stmt->execute()) {
    logActivity($conn, $actorEmail ?: null, $actorRole ?: 'system', 'course_material_notify', "Course ID: $courseId, type: $type");
    echo json_encode(['success' => true, 'message' => 'Notifications sent']);
} else {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Failed to send notifications: ' . $stmt->error]);
}

$stmt->close();
$conn->close();
?>