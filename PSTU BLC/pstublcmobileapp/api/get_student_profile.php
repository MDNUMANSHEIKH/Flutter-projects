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

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Method not allowed']);
    exit();
}

$email = trim(strtolower($_POST['email'] ?? ''));

if (empty($email)) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Email is required']);
    exit();
}

$table = getStudentTable($email);

if (!$table) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Could not determine faculty from email']);
    exit();
}

$stmt = $conn->prepare("SELECT id, name, email, phone, password_hash FROM $table WHERE email = ?");
if (!$stmt) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Database error']);
    exit();
}

$stmt->bind_param('s', $email);
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows > 0) {
    $user = $result->fetch_assoc();
    
    $decryptedPassword = decryptPassword($user['password_hash']);
    
    echo json_encode([
        'success' => true,
        'data' => [
            'name' => $user['name'],
            'email' => $user['email'],
            'phone' => $user['phone'],
            'password' => $decryptedPassword 
        ]
    ]);
} else {
    http_response_code(404);
    echo json_encode(['success' => false, 'message' => 'User not found']);
}

$stmt->close();
$conn->close();
?>
