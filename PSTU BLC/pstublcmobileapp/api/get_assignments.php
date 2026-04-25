<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once 'db_config.php';

$data = json_decode(file_get_contents('php://input'), true);
$course_id = (int)($data['course_id'] ?? 0);
$student_email = trim(strtolower($data['student_email'] ?? ''));

if ($course_id <= 0) {
    echo json_encode(['success' => false, 'message' => 'course_id is required']);
    exit();
}

if (!empty($student_email)) {
    // Join with AssignmentSubmission to get is_turned_in for the specific student
    $stmt = $conn->prepare("
        SELECT a.*, IFNULL(s.is_turned_in, 0) as is_turned_in 
        FROM `Assignment` a 
        LEFT JOIN `AssignmentSubmission` s ON a.id = s.assignment_id AND s.student_email = ?
        WHERE a.course_id = ? 
        ORDER BY a.due_date DESC, a.created_at DESC
    ");
    $stmt->bind_param('si', $student_email, $course_id);
} else {
    $stmt = $conn->prepare("SELECT id, course_id, teacher_email, title, description, due_date, created_at, edited_at, is_private FROM `Assignment` WHERE course_id = ? ORDER BY due_date DESC, created_at DESC");
    $stmt->bind_param('i', $course_id);
}

if (!$stmt) {
    echo json_encode(['success' => false, 'message' => 'Prepare failed: ' . $conn->error]);
    exit();
}

$stmt->execute();
$result = $stmt->get_result();

$assignments = [];
while ($row = $result->fetch_assoc()) {
    $assignments[] = $row;
}

echo json_encode(['success' => true, 'assignments' => $assignments]);

$stmt->close();
$conn->close();
?>
