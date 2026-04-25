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

function ensureAssignmentCommentReplyColumns(mysqli $conn): bool {
    $replyIdCheck = $conn->query("SHOW COLUMNS FROM assignment_comment_messages LIKE 'reply_to_message_id'");
    if ($replyIdCheck && $replyIdCheck->num_rows === 0) {
        if (!$conn->query("ALTER TABLE assignment_comment_messages ADD COLUMN reply_to_message_id INT NULL AFTER message")) {
            return false;
        }
    }

    $replySenderCheck = $conn->query("SHOW COLUMNS FROM assignment_comment_messages LIKE 'reply_to_sender_name'");
    if ($replySenderCheck && $replySenderCheck->num_rows === 0) {
        if (!$conn->query("ALTER TABLE assignment_comment_messages ADD COLUMN reply_to_sender_name VARCHAR(120) NULL AFTER reply_to_message_id")) {
            return false;
        }
    }

    $replyMessageCheck = $conn->query("SHOW COLUMNS FROM assignment_comment_messages LIKE 'reply_to_message'");
    if ($replyMessageCheck && $replyMessageCheck->num_rows === 0) {
        if (!$conn->query("ALTER TABLE assignment_comment_messages ADD COLUMN reply_to_message TEXT NULL AFTER reply_to_sender_name")) {
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
$senderName = trim((string)($data['sender_name'] ?? ''));
$message = trim((string)($data['message'] ?? ''));
$targetAudience = trim(strtolower((string)($data['target_audience'] ?? 'everyone')));
$targetStudentEmail = trim(strtolower((string)($data['target_student_email'] ?? '')));
$replyToMessageId = (int)($data['reply_to_message_id'] ?? 0);
$replyToSenderName = trim((string)($data['reply_to_sender_name'] ?? ''));
$replyToMessage = trim((string)($data['reply_to_message'] ?? ''));

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

if ($message === '') {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Message is required']);
    exit();
}

if ($replyToMessageId <= 0) {
    $replyToMessageId = null;
    $replyToSenderName = null;
    $replyToMessage = null;
}

if (!ensureAssignmentCommentTargetColumns($conn) || !ensureAssignmentCommentReplyColumns($conn)) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Failed to prepare assignment comment table']);
    exit();
}

$accessStmt = $conn->prepare('SELECT LOWER(t.email) AS teacher_email FROM `Assignment` a JOIN courses c ON a.course_id = c.id JOIN teachers t ON c.teacher_id = t.id WHERE a.id = ? AND a.course_id = ? LIMIT 1');
if (!$accessStmt) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Prepare failed: ' . $conn->error]);
    exit();
}
$accessStmt->bind_param('ii', $assignmentId, $courseId);
$accessStmt->execute();
$accessResult = $accessStmt->get_result();
if (!$accessResult || $accessResult->num_rows === 0) {
    $accessStmt->close();
    http_response_code(404);
    echo json_encode(['success' => false, 'message' => 'Assignment not found']);
    exit();
}
$courseRow = $accessResult->fetch_assoc();
$teacherEmail = trim(strtolower((string)($courseRow['teacher_email'] ?? '')));
$accessStmt->close();

if ($teacherEmail === '') {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Teacher account not found for this course']);
    exit();
}

if ($role === 'teacher') {
    if ($email !== $teacherEmail) {
        http_response_code(403);
        echo json_encode(['success' => false, 'message' => 'Access denied for this assignment']);
        exit();
    }
} else {
    $studentAccessStmt = $conn->prepare('SELECT 1 FROM enrollments WHERE course_id = ? AND LOWER(student_email) = ? AND (is_blocked IS NULL OR is_blocked = 0) LIMIT 1');
    if (!$studentAccessStmt) {
        http_response_code(500);
        echo json_encode(['success' => false, 'message' => 'Prepare failed: ' . $conn->error]);
        exit();
    }
    $studentAccessStmt->bind_param('is', $courseId, $email);
    $studentAccessStmt->execute();
    $studentAccessResult = $studentAccessStmt->get_result();
    if (!$studentAccessResult || $studentAccessResult->num_rows === 0) {
        $studentAccessStmt->close();
        http_response_code(403);
        echo json_encode(['success' => false, 'message' => 'Access denied for this assignment']);
        exit();
    }
    $studentAccessStmt->close();
}

if (!in_array($targetAudience, ['everyone', 'teacher', 'student'], true)) {
    $targetAudience = 'everyone';
}

if ($targetAudience === 'student') {
    if ($targetStudentEmail === '') {
        http_response_code(400);
        echo json_encode(['success' => false, 'message' => 'Target student is required']);
        exit();
    }

    $targetCheckStmt = $conn->prepare('SELECT 1 FROM enrollments WHERE course_id = ? AND LOWER(student_email) = ? AND (is_blocked IS NULL OR is_blocked = 0) LIMIT 1');
    if (!$targetCheckStmt) {
        http_response_code(500);
        echo json_encode(['success' => false, 'message' => 'Prepare failed: ' . $conn->error]);
        exit();
    }
    $targetCheckStmt->bind_param('is', $courseId, $targetStudentEmail);
    $targetCheckStmt->execute();
    $targetCheckResult = $targetCheckStmt->get_result();
    if (!$targetCheckResult || $targetCheckResult->num_rows === 0) {
        $targetCheckStmt->close();
        http_response_code(400);
        echo json_encode(['success' => false, 'message' => 'Selected student is not enrolled in this course']);
        exit();
    }
    $targetCheckStmt->close();
} else {
    $targetStudentEmail = '';
}

if ($senderName === '') {
    $senderName = $role === 'teacher' ? 'Teacher' : 'Student';
}

$createdAt = date('Y-m-d H:i:s');
$stmt = $conn->prepare('INSERT INTO assignment_comment_messages (assignment_id, course_id, sender_email, sender_name, sender_role, target_audience, target_student_email, message, reply_to_message_id, reply_to_sender_name, reply_to_message, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)');
if (!$stmt) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Prepare failed: ' . $conn->error]);
    exit();
}

$stmt->bind_param('iissssssisss', $assignmentId, $courseId, $email, $senderName, $role, $targetAudience, $targetStudentEmail, $message, $replyToMessageId, $replyToSenderName, $replyToMessage, $createdAt);

if ($stmt->execute()) {
    echo json_encode([
        'success' => true,
        'message' => 'Assignment comment sent successfully',
        'message_id' => $stmt->insert_id,
    ]);
} else {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Failed to send assignment comment: ' . $stmt->error]);
}

$stmt->close();
$conn->close();
?>
