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

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Method not allowed']);
    exit();
}

$data = json_decode(file_get_contents("php://input"), true);
if (!$data) {
    $data = $_POST;
}

$email = trim(strtolower($data['email'] ?? ''));
$courseId = intval($data['course_id'] ?? 0);
$password = $data['password'] ?? '';

if (empty($email) || empty($password) || empty($courseId)) {
    http_response_code(400);
    logActivity($conn, $email, 'teacher', 'course_delete_failed', 'Missing required fields');
    echo json_encode(['success' => false, 'message' => 'Missing required fields']);
    exit();
}

$stmt = $conn->prepare("SELECT id, password_hash FROM teachers WHERE LOWER(email) = ?");
if (!$stmt) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Database error']);
    exit();
}

$stmt->bind_param('s', $email);
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows === 0) {
    http_response_code(404);
    logActivity($conn, $email, 'teacher', 'course_delete_failed', 'Teacher not found');
    echo json_encode(['success' => false, 'message' => 'Teacher not found']);
    exit();
}

$user = $result->fetch_assoc();
$teacherId = $user['id'];
$storedEncrypted = $user['password_hash'];
$decryptedStored = decryptPassword($storedEncrypted);

if ($password !== $decryptedStored) {
    http_response_code(401);
    logActivity($conn, $email, 'teacher', 'course_delete_failed', 'Incorrect password');
    echo json_encode(['success' => false, 'message' => 'Please enter the correct password']);
    exit();
}

$conn->begin_transaction();

$discussionStmt = $conn->prepare("DELETE FROM course_discussion_messages WHERE course_id = ?");
if (!$discussionStmt) {
    $conn->rollback();
    http_response_code(500);
    logActivity($conn, $email, 'teacher', 'course_delete_failed', 'Prepare failed for discussion cleanup: ' . $conn->error);
    echo json_encode(['success' => false, 'message' => 'Failed to prepare discussion cleanup']);
    exit();
}
$discussionStmt->bind_param('i', $courseId);
if (!$discussionStmt->execute()) {
    $discussionError = $discussionStmt->error;
    $discussionStmt->close();
    $conn->rollback();
    http_response_code(500);
    logActivity($conn, $email, 'teacher', 'course_delete_failed', 'Failed to delete discussion messages: ' . $discussionError);
    echo json_encode(['success' => false, 'message' => 'Failed to delete course discussion messages']);
    exit();
}
$discussionStmt->close();

$deleteStmt = $conn->prepare("DELETE FROM courses WHERE id = ? AND teacher_id = ?");
if (!$deleteStmt) {
    $conn->rollback();
    http_response_code(500);
    logActivity($conn, $email, 'teacher', 'course_delete_failed', 'Prepare failed: ' . $conn->error);
    echo json_encode(['success' => false, 'message' => 'Failed to prepare course delete']);
    exit();
}
$deleteStmt->bind_param('ii', $courseId, $teacherId);

if ($deleteStmt->execute()) {
    if ($deleteStmt->affected_rows > 0) {
        $conn->commit();
        logActivity($conn, $email, 'teacher', 'course_delete', "Course ID: $courseId");
        echo json_encode(['success' => true, 'message' => 'Course deleted successfully']);
    } else {
        $conn->rollback();
        http_response_code(404);
        logActivity($conn, $email, 'teacher', 'course_delete_failed', 'Course not found or unauthorized');
        echo json_encode(['success' => false, 'message' => 'Course not found or unauthorized']);
    }
} else {
    $conn->rollback();
    http_response_code(500);
    logActivity($conn, $email, 'teacher', 'course_delete_failed', 'Database error: ' . $deleteStmt->error);
    echo json_encode(['success' => false, 'message' => 'Failed to delete course: ' . $deleteStmt->error]);
}

$deleteStmt->close();
$stmt->close();
$conn->close();
?>
