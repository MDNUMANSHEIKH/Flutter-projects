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

$data = json_decode(file_get_contents("php://input"), true);
$email = trim($data['email'] ?? '');
$course_id = intval($data['course_id'] ?? 0);

if (empty($email) || $course_id === 0) {
    http_response_code(400);
    logActivity($conn, $email, 'student', 'course_unenroll_failed', 'Missing required fields');
    echo json_encode(['success' => false, 'message' => 'Missing required fields']);
    exit();
}

$sql = "DELETE FROM enrollments WHERE student_email = ? AND course_id = ? AND is_blocked = 0";
$stmt = $conn->prepare($sql);
$stmt->bind_param('si', $email, $course_id);

if ($stmt->execute()) {
    logActivity($conn, $email, 'student', 'course_unenroll', "Course ID: $course_id");
    echo json_encode(['success' => true, 'message' => 'Unenrolled successfully']);
} else {
    logActivity($conn, $email, 'student', 'course_unenroll_failed', 'Unenrollment failed: ' . $conn->error);
    echo json_encode(['success' => false, 'message' => 'Unenrollment failed: ' . $conn->error]);
}

$stmt->close();
$conn->close();
?>
