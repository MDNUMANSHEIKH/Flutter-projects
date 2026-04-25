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
date_default_timezone_set('Asia/Dhaka');

$data = json_decode(file_get_contents('php://input'), true);

$course_id = (int)($data['course_id'] ?? 0);
$teacher_email = trim(strtolower((string)($data['teacher_email'] ?? '')));
$title = trim((string)($data['title'] ?? ''));
$due_date = trim((string)($data['due_date'] ?? ''));
$description = trim((string)($data['description'] ?? ''));
$is_private = (int)($data['is_private'] ?? 1);
$is_private = $is_private === 1 ? 1 : 0;

if ($course_id <= 0 || $teacher_email === '' || $title === '' || $due_date === '' || $description === '') {
    echo json_encode(['success' => false, 'message' => 'Missing required fields']);
    exit();
}

$parsedDueDate = DateTime::createFromFormat('Y-m-d', $due_date);
if (!$parsedDueDate || $parsedDueDate->format('Y-m-d') !== $due_date) {
    echo json_encode(['success' => false, 'message' => 'Invalid due date']);
    exit();
}

$today = new DateTime('today');
if ($parsedDueDate < $today) {
    echo json_encode(['success' => false, 'message' => 'Past date is not allowed']);
    exit();
}

$created_at = (new DateTime())->format('Y-m-d H:i:s');

$stmt = $conn->prepare("INSERT INTO `Assignment` (course_id, teacher_email, title, description, due_date, created_at, is_private) VALUES (?, ?, ?, ?, ?, ?, ?)");
if (!$stmt) {
    echo json_encode(['success' => false, 'message' => 'Prepare failed: ' . $conn->error]);
    exit();
}

$stmt->bind_param('isssssi', $course_id, $teacher_email, $title, $description, $due_date, $created_at, $is_private);

if ($stmt->execute()) {
    $assignment_id = $stmt->insert_id;
    logActivity($conn, $teacher_email, 'teacher', 'create_assignment', "Course: $course_id, Assignment ID: $assignment_id, Title: $title");
    echo json_encode([
        'success' => true,
        'message' => 'Assignment created successfully',
        'assignment_id' => $assignment_id,
    ]);
} else {
    echo json_encode(['success' => false, 'message' => 'Database error: ' . $stmt->error]);
}

$stmt->close();
$conn->close();
?>
