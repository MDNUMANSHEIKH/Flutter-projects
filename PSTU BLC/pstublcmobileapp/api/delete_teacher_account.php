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
$password = $_POST['password'] ?? '';

if (empty($email) || empty($password)) {
    http_response_code(400);
    logActivity($conn, $email, 'teacher', 'account_delete_failed', 'Missing required fields');
    echo json_encode(['success' => false, 'message' => 'Missing required fields']);
    exit();
}


$stmt = $conn->prepare("SELECT password_hash FROM teachers WHERE LOWER(email) = ?");
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
    logActivity($conn, $email, 'teacher', 'account_delete_failed', 'User not found');
    echo json_encode(['success' => false, 'message' => 'User not found']);
    exit();
}

$user = $result->fetch_assoc();
$storedEncrypted = $user['password_hash'];
$decryptedStored = decryptPassword($storedEncrypted);

if ($password !== $decryptedStored) {
    http_response_code(401);
    logActivity($conn, $email, 'teacher', 'account_delete_failed', 'Incorrect password');
    echo json_encode(['success' => false, 'message' => 'Please enter the correct password']);
    exit();
}



$conn->begin_transaction();

try {
    $infoStmt = $conn->prepare("SELECT id, hex_code_id FROM teachers WHERE LOWER(email) = ?");
    $infoStmt->bind_param('s', $email);
    $infoStmt->execute();
    $row = $infoStmt->get_result()->fetch_assoc();
    $teacherId = $row['id'];
    $hexCodeId = $row['hex_code_id'];
    $infoStmt->close();

    $deleteStmt = $conn->prepare("DELETE FROM teachers WHERE id = ?");
    $deleteStmt->bind_param('i', $teacherId);
    
    if (!$deleteStmt->execute()) {
        throw new Error('Failed to delete teacher record');
    }

    $clearHexStmt = $conn->prepare("UPDATE teacher_hex_codes SET used_by = NULL WHERE id = ?");
    $clearHexStmt->bind_param("i", $hexCodeId);
    $clearHexStmt->execute();
    $clearHexStmt->close();

    $conn->commit();
    logActivity($conn, $email, 'teacher', 'account_delete');
    echo json_encode(['success' => true, 'message' => 'Account and all associated data deleted successfully']);

} catch (Exception $e) {
    $conn->rollback();
    http_response_code(500);
    logActivity($conn, $email, 'teacher', 'account_delete_failed', 'Failed to delete account: ' . $e->getMessage());
    echo json_encode(['success' => false, 'message' => 'Failed to delete account: ' . $e->getMessage()]);
}

$stmt->close();
if (isset($deleteStmt)) $deleteStmt->close();
$conn->close();
?>
