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
$fileIdToDelete = $data['file_id'] ?? '';

if ($assignmentId <= 0 || empty($studentEmail) || empty($fileIdToDelete)) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Missing required fields']);
    exit();
}

// Get current submission
$stmt = $conn->prepare("SELECT file_ids, file_names FROM AssignmentSubmission WHERE assignment_id = ? AND student_email = ?");
$stmt->bind_param("is", $assignmentId, $studentEmail);
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows === 0) {
    echo json_encode(['success' => false, 'message' => 'Submission not found']);
    exit();
}

$row = $result->fetch_assoc();
$fileIds = json_decode($row['file_ids'], true);
$fileNames = json_decode($row['file_names'], true);

$index = array_search($fileIdToDelete, $fileIds);
if ($index !== false) {
    array_splice($fileIds, $index, 1);
    array_splice($fileNames, $index, 1);
} else {
    echo json_encode(['success' => false, 'message' => 'File not found in submission']);
    exit();
}

if (empty($fileIds)) {
    // If no files left, delete the submission record
    $deleteStmt = $conn->prepare("DELETE FROM AssignmentSubmission WHERE assignment_id = ? AND student_email = ?");
    $deleteStmt->bind_param("is", $assignmentId, $studentEmail);
    if ($deleteStmt->execute()) {
        echo json_encode(['success' => true, 'message' => 'Submission deleted (empty)']);
    } else {
        echo json_encode(['success' => false, 'message' => 'Database error during deletion']);
    }
} else {
    // Update the record with remaining files and new timestamp
    $fileIdsJson = json_encode($fileIds);
    $fileNamesJson = json_encode($fileNames);
    $updateStmt = $conn->prepare("UPDATE AssignmentSubmission SET file_ids = ?, file_names = ?, submitted_at = ? WHERE assignment_id = ? AND student_email = ?");
    $updateStmt->bind_param("sssis", $fileIdsJson, $fileNamesJson, $currentTime, $assignmentId, $studentEmail);

    if ($updateStmt->execute()) {
        echo json_encode(['success' => true, 'message' => 'File removed from submission']);
    } else {
        echo json_encode(['success' => false, 'message' => 'Database error during update']);
    }
}

$conn->close();
?>
