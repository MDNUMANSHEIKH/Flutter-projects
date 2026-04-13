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

// 1. Get course details to find the correct student table and batch
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

// Determine batch email pattern (e.g., ug22%)
$emailPattern = 'ug%';
if (preg_match('/^20(\d{2})-/', $session, $matches)) {
    $batch = $matches[1];
    $emailPattern = 'ug' . $batch . '%';
}

// 2. Count total past sessions for this course
$tsSql = "SELECT COUNT(*) as total FROM attendance_sessions WHERE course_id = ?";
$tsStmt = $conn->prepare($tsSql);
$tsStmt->bind_param('i', $courseId);
$tsStmt->execute();
$tsRes = $tsStmt->get_result();
$totalSessionsResult = (int)($tsRes->fetch_assoc()['total'] ?? 0);
$totalSessions = max(1, $totalSessionsResult);
$tsStmt->close();

// 3. Fetch all students in course batch, attendance counts, and blocked status
$sql = "SELECT 
            s.name, 
            s.email, 
            (SELECT COUNT(*) FROM attendance_records ar JOIN attendance_sessions as_s ON ar.session_id = as_s.id WHERE ar.student_email = s.email AND as_s.course_id = ?) as total_present,
            (SELECT is_blocked FROM enrollments e WHERE e.student_email = s.email AND e.course_id = ?) as is_blocked
        FROM $studentTable s
        WHERE s.email LIKE ?
        ORDER BY s.name ASC";

$stmt = $conn->prepare($sql);
if (!$stmt) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Database error: ' . $conn->error]);
    exit();
}

$stmt->bind_param('iis', $courseId, $courseId, $emailPattern);
$stmt->execute();
$result = $stmt->get_result();

$overview = [];
while ($row = $result->fetch_assoc()) {
    $totalPresent = (int)($row['total_present'] ?? 0);
    $totalAbsent = max(0, $totalSessionsResult - $totalPresent);
    $percentage = round(($totalPresent / $totalSessions) * 100);

    if ($totalSessionsResult == 0) $percentage = 0;

    $overview[] = [
        'name' => $row['name'],
        'email' => $row['email'],
        'total_present' => $totalPresent,
        'total_absent' => $totalAbsent,
        'score_percentage' => $percentage,
        'is_blocked' => (int)($row['is_blocked'] ?? 0)
    ];
}

echo json_encode([
    'success' => true,
    'total_sessions' => $totalSessionsResult,
    'overview' => $overview
]);

$stmt->close();
$conn->close();
?>
