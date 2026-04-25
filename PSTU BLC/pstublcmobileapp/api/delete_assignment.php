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

if ($id <= 0 || $course_id <= 0 || $teacher_email === '') {
    echo json_encode(['success' => false, 'message' => 'Missing required fields']);
    exit();
}

$stmt = $conn->prepare("DELETE FROM `Assignment` WHERE id = ? AND course_id = ? AND LOWER(teacher_email) = ?");
if (!$stmt) {
    echo json_encode(['success' => false, 'message' => 'Prepare failed: ' . $conn->error]);
    exit();
}

$stmt->bind_param('iis', $id, $course_id, $teacher_email);

// Also delete related comments and submissions from database
$stmt_comments = $conn->prepare("DELETE FROM `assignment_comment_messages` WHERE assignment_id = ? AND course_id = ?");
if ($stmt_comments) {
    $stmt_comments->bind_param('ii', $id, $course_id);
    $stmt_comments->execute();
    $stmt_comments->close();
}

$stmt_submissions = $conn->prepare("DELETE FROM `AssignmentSubmission` WHERE assignment_id = ?");
if ($stmt_submissions) {
    $stmt_submissions->bind_param('i', $id);
    $stmt_submissions->execute();
    $stmt_submissions->close();
}

if ($stmt->execute()) {
    if ($stmt->affected_rows > 0) {
        logActivity($conn, $teacher_email, 'teacher', 'delete_assignment', "Course: $course_id, Assignment ID: $id");
        echo json_encode(['success' => true, 'message' => 'Assignment deleted successfully']);
    } else {
        echo json_encode(['success' => false, 'message' => 'Assignment not found or not allowed']);
    }
} else {
    echo json_encode(['success' => false, 'message' => 'Database error: ' . $stmt->error]);
}

$stmt->close();
$conn->close();
?>
