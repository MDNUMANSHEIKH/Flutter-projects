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

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Method not allowed']);
    exit();
}

$data = json_decode(file_get_contents("php://input"), true);
$email = trim(strtolower($data['email'] ?? ''));
$session_ids = $data['session_ids'] ?? [];

if (empty($email) || !is_array($session_ids) || empty($session_ids)) {
    echo json_encode(['success' => true, 'marked_sessions' => []]);
    exit();
}

$ids_str = implode(',', array_map('intval', $session_ids));
$sql = "SELECT session_id FROM attendance_records WHERE student_email = ? AND session_id IN ($ids_str)";
$stmt = $conn->prepare($sql);
$stmt->bind_param("s", $email);
$stmt->execute();
$result = $stmt->get_result();

$marked_sessions = [];
while ($row = $result->fetch_assoc()) {
    $marked_sessions[] = (int)$row['session_id'];
}

echo json_encode([
    'success' => true,
    'marked_sessions' => $marked_sessions
]);

$stmt->close();
$conn->close();
?>
