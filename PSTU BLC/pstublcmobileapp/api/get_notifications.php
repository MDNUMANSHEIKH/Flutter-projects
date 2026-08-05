<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
header('Pragma: no-cache');
header('Expires: 0');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once 'db_config.php';
require_once 'attendance_notify_helper.php';

$email = trim(strtolower($_GET['email'] ?? ''));

if (empty($email)) {
    echo json_encode(['success' => false, 'message' => 'Email is required']);
    exit();
}

// Auto-check and notify any scheduled sessions that just became active
checkAndNotifyActiveSessions($conn);

// Fetch notifications
$sql = "SELECT id, course_id, title, message, type, is_read, created_at 
        FROM notifications 
        WHERE student_email = ? 
        ORDER BY created_at DESC 
        LIMIT 50";

$stmt = $conn->prepare($sql);
$stmt->bind_param("s", $email);
$stmt->execute();
$result = $stmt->get_result();

$notifications = [];
$unread_count = 0;

while ($row = $result->fetch_assoc()) {
    if ($row['is_read'] == 0) {
        $unread_count++;
    }
    $notifications[] = [
        'id' => (int)$row['id'],
        'course_id' => (int)$row['course_id'],
        'title' => $row['title'],
        'message' => $row['message'],
        'type' => $row['type'],
        'is_read' => (int)$row['is_read'] == 1,
        'created_at' => $row['created_at']
    ];
}

echo json_encode([
    'success' => true,
    'notifications' => $notifications,
    'unread_count' => $unread_count
]);

$stmt->close();
$conn->close();
?>
