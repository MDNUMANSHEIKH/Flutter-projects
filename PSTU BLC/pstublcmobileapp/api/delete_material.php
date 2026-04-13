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

if ($conn->connect_error) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Database connection failed']);
    exit();
}

$data = json_decode(file_get_contents("php://input"), true);
$materialId = $data['material_id'] ?? '';
$teacherEmail = $data['teacher_email'] ?? '';

if (empty($materialId) || empty($teacherEmail)) {
    http_response_code(400);
    logActivity($conn, $teacherEmail, 'teacher', 'material_delete_failed', 'Required fields missing');
    echo json_encode(['success' => false, 'message' => 'Required fields missing']);
    exit();
}

$tStmt = $conn->prepare("SELECT id FROM teachers WHERE email = ?");
$tStmt->bind_param('s', $teacherEmail);
$tStmt->execute();
$tRes = $tStmt->get_result();
$teacher = $tRes->fetch_assoc();
$tStmt->close();

if (!$teacher) {
    http_response_code(404);
    logActivity($conn, $teacherEmail, 'teacher', 'material_delete_failed', 'Teacher not found');
    echo json_encode(['success' => false, 'message' => 'Teacher not found']);
    exit();
}

$teacherId = $teacher['id'];

$mStmt = $conn->prepare("SELECT file_path FROM course_materials WHERE id = ? AND teacher_id = ?");
$mStmt->bind_param('ii', $materialId, $teacherId);
$mStmt->execute();
$mRes = $mStmt->get_result();
$material = $mRes->fetch_assoc();
$mStmt->close();

if (!$material) {
    http_response_code(403);
    logActivity($conn, $teacherEmail, 'teacher', 'material_delete_failed', 'Unauthorized or invalid material');
    echo json_encode(['success' => false, 'message' => 'Unauthorized or invalid material']);
    exit();
}

$filePath = '../uploads/materials/' . $material['file_path'];

$stmt = $conn->prepare("DELETE FROM course_materials WHERE id = ?");
$stmt->bind_param('i', $materialId);

if ($stmt->execute()) {
    if (file_exists($filePath)) {
        unlink($filePath);
    }
    logActivity($conn, $teacherEmail, 'teacher', 'material_delete', "Material ID: $materialId");
    echo json_encode(['success' => true, 'message' => 'Material deleted successfully']);
} else {
    http_response_code(500);
    logActivity($conn, $teacherEmail, 'teacher', 'material_delete_failed', 'Database error during delete');
    echo json_encode(['success' => false, 'message' => 'Database error']);
}

$stmt->close();
$conn->close();
?>
