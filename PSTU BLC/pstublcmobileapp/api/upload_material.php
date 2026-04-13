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

$teacherEmail = $_POST['teacher_email'] ?? '';
$courseId = $_POST['course_id'] ?? '';

if (empty($teacherEmail) || empty($courseId) || empty($_FILES['material'])) {
    http_response_code(400);
    logActivity($conn, $teacherEmail, 'teacher', 'material_upload_failed', 'Required fields missing');
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
    logActivity($conn, $teacherEmail, 'teacher', 'material_upload_failed', 'Teacher not found');
    echo json_encode(['success' => false, 'message' => 'Teacher not found']);
    exit();
}

$teacherId = $teacher['id'];

$cStmt = $conn->prepare("SELECT id FROM courses WHERE id = ? AND teacher_id = ?");
$cStmt->bind_param('ii', $courseId, $teacherId);
$cStmt->execute();
$cRes = $cStmt->get_result();
$course = $cRes->fetch_assoc();
$cStmt->close();

if (!$course) {
    http_response_code(403);
    logActivity($conn, $teacherEmail, 'teacher', 'material_upload_failed', 'Unauthorized or invalid course');
    echo json_encode(['success' => false, 'message' => 'Unauthorized or invalid course']);
    exit();
}

$file = $_FILES['material'];
$ext = pathinfo($file['name'], PATHINFO_EXTENSION);

$forbidden = ['php', 'php3', 'php4', 'php5', 'phtml', 'exe', 'sh', 'bat'];
if (in_array(strtolower($ext), $forbidden)) {
    http_response_code(400);
    logActivity($conn, $teacherEmail, 'teacher', 'material_upload_failed', 'Forbidden file type');
    echo json_encode(['success' => false, 'message' => 'File type not allowed']);
    exit();
}

$newFileName = time() . '_' . preg_replace('/[^a-zA-Z0-9._-]/', '_', $file['name']);
$uploadDir = '../uploads/materials/';
$targetPath = $uploadDir . $newFileName;

if (move_uploaded_file($file['tmp_name'], $targetPath)) {
    $stmt = $conn->prepare("INSERT INTO course_materials (course_id, teacher_id, file_name, file_path, file_type, file_size) VALUES (?, ?, ?, ?, ?, ?)");
    $stmt->bind_param('iisssi', $courseId, $teacherId, $file['name'], $newFileName, $file['type'], $file['size']);
    
    if ($stmt->execute()) {
        // Notify all enrolled students
        $nSql = "INSERT INTO notifications (student_email, course_id, title, message, type) 
                 SELECT student_email, ?, ?, ?, 'material' 
                 FROM enrollments 
                 WHERE course_id = ? AND is_blocked = 0";

        $notifTitle = "New Study Material";
        $notifMsg = "New file/document has been uploaded for your course. Check it in the materials section.";

        $nStmt = $conn->prepare($nSql);
        $nStmt->bind_param("isssi", $courseId, $notifTitle, $notifMsg, $courseId);
        $nStmt->execute();
        $nStmt->close();

        logActivity($conn, $teacherEmail, 'teacher', 'material_upload', "Course ID: $courseId, File: " . $file['name']);
        echo json_encode(['success' => true, 'message' => 'File uploaded successfully and students notified']);
    } else {
        unlink($targetPath);
        http_response_code(500);
        logActivity($conn, $teacherEmail, 'teacher', 'material_upload_failed', 'Database error while inserting material');
        echo json_encode(['success' => false, 'message' => 'Database error']);
    }
    $stmt->close();
} else {
    http_response_code(500);
    logActivity($conn, $teacherEmail, 'teacher', 'material_upload_failed', 'File move/upload failed');
    echo json_encode(['success' => false, 'message' => 'Upload failed']);
}

$conn->close();
?>
