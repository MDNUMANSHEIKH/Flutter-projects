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
require_once 'student_utils.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Method not allowed']);
    exit();
}

$data = json_decode(file_get_contents('php://input'), true);
if (!$data) $data = $_POST;

$assignmentId = intval($data['assignment_id'] ?? 0);
$studentEmail = trim(strtolower($data['student_email'] ?? ''));

if ($assignmentId <= 0) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Assignment ID is required']);
    exit();
}

if (!empty($studentEmail)) {
    // Student view: show their own submission (any status)
    $stmt = $conn->prepare("SELECT * FROM AssignmentSubmission WHERE assignment_id = ? AND student_email = ?");
    $stmt->bind_param("is", $assignmentId, $studentEmail);
} else {
    // Teacher view: only show finalized (turned in) submissions
    $stmt = $conn->prepare("SELECT * FROM AssignmentSubmission WHERE assignment_id = ? AND is_turned_in = 1 ORDER BY submitted_at DESC");
    $stmt->bind_param("i", $assignmentId);
}

if (!$stmt->execute()) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Database error: ' . $stmt->error]);
    exit();
}

$result = $stmt->get_result();
$submissions = [];

while ($row = $result->fetch_assoc()) {
    $email = $row['student_email'];
    $table = getStudentTable($email);
    $name = 'Unknown Student';
    
    if ($table) {
        $studentStmt = $conn->prepare("SELECT name FROM $table WHERE email = ?");
        $studentStmt->bind_param("s", $email);
        $studentStmt->execute();
        $studentRes = $studentStmt->get_result();
        if ($studentRow = $studentRes->fetch_assoc()) {
            $name = $studentRow['name'];
        }
        $studentStmt->close();
    }
    
    $row['student_name'] = $name;
    $row['file_ids'] = json_decode($row['file_ids'], true);
    $row['file_names'] = json_decode($row['file_names'], true);
    $submissions[] = $row;
}

echo json_encode([
    'success' => true,
    'submissions' => $submissions
]);

$stmt->close();
$conn->close();
?>
