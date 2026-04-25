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
require_once 'logger.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Method not allowed']);
    exit();
}

$email = trim(strtolower($_POST['email'] ?? ''));
$password = $_POST['password'] ?? '';

if (empty($email) || empty($password)) {
    http_response_code(400);
    logActivity($conn, $email, 'student', 'account_delete_failed', 'Missing required fields');
    echo json_encode(['success' => false, 'message' => 'Missing required fields']);
    exit();
}

$table = getStudentTable($email);

if (!$table) {
    http_response_code(400);
    logActivity($conn, $email, 'student', 'account_delete_failed', 'Could not determine student record');
    echo json_encode(['success' => false, 'message' => 'Could not determine student record']);
    exit();
}


$stmt = $conn->prepare("SELECT password_hash FROM $table WHERE email = ?");
if (!$stmt) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Database error']);
    exit();
}

$stmt->bind_param('s', $email);
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows === 0) {
    http_response_code(404);
    logActivity($conn, $email, 'student', 'account_delete_failed', 'User not found');
    echo json_encode(['success' => false, 'message' => 'User not found']);
    exit();
}

$user = $result->fetch_assoc();
$storedEncrypted = $user['password_hash'];
$decryptedStored = decryptPassword($storedEncrypted);

$verifyOnly = isset($_POST['verify_only']) && ($_POST['verify_only'] === 'true' || $_POST['verify_only'] === '1');

if ($password !== $decryptedStored) {
    http_response_code(401);
    logActivity($conn, $email, 'student', 'account_delete_failed', 'Incorrect password');
    echo json_encode(['success' => false, 'message' => 'Please enter the correct password']);
    exit();
}

if ($verifyOnly) {
    echo json_encode(['success' => true, 'message' => 'Password verified']);
    exit();
}


$deleteStmt = $conn->prepare("DELETE FROM $table WHERE email = ?");
if (!$deleteStmt) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Database error during deletion']);
    exit();
}

$deleteStmt->bind_param('s', $email);

if ($deleteStmt->execute()) {
    logActivity($conn, $email, 'student', 'account_delete');
    echo json_encode(['success' => true, 'message' => 'Account deleted successfully']);
} else {
    http_response_code(500);
    logActivity($conn, $email, 'student', 'account_delete_failed', 'Failed to delete account');
    echo json_encode(['success' => false, 'message' => 'Failed to delete account']);
}

$stmt->close();
$deleteStmt->close();
$conn->close();
?>
