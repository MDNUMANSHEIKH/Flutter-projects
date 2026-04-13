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

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Method not allowed']);
    exit();
}

$email = trim(strtolower($_POST['email'] ?? ''));

if (isset($_POST['current_password']) && isset($_POST['new_password'])) {
    $currentPassword = $_POST['current_password'];
    $newPassword = $_POST['new_password'];

    if (empty($email) || empty($currentPassword) || empty($newPassword)) {
        http_response_code(400);
        logActivity($conn, $email, 'teacher', 'password_change_failed', 'Missing required fields');
        echo json_encode(['success' => false, 'message' => 'Missing required fields']);
        exit();
    }

    $stmt = $conn->prepare("SELECT password_hash FROM teachers WHERE LOWER(email) = ?");
    if (!$stmt) {
        http_response_code(500);
        logActivity($conn, $email, 'teacher', 'password_change_failed', 'Database error: ' . $conn->error);
        echo json_encode(['success' => false, 'message' => 'Database error: ' . $conn->error]);
        exit();
    }
    $stmt->bind_param('s', $email);
    $stmt->execute();
    $result = $stmt->get_result();

    if ($result->num_rows === 0) {
        http_response_code(404);
        logActivity($conn, $email, 'teacher', 'password_change_failed', 'User not found');
        echo json_encode(['success' => false, 'message' => 'User not found']);
        exit();
    }

    $user = $result->fetch_assoc();
    $storedEncrypted = $user['password_hash'];
    $decryptedStored = decryptPassword($storedEncrypted);

    if ($currentPassword !== $decryptedStored) {
        http_response_code(401);
        logActivity($conn, $email, 'teacher', 'password_change_failed', 'Incorrect current password');
        echo json_encode(['success' => false, 'message' => 'Please enter the correct password']);
        exit();
    }

    $newEncrypted = encryptPassword($newPassword);
    $updateStmt = $conn->prepare("UPDATE teachers SET password_hash = ? WHERE LOWER(email) = ?");
    
    if (!$updateStmt) {
        http_response_code(500);
        logActivity($conn, $email, 'teacher', 'password_change_failed', 'Database update error: ' . $conn->error);
        echo json_encode(['success' => false, 'message' => 'Database update error: ' . $conn->error]);
        exit();
    }
    
    $updateStmt->bind_param('ss', $newEncrypted, $email);
    
    if ($updateStmt->execute()) {
        logActivity($conn, $email, 'teacher', 'password_change');
        echo json_encode(['success' => true, 'message' => 'Password changed successfully']);
    } else {
        http_response_code(500);
        logActivity($conn, $email, 'teacher', 'password_change_failed', 'Update failed: ' . $updateStmt->error);
        echo json_encode(['success' => false, 'message' => 'Update failed: ' . $updateStmt->error]);
    }
    
    $stmt->close();
    $updateStmt->close();
    $conn->close();
    exit();
}

$field = trim($_POST['field'] ?? '');
$value = trim($_POST['value'] ?? '');

$allowedFields = ['name', 'email', 'phone'];
if (!in_array($field, $allowedFields)) {
    http_response_code(400);
    logActivity($conn, $email, 'teacher', 'profile_update_failed', 'Invalid field');
    echo json_encode(['success' => false, 'message' => 'Invalid field']);
    exit();
}

if (empty($email) || empty($field) || empty($value)) {
    http_response_code(400);
    logActivity($conn, $email, 'teacher', 'profile_update_failed', 'Missing parameters');
    echo json_encode(['success' => false, 'message' => 'Missing parameters']);
    exit();
}

$conn->begin_transaction();

try {
    $infoStmt = $conn->prepare("SELECT id, hex_code_id FROM teachers WHERE LOWER(email) = ?");
    if (!$infoStmt) {
        throw new Exception('Database prepare error (info): ' . $conn->error);
    }
    $infoStmt->bind_param('s', $email);
    $infoStmt->execute();
    $infoResult = $infoStmt->get_result();
    if ($infoResult->num_rows === 0) {
        throw new Exception('User not found');
    }
    $teacherInfo = $infoResult->fetch_assoc();
    $teacherId = $teacherInfo['id'];
    $hexCodeId = $teacherInfo['hex_code_id'];
    $infoStmt->close();

    $stmt = $conn->prepare("UPDATE teachers SET $field = ? WHERE id = ?");
    if (!$stmt) {
        throw new Exception('Database prepare error (update): ' . $conn->error);
    }
    $stmt->bind_param('si', $value, $teacherId);
    if (!$stmt->execute()) {
        throw new Exception('Failed to update teacher profile: ' . $stmt->error);
    }
    $stmt->close();

    if ($field === 'email') {
        $syncStmt = $conn->prepare("UPDATE teacher_hex_codes SET used_by = ? WHERE id = ?");
        if (!$syncStmt) {
            throw new Exception('Database prepare error (sync): ' . $conn->error);
        }
        $syncStmt->bind_param('si', $value, $hexCodeId);
        $syncStmt->execute();
        $syncStmt->close();
    }

    $conn->commit();
    logActivity($conn, $field === 'email' ? $value : $email, 'teacher', 'profile_update', "Updated field: $field");
    echo json_encode(['success' => true, 'message' => 'Profile updated successfully']);

} catch (Exception $e) {
    if ($conn) $conn->rollback();
    logActivity($conn, $email, 'teacher', 'profile_update_failed', $e->getMessage());
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Update failed: ' . $e->getMessage()]);
}

if ($conn) $conn->close();
?>
