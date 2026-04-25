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

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Method not allowed']);
    exit();
}

$data = json_decode(file_get_contents("php://input"), true);
$courseId = trim($data['course_id'] ?? '');

if (empty($courseId)) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'course_id is required']);
    exit();
}

// 1. Get course details
$fSql = "SELECT faculty_code, session FROM courses WHERE id = ?";
$fStmt = $conn->prepare($fSql);
$fStmt->bind_param('i', $courseId);
$fStmt->execute();
$fResult = $fStmt->get_result();
$courseData = $fResult->fetch_assoc();
$fStmt->close();

if (!$courseData) {
    http_response_code(404);
    echo json_encode(['success' => false, 'message' => 'Course not found']);
    exit();
}

$facultyCode = $courseData['faculty_code'];
$session = $courseData['session'];
$studentTable = $facultyMap[$facultyCode]['table'] ?? null;

if (!$studentTable) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Invalid faculty configuration']);
    exit();
}

$emailPattern = 'ug%';
if (preg_match('/^20(\d{2})-/', $session, $matches)) {
    $batch = $matches[1];
    $emailPattern = 'ug' . $batch . '%';
}

// 2. Count total assignments for this course
$tsSql = "SELECT COUNT(*) as total FROM Assignment WHERE course_id = ?";
$tsStmt = $conn->prepare($tsSql);
$tsStmt->bind_param('i', $courseId);
$tsStmt->execute();
$tsRes = $tsStmt->get_result();
$totalAssignments = (int)($tsRes->fetch_assoc()['total'] ?? 0);
$tsStmt->close();

// 3. Fetch students and submission stats
$sql = "SELECT 
            s.name, 
            s.email, 
            (SELECT COUNT(*) FROM AssignmentSubmission asub JOIN Assignment a ON asub.assignment_id = a.id WHERE asub.student_email = s.email AND a.course_id = ? AND asub.is_turned_in = 1) as total_submitted
        FROM $studentTable s
        WHERE s.email LIKE ?
        ORDER BY s.name ASC";

$stmt = $conn->prepare($sql);
$stmt->bind_param('is', $courseId, $emailPattern);
$stmt->execute();
$result = $stmt->get_result();

$overview = [];
while ($row = $result->fetch_assoc()) {
    $totalSubmitted = (int)($row['total_submitted'] ?? 0);
    $totalMissed = max(0, $totalAssignments - $totalSubmitted);
    $percentage = $totalAssignments > 0 ? round(($totalSubmitted / $totalAssignments) * 100) : 0;

    $overview[] = [
        'name' => $row['name'],
        'email' => $row['email'],
        'total_submitted' => $totalSubmitted,
        'total_missed' => $totalMissed,
        'score_percentage' => $percentage
    ];
}

echo json_encode([
    'success' => true,
    'total_assignments' => $totalAssignments,
    'overview' => $overview
]);

$stmt->close();
$conn->close();
?>
