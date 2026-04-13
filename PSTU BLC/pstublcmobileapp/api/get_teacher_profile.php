<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once 'db_config.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST' && $_SERVER['REQUEST_METHOD'] !== 'GET') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Method not allowed']);
    exit();
}

$email = trim(strtolower($_POST['email'] ?? $_GET['email'] ?? ''));

if (empty($email)) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Email is required']);
    exit();
}

$query = "SELECT name, email, phone, password_hash FROM teachers WHERE LOWER(email) = ?";
$stmt = $conn->prepare($query);

if (!$stmt) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Database error: ' . $conn->error]);
    exit();
}

$stmt->bind_param('s', $email);
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows > 0) {
    $teacher = $result->fetch_assoc();
    $decryptedPassword = decryptPassword($teacher['password_hash']);
    
    echo json_encode([
        'success' => true,
        'data' => [
            'name' => $teacher['name'] ?? 'Not provided',
            'email' => $teacher['email'] ?? 'Not provided',
            'phone' => $teacher['phone'] ?? 'Not provided',
            'password' => $decryptedPassword ?: 'Not provided'
        ]
    ]);
} else {
    http_response_code(404);
    echo json_encode(['success' => false, 'message' => 'Teacher not found']);
}

$stmt->close();
$conn->close();
?>
