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

$data = json_decode(file_get_contents("php://input"), true);
if (!$data) {
    $data = $_POST;
}

$email = trim(strtolower($data['email'] ?? ''));
$newPassword = $data['new_password'] ?? '';

if (empty($email) || empty($newPassword)) {
    http_response_code(400);
    logActivity($conn, $email, 'unknown', 'password_reset_failed', 'Missing email or new password');
    echo json_encode(['success' => false, 'message' => 'Email and new password are required']);
    exit();
}

$studentTable = getStudentTable($email);
$tableToUpdate = null;
$type = '';

if ($studentTable) {
    $stmt = $conn->prepare("SELECT id FROM $studentTable WHERE email = ?");
    $stmt->bind_param('s', $email);
    $stmt->execute();
    if ($stmt->get_result()->num_rows > 0) {
        $tableToUpdate = $studentTable;
        $type = 'student';
    }
    $stmt->close();
}

if (!$tableToUpdate) {
    $stmt = $conn->prepare("SELECT id FROM teachers WHERE email = ?");
    $stmt->bind_param('s', $email);
    $stmt->execute();
    if ($stmt->get_result()->num_rows > 0) {
        $tableToUpdate = 'teachers';
        $type = 'teacher';
    }
    $stmt->close();
}

if (!$tableToUpdate) {
    http_response_code(404);
    logActivity($conn, $email, 'unknown', 'password_reset_failed', 'User not found');
    echo json_encode(['success' => false, 'message' => 'User not found']);
    exit();
}

$newEncrypted = encryptPassword($newPassword);
$updateStmt = $conn->prepare("UPDATE $tableToUpdate SET password_hash = ? WHERE email = ?");

if (!$updateStmt) {
    http_response_code(500);
    logActivity($conn, $email, $type ?: 'unknown', 'password_reset_failed', 'Database update prepare error');
    echo json_encode(['success' => false, 'message' => 'Database update error']);
    exit();
}

$updateStmt->bind_param('ss', $newEncrypted, $email);

if ($updateStmt->execute()) {
    logActivity($conn, $email, $type ?: 'unknown', 'password_reset');
    echo json_encode(['success' => true, 'message' => 'Password reset successfully']);
} else {
    http_response_code(500);
    logActivity($conn, $email, $type ?: 'unknown', 'password_reset_failed', 'Update failed: ' . $updateStmt->error);
    echo json_encode(['success' => false, 'message' => 'Update failed: ' . $updateStmt->error]);
}

$updateStmt->close();
$conn->close();
?>
