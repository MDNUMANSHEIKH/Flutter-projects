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
$table = getStudentTable($email);

if (empty($email) || !$table) {
    http_response_code(400);
    logActivity($conn, $email, 'student', 'profile_update_failed', 'Invalid email or faculty could not be determined');
    echo json_encode(['success' => false, 'message' => 'Invalid email or faculty could not be determined']);
    exit();
}

if (isset($_POST['current_password']) && isset($_POST['new_password'])) {
    $currentPassword = $_POST['current_password'];
    $newPassword = $_POST['new_password'];
    $stmt = $conn->prepare("SELECT password_hash FROM $table WHERE email = ?");
    $stmt->bind_param('s', $email);
    $stmt->execute();
    $result = $stmt->get_result();
    
    if ($result->num_rows === 0) {
        http_response_code(404);
        logActivity($conn, $email, 'student', 'password_change_failed', 'User not found');
        echo json_encode(['success' => false, 'message' => 'User not found']);
        exit();
    }

    $user = $result->fetch_assoc();
    $storedEncrypted = $user['password_hash'];
    $decryptedStored = decryptPassword($storedEncrypted);

    if ($currentPassword !== $decryptedStored) {
        http_response_code(401);
        logActivity($conn, $email, 'student', 'password_change_failed', 'Incorrect current password');
        echo json_encode(['success' => false, 'message' => 'Please enter the correct password']);
        exit();
    }

    $newEncrypted = encryptPassword($newPassword);
    $updateStmt = $conn->prepare("UPDATE $table SET password_hash = ? WHERE email = ?");
    
    if (!$updateStmt) {
        http_response_code(500);
        logActivity($conn, $email, 'student', 'password_change_failed', 'Database update error');
        echo json_encode(['success' => false, 'message' => 'Database update error']);
        exit();
    }
    
    $updateStmt->bind_param('ss', $newEncrypted, $email);
    
    if ($updateStmt->execute()) {
        logActivity($conn, $email, 'student', 'password_change');
        echo json_encode(['success' => true, 'message' => 'Password changed successfully']);
    } else {
        http_response_code(500);
        logActivity($conn, $email, 'student', 'password_change_failed', 'Update failed: ' . $updateStmt->error);
        echo json_encode(['success' => false, 'message' => 'Update failed: ' . $updateStmt->error]);
    }
    exit();
}

$field = $_POST['field'] ?? '';
$value = trim($_POST['value'] ?? '');

$allowedFields = ['name', 'phone', 'email'];

if (!in_array($field, $allowedFields)) {
    http_response_code(400);
    logActivity($conn, $email, 'student', 'profile_update_failed', 'Invalid field');
    echo json_encode(['success' => false, 'message' => 'Invalid field']);
    exit();
}

if (empty($value)) {
    http_response_code(400);
    logActivity($conn, $email, 'student', 'profile_update_failed', 'Value cannot be empty');
    echo json_encode(['success' => false, 'message' => 'Value cannot be empty']);
    exit();
}

$sql = "UPDATE $table SET $field = ? WHERE email = ?";
$stmt = $conn->prepare($sql);

if (!$stmt) {
    http_response_code(500);
    logActivity($conn, $email, 'student', 'profile_update_failed', 'Database error: ' . $conn->error);
    echo json_encode(['success' => false, 'message' => 'Database error: ' . $conn->error]);
    exit();
}

$stmt->bind_param('ss', $value, $email);

if ($stmt->execute()) {
    logActivity($conn, $field === 'email' ? $value : $email, 'student', 'profile_update', "Updated field: $field");
    echo json_encode(['success' => true, 'message' => 'Profile updated successfully']);
} else {
    http_response_code(500);
    logActivity($conn, $email, 'student', 'profile_update_failed', 'Update failed: ' . $stmt->error);
    echo json_encode(['success' => false, 'message' => 'Update failed: ' . $stmt->error]);
}

$stmt->close();
$conn->close();
?>
