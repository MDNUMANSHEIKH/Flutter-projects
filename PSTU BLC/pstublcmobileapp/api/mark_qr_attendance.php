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
require_once 'logger.php';

$data = json_decode(file_get_contents("php://input"), true);

$session_id = isset($data['session_id']) ? intval($data['session_id']) : 0;
$email = trim(strtolower($data['email'] ?? ''));
$qr_code = trim($data['qr_code'] ?? '');

if (!$session_id || empty($email) || empty($qr_code)) {
    echo json_encode(['success' => false, 'message' => 'Missing session_id, email, or qr_code']);
    exit();
}

// 1. Fetch Session details
$stmt = $conn->prepare("SELECT id, course_id, session_date, session_end, is_private, is_dynamic_qr, qr_interval, qr_code_hex FROM attendance_sessions WHERE id = ?");
$stmt->bind_param("i", $session_id);
$stmt->execute();
$session = $stmt->get_result()->fetch_assoc();
$stmt->close();

if (!$session) {
    echo json_encode(['success' => false, 'message' => 'Attendance session not found']);
    exit();
}

if (intval($session['is_private']) === 1) {
    echo json_encode(['success' => false, 'message' => 'Attendance session is private']);
    exit();
}

$now = new DateTime();
$st = new DateTime($session['session_date']);
$en = new DateTime($session['session_end']);

if ($now < $st || $now > $en) {
    echo json_encode(['success' => false, 'message' => 'Attendance session is not currently active']);
    exit();
}

$course_id = intval($session['course_id']);

// 2. Verify enrollment
$eStmt = $conn->prepare("SELECT id, is_blocked FROM enrollments WHERE student_email = ? AND course_id = ?");
$eStmt->bind_param("si", $email, $course_id);
$eStmt->execute();
$enrollment = $eStmt->get_result()->fetch_assoc();
$eStmt->close();

if (!$enrollment) {
    echo json_encode(['success' => false, 'message' => 'You are not enrolled in this course']);
    exit();
}

if (intval($enrollment['is_blocked']) === 1) {
    echo json_encode(['success' => false, 'message' => 'Your enrollment is blocked for this course']);
    exit();
}

// 3. Check if already marked
$cStmt = $conn->prepare("SELECT id FROM attendance_records WHERE session_id = ? AND student_email = ?");
$cStmt->bind_param("is", $session_id, $email);
$cStmt->execute();
$existing = $cStmt->get_result()->fetch_assoc();
$cStmt->close();

if ($existing) {
    echo json_encode(['success' => false, 'message' => 'Attendance already marked for this session']);
    exit();
}

// 4. Verify QR code payload
$is_dynamic_qr = intval($session['is_dynamic_qr']);
if ($is_dynamic_qr === 1 || !empty($session['qr_code_hex'])) {
    $qrParts = explode(':', $qr_code);
    if (count($qrParts) < 2) {
        echo json_encode(['success' => false, 'message' => 'Invalid QR Code format']);
        exit();
    }

    $scannedHex = $qrParts[0];
    $scannedSlot = intval($qrParts[1]);

    $expectedHex = $session['qr_code_hex'] ?? '';
    if (empty($expectedHex)) {
        $expectedHex = 'a1b2c3d4e5f678901234567890abcdef1234567890' . str_pad($session_id, 8, '0', STR_PAD_LEFT);
    }

    if ($scannedHex !== $expectedHex) {
        echo json_encode(['success' => false, 'message' => 'Invalid QR Code. This QR does not belong to this attendance card!']);
        exit();
    }

    $interval = intval($session['qr_interval'] ?? 3);
    if ($interval < 1) $interval = 1;
    if ($interval > 20) $interval = 20;

    $currentSlot = floor(time() / $interval);
    
    // Allow current slot or previous 2 slots (up to ~6-9 sec for scan + network latency)
    $slotDiff = abs($currentSlot - $scannedSlot);
    if ($slotDiff > 2) {
        echo json_encode(['success' => false, 'message' => 'QR Code expired! Please scan the current live QR code on the teacher screen.']);
        exit();
    }
}

// 5. Insert attendance record
$iStmt = $conn->prepare("INSERT INTO attendance_records (session_id, student_email, marked_at) VALUES (?, ?, NOW())");
$iStmt->bind_param("is", $session_id, $email);

if ($iStmt->execute()) {
    logActivity($conn, $email, 'student', 'mark_qr_attendance', "Session ID: $session_id");
    echo json_encode(['success' => true, 'message' => 'Attendance marked successfully via QR scan!']);
} else {
    echo json_encode(['success' => false, 'message' => 'Database error: ' . $iStmt->error]);
}

$iStmt->close();
$conn->close();
?>
