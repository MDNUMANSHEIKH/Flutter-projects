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

date_default_timezone_set('Asia/Dhaka');

if ($conn->connect_error) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Database connection failed']);
    exit();
}

function ensureDiscussionReplyColumns(mysqli $conn): bool {
    $replyIdCheck = $conn->query("SHOW COLUMNS FROM course_discussion_messages LIKE 'reply_to_message_id'");
    if ($replyIdCheck && $replyIdCheck->num_rows === 0) {
        if (!$conn->query("ALTER TABLE course_discussion_messages ADD COLUMN reply_to_message_id INT NULL AFTER message")) {
            return false;
        }
    }

    $replySenderCheck = $conn->query("SHOW COLUMNS FROM course_discussion_messages LIKE 'reply_to_sender_name'");
    if ($replySenderCheck && $replySenderCheck->num_rows === 0) {
        if (!$conn->query("ALTER TABLE course_discussion_messages ADD COLUMN reply_to_sender_name VARCHAR(120) NULL AFTER reply_to_message_id")) {
            return false;
        }
    }

    $replyMessageCheck = $conn->query("SHOW COLUMNS FROM course_discussion_messages LIKE 'reply_to_message'");
    if ($replyMessageCheck && $replyMessageCheck->num_rows === 0) {
        if (!$conn->query("ALTER TABLE course_discussion_messages ADD COLUMN reply_to_message TEXT NULL AFTER reply_to_sender_name")) {
            return false;
        }
    }

    return true;
}

function buildDiscussionCourseLabel(array $courseRow): string {
    $courseCode = trim((string)($courseRow['course_code'] ?? ''));
    $courseName = trim((string)($courseRow['course_name'] ?? ''));
    $parts = array_filter([$courseCode, $courseName], fn($v) => $v !== '');
    if (!empty($parts)) {
        return implode(' - ', $parts);
    }
    return 'Course #' . (int)($courseRow['id'] ?? 0);
}

function buildDiscussionSenderLabel(string $role, string $senderName, string $email): string {
    $role = strtolower(trim($role));
    $senderName = trim($senderName);
    $email = trim($email);

    if ($role === 'teacher') {
        return 'Teacher';
    }

    if ($senderName !== '' && $email !== '') {
        return $senderName . ' - ' . $email;
    }

    if ($senderName !== '') {
        return $senderName;
    }

    return $email !== '' ? $email : 'Student';
}

$data = json_decode(file_get_contents('php://input'), true);
$courseId = (int)($data['course_id'] ?? 0);
$email = trim(strtolower((string)($data['email'] ?? '')));
$role = trim(strtolower((string)($data['role'] ?? '')));
$senderName = trim((string)($data['sender_name'] ?? ''));
$message = trim((string)($data['message'] ?? ''));
$replyToMessageId = (int)($data['reply_to_message_id'] ?? 0);
$replyToSenderName = trim((string)($data['reply_to_sender_name'] ?? ''));
$replyToMessage = trim((string)($data['reply_to_message'] ?? ''));

if ($courseId <= 0) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Course ID is required']);
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

if (!ensureDiscussionReplyColumns($conn)) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Failed to prepare discussion table for replies']);
    exit();
}

if ($role === 'teacher') {
    $accessStmt = $conn->prepare('SELECT t.name FROM courses c JOIN teachers t ON c.teacher_id = t.id WHERE c.id = ? AND LOWER(t.email) = ? LIMIT 1');
} else {
    $studentTable = getStudentTable($email);
    if (!$studentTable) {
        http_response_code(400);
        echo json_encode(['success' => false, 'message' => 'Could not determine student table']);
        exit();
    }
    $accessStmt = $conn->prepare('SELECT s.name FROM enrollments e INNER JOIN ' . $studentTable . ' s ON LOWER(s.email) = LOWER(e.student_email) WHERE e.course_id = ? AND LOWER(e.student_email) = ? AND (e.is_blocked IS NULL OR e.is_blocked = 0) LIMIT 1');
}

if (!$accessStmt) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Prepare failed: ' . $conn->error]);
    exit();
}

$accessStmt->bind_param('is', $courseId, $email);
$accessStmt->execute();
$accessResult = $accessStmt->get_result();

if (!$accessResult || $accessResult->num_rows === 0) {
    $accessStmt->close();
    http_response_code(403);
    echo json_encode(['success' => false, 'message' => 'Access denied for this course']);
    exit();
}

$row = $accessResult->fetch_assoc();
$accessStmt->close();

if ($senderName === '') {
    $senderName = trim((string)($row['name'] ?? ''));
}

if ($senderName === '') {
    $senderName = $role === 'teacher' ? 'Teacher' : 'Student';
}

$createdAt = date('Y-m-d H:i:s');
$courseStmt = $conn->prepare('SELECT id, course_code, course_name FROM courses WHERE id = ? LIMIT 1');
$courseRow = ['id' => $courseId, 'course_code' => '', 'course_name' => ''];
if ($courseStmt) {
    $courseStmt->bind_param('i', $courseId);
    $courseStmt->execute();
    $courseResult = $courseStmt->get_result();
    if ($courseResult && ($row = $courseResult->fetch_assoc())) {
        $courseRow = $row;
    }
    $courseStmt->close();
}
$courseLabel = buildDiscussionCourseLabel($courseRow);
$senderLabel = buildDiscussionSenderLabel($role, $senderName, $email);
$notifTitle = 'New message in ' . $courseLabel . ' from ' . $senderLabel;
$notifMessage = $message;

$stmt = $conn->prepare('INSERT INTO course_discussion_messages (course_id, sender_email, sender_name, sender_role, message, reply_to_message_id, reply_to_sender_name, reply_to_message, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)');
if (!$stmt) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Prepare failed: ' . $conn->error]);
    exit();
}

$stmt->bind_param('issssisss', $courseId, $email, $senderName, $role, $message, $replyToMessageId, $replyToSenderName, $replyToMessage, $createdAt);

if ($stmt->execute()) {
    $dedupeStmt = $conn->prepare("DELETE FROM notifications WHERE course_id = ? AND type = 'discussion'");
    if ($dedupeStmt) {
        $dedupeStmt->bind_param('i', $courseId);
        $dedupeStmt->execute();
        $dedupeStmt->close();
    }

    $notifySql = "INSERT INTO notifications (student_email, course_id, title, message, type)
                  SELECT e.student_email, ?, ?, ?, 'discussion'
                  FROM enrollments e
                  WHERE e.course_id = ? AND e.is_blocked = 0";
    $notifyParams = [$courseId, $notifTitle, $notifMessage, $courseId];
    $notifyTypes = 'issi';
    if ($role === 'student') {
        $notifySql .= ' AND LOWER(e.student_email) <> ?';
        $notifyParams[] = $email;
        $notifyTypes .= 's';
    }
    $notifyStmt = $conn->prepare($notifySql);
    if ($notifyStmt) {
        $notifyStmt->bind_param($notifyTypes, ...$notifyParams);
        $notifyStmt->execute();
        $notifyStmt->close();
    }

    echo json_encode([
        'success' => true,
        'message' => 'Message sent successfully',
        'message_id' => $stmt->insert_id,
    ]);
} else {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Failed to send message: ' . $stmt->error]);
}

$stmt->close();
$conn->close();
?>