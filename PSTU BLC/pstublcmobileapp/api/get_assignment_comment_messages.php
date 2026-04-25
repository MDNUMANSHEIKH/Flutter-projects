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

set_exception_handler(function (Throwable $e) {
    if (!headers_sent()) {
        http_response_code(500);
        header('Content-Type: application/json');
    }
    echo json_encode([
        'success' => false,
        'message' => 'Server error while loading assignment comments',
    ]);
    exit();
});

date_default_timezone_set('Asia/Dhaka');

if ($conn->connect_error) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Database connection failed']);
    exit();
}

function ensureAssignmentCommentTargetColumns(mysqli $conn): bool {
    $targetAudienceCheck = $conn->query("SHOW COLUMNS FROM assignment_comment_messages LIKE 'target_audience'");
    if ($targetAudienceCheck && $targetAudienceCheck->num_rows === 0) {
        if (!$conn->query("ALTER TABLE assignment_comment_messages ADD COLUMN target_audience VARCHAR(20) NOT NULL DEFAULT 'everyone' AFTER sender_role")) {
            return false;
        }
    }

    $targetStudentEmailCheck = $conn->query("SHOW COLUMNS FROM assignment_comment_messages LIKE 'target_student_email'");
    if ($targetStudentEmailCheck && $targetStudentEmailCheck->num_rows === 0) {
        if (!$conn->query("ALTER TABLE assignment_comment_messages ADD COLUMN target_student_email VARCHAR(100) NULL AFTER target_audience")) {
            return false;
        }
    }

    return true;
}

$data = json_decode(file_get_contents('php://input'), true);
$assignmentId = (int)($data['assignment_id'] ?? 0);
$courseId = (int)($data['course_id'] ?? 0);
$email = trim(strtolower((string)($data['email'] ?? '')));
$role = trim(strtolower((string)($data['role'] ?? '')));

if ($assignmentId <= 0 || $courseId <= 0) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Assignment ID and Course ID are required']);
    exit();
}

if ($email === '' || !in_array($role, ['teacher', 'student'], true)) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Valid email and role are required']);
    exit();
}

if (!ensureAssignmentCommentTargetColumns($conn)) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Failed to prepare assignment comment table']);
    exit();
}

if ($role === 'teacher') {
    $accessStmt = $conn->prepare('SELECT LOWER(t.email) AS teacher_email FROM `Assignment` a JOIN courses c ON a.course_id = c.id JOIN teachers t ON c.teacher_id = t.id WHERE a.id = ? AND a.course_id = ? LIMIT 1');
} else {
    $accessStmt = $conn->prepare('SELECT LOWER(t.email) AS teacher_email FROM `Assignment` a JOIN courses c ON a.course_id = c.id JOIN teachers t ON c.teacher_id = t.id JOIN enrollments e ON a.course_id = e.course_id WHERE a.id = ? AND a.course_id = ? AND LOWER(e.student_email) = ? AND (e.is_blocked IS NULL OR e.is_blocked = 0) LIMIT 1');
}

if (!$accessStmt) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Prepare failed: ' . $conn->error]);
    exit();
}

if ($role === 'teacher') {
    $accessStmt->bind_param('ii', $assignmentId, $courseId);
} else {
    $accessStmt->bind_param('iis', $assignmentId, $courseId, $email);
}
$accessStmt->execute();
$accessResult = $accessStmt->get_result();
if (!$accessResult || $accessResult->num_rows === 0) {
    $accessStmt->close();
    http_response_code(403);
    echo json_encode(['success' => false, 'message' => 'Access denied for this assignment']);
    exit();
}
$accessRow = $accessResult->fetch_assoc();
$teacherEmail = trim(strtolower((string)($accessRow['teacher_email'] ?? '')));
$accessStmt->close();

if ($teacherEmail === '') {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Teacher account not found for this course']);
    exit();
}

if ($role === 'teacher' && $email !== $teacherEmail) {
    http_response_code(403);
    echo json_encode(['success' => false, 'message' => 'Access denied for this assignment']);
    exit();
}

$sql = "SELECT 
                acm.id, 
                acm.assignment_id, 
                acm.course_id, 
                acm.sender_email, 
                acm.sender_name,
                acm.sender_role, 
                acm.target_audience, 
                acm.target_student_email, 
                acm.message, 
                acm.created_at,
                CASE 
                    WHEN acm.sender_name IS NOT NULL AND acm.sender_name != '' THEN acm.sender_name
                    WHEN acm.sender_role = 'teacher' THEN COALESCE(t.name, '')
                    ELSE ''
                END as final_name
                FROM assignment_comment_messages acm
                LEFT JOIN teachers t ON acm.sender_role = 'teacher' AND LOWER(acm.sender_email) = LOWER(t.email)
                WHERE acm.assignment_id = ? AND acm.course_id = ?";
if ($role === 'teacher') {
    $sql .= " AND (LOWER(acm.sender_email) = ? OR acm.target_audience = 'everyone' OR acm.target_audience = 'teacher')";
} else {
    $sql .= " AND (LOWER(acm.sender_email) = ? OR acm.target_audience = 'everyone' OR (acm.target_audience = 'student' AND LOWER(acm.target_student_email) = ?))";
}
$sql .= " ORDER BY acm.created_at ASC, acm.id ASC LIMIT 300";

$stmt = $conn->prepare($sql);
if (!$stmt) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Prepare failed: ' . $conn->error]);
    exit();
}

if ($role === 'teacher') {
    $stmt->bind_param('iis', $assignmentId, $courseId, $email);
} else {
    $stmt->bind_param('iiss', $assignmentId, $courseId, $email, $email);
}

$stmt->execute();
$result = $stmt->get_result();

$messages = [];
while ($row = $result->fetch_assoc()) {
    $messages[] = [
        'id' => (int)$row['id'],
        'assignment_id' => (int)$row['assignment_id'],
        'course_id' => (int)$row['course_id'],
        'sender_email' => $row['sender_email'],
        'sender_name' => $row['final_name'] ?? $row['sender_name'] ?? '',
        'sender_role' => $row['sender_role'],
        'target_audience' => $row['target_audience'] ?? 'everyone',
        'target_student_email' => $row['target_student_email'] ?? null,
        'message' => $row['message'],
        'created_at' => $row['created_at'],
    ];
}

echo json_encode(['success' => true, 'messages' => $messages]);

$stmt->close();
$conn->close();
?>
