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
date_default_timezone_set('Asia/Dhaka');
$currentTime = date('Y-m-d H:i:s');

$data = json_decode(file_get_contents('php://input'), true);
if (!$data) $data = $_POST;

$assignmentId = intval($data['assignment_id'] ?? 0);
$studentEmail = trim(strtolower($data['student_email'] ?? ''));
$isTurnedIn = intval($data['is_turned_in'] ?? 0);

if ($assignmentId <= 0 || empty($studentEmail)) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Missing required fields']);
    exit();
}

$stmt = $conn->prepare("UPDATE AssignmentSubmission SET is_turned_in = ?, turned_in_at = ? WHERE assignment_id = ? AND student_email = ?");
$turnedInAt = ($isTurnedIn == 1) ? $currentTime : null;
$stmt->bind_param("isis", $isTurnedIn, $turnedInAt, $assignmentId, $studentEmail);

if ($stmt->execute()) {
    echo json_encode(['success' => true, 'message' => 'Submission status updated', 'is_turned_in' => $isTurnedIn]);
} else {
    echo json_encode(['success' => false, 'message' => 'Database error']);
}

$conn->close();
?>
