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
if (!$data) {
    $data = $_POST;
}

$email = trim(strtolower($data['email'] ?? ''));
$role = trim($data['role'] ?? 'unknown');

if (empty($email)) {
    logActivity($conn, null, $role, 'signout_failed', 'Missing email in signout request');
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Email is required']);
    $conn->close();
    exit();
}

logActivity($conn, $email, $role, 'signout');

echo json_encode(['success' => true, 'message' => 'Signout logged successfully']);
$conn->close();
?>
