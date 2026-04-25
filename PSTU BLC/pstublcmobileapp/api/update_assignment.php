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

$id = (int)($data['id'] ?? 0);
$course_id = (int)($data['course_id'] ?? 0);
$teacher_email = trim(strtolower((string)($data['teacher_email'] ?? '')));
$hasTitle = array_key_exists('title', $data);
$hasDueDate = array_key_exists('due_date', $data);
$hasDescription = array_key_exists('description', $data);
$hasIsPrivate = array_key_exists('is_private', $data);

$title = trim((string)($data['title'] ?? ''));
$due_date = trim((string)($data['due_date'] ?? ''));
$description = trim((string)($data['description'] ?? ''));
$is_private = (int)($data['is_private'] ?? 0);
$is_private = $is_private === 1 ? 1 : 0;

if ($id <= 0 || $course_id <= 0 || $teacher_email === '') {
    echo json_encode(['success' => false, 'message' => 'Missing required fields']);
    exit();
}

if (!$hasTitle && !$hasDueDate && !$hasDescription) {
    echo json_encode(['success' => false, 'message' => 'No fields provided to update']);
    exit();
}

if ($hasTitle && $title === '') {
    echo json_encode(['success' => false, 'message' => 'Title cannot be empty']);
    exit();
}

if ($hasDescription && $description === '') {
    echo json_encode(['success' => false, 'message' => 'Description cannot be empty']);
    exit();
}

if ($hasDueDate) {
    $parsedDueDate = DateTime::createFromFormat('Y-m-d H:i:s', $due_date);
    if (!$parsedDueDate) {
        $parsedDueDate = DateTime::createFromFormat('Y-m-d', $due_date);
    }
    
    if (!$parsedDueDate) {
        echo json_encode(['success' => false, 'message' => 'Invalid due date format. Use Y-m-d or Y-m-d H:i:s']);
        exit();
    }

    $today = new DateTime('today');
    // Allow past dates for teachers to manually expire assignments
    /*
    if ($parsedDueDate < $today) {
        echo json_encode(['success' => false, 'message' => 'Past date is not allowed']);
        exit();
    }
    */
}

$edited_at = (new DateTime())->format('Y-m-d H:i:s');
$fields = [];
$types = '';
$params = [];

if ($hasTitle) {
    $fields[] = 'title = ?';
    $types .= 's';
    $params[] = $title;
}
if ($hasDueDate) {
    $fields[] = 'due_date = ?';
    $types .= 's';
    $params[] = $due_date;
}
if ($hasDescription) {
    $fields[] = 'description = ?';
    $types .= 's';
    $params[] = $description;
}
if ($hasIsPrivate) {
    $fields[] = 'is_private = ?';
    $types .= 'i';
    $params[] = $is_private;
}
$fields[] = 'edited_at = ?';
$types .= 's';
$params[] = $edited_at;

$sql = "UPDATE `Assignment` SET " . implode(', ', $fields) . " WHERE id = ? AND course_id = ? AND LOWER(teacher_email) = ?";
$stmt = $conn->prepare($sql);
if (!$stmt) {
    echo json_encode(['success' => false, 'message' => 'Prepare failed: ' . $conn->error]);
    exit();
}

$types .= 'iis';
$params[] = $id;
$params[] = $course_id;
$params[] = $teacher_email;

$stmt->bind_param($types, ...$params);

if ($stmt->execute()) {
    if ($stmt->affected_rows > 0) {
        logActivity($conn, $teacher_email, 'teacher', 'update_assignment', "Course: $course_id, Assignment ID: $id");
        echo json_encode(['success' => true, 'message' => 'Assignment updated successfully']);
    } else {
        echo json_encode(['success' => true, 'message' => 'No changes made']);
    }
} else {
    echo json_encode(['success' => false, 'message' => 'Database error: ' . $stmt->error]);
}

$stmt->close();
$conn->close();
?>
