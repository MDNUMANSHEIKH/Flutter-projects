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

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Method not allowed']);
    exit();
}

$data = json_decode(file_get_contents('php://input'), true);

if (!$data) {
    $data = $_POST;
}

$assignmentId = intval($data['assignment_id'] ?? 0);
$studentEmail = trim(strtolower($data['student_email'] ?? ''));
$fileIds = $data['file_ids'] ?? [];
$fileNames = $data['file_names'] ?? [];

if ($assignmentId <= 0 || empty($studentEmail) || empty($fileIds)) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Missing required fields']);
    exit();
}

$fileIdsJson = json_encode($fileIds);
$fileNamesJson = json_encode($fileNames);

// Check if already submitted
$checkStmt = $conn->prepare("SELECT id FROM AssignmentSubmission WHERE assignment_id = ? AND student_email = ?");
$checkStmt->bind_param("is", $assignmentId, $studentEmail);
$checkStmt->execute();
$checkResult = $checkStmt->get_result();

if ($checkResult->num_rows > 0) {
    // Update existing submission
    $stmt = $conn->prepare("UPDATE AssignmentSubmission SET file_ids = ?, file_names = ?, submitted_at = ? WHERE assignment_id = ? AND student_email = ?");
    $stmt->bind_param("sssis", $fileIdsJson, $fileNamesJson, $currentTime, $assignmentId, $studentEmail);
} else {
    // Insert new submission
    $stmt = $conn->prepare("INSERT INTO AssignmentSubmission (assignment_id, student_email, file_ids, file_names, submitted_at) VALUES (?, ?, ?, ?, ?)");
    $stmt->bind_param("issss", $assignmentId, $studentEmail, $fileIdsJson, $fileNamesJson, $currentTime);
}

if ($stmt->execute()) {
    echo json_encode(['success' => true, 'message' => 'Assignment submitted successfully']);
} else {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Database error: ' . $stmt->error]);
}

$stmt->close();
$checkStmt->close();
$conn->close();
?>
