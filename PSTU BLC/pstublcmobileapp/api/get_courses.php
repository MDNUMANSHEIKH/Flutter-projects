<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once 'db_config.php';

if ($conn->connect_error) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Database connection failed']);
    exit();
}

$data = json_decode(file_get_contents("php://input"), true);
$email = trim($data['email'] ?? $_GET['email'] ?? '');

if (empty($email)) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Email is required']);
    exit();
}

$sql = "SELECT c.id as course_id, c.course_code, c.course_name, c.session, c.is_private, f.faculty_name, t.name as teacher_name 
        FROM courses c 
        JOIN faculties f ON c.faculty_code = f.faculty_code 
        JOIN teachers t ON c.teacher_id = t.id 
        WHERE t.email = ?
        ORDER BY c.created_at DESC";

$stmt = $conn->prepare($sql);
if (!$stmt) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Prepare failed: ' . $conn->error]);
    exit();
}

$stmt->bind_param('s', $email);
$stmt->execute();
$result = $stmt->get_result();

$courses = [];
while ($row = $result->fetch_assoc()) {
    $courseId = $row['course_id'];
    $facultyCode = null;
    $session = $row['session'];
    
    $fCode = null;
    foreach ($facultyMap as $code => $info) {
        if ($info['name'] === $row['faculty_name']) {
            $fCode = $code;
            break;
        }
    }
    
    $studentCount = 0;
    if ($fCode && isset($facultyMap[$fCode])) {
        $studentTable = $facultyMap[$fCode]['table'];
        
        if (preg_match('/^20(\d{2})-/', $session, $matches)) {
            $batch = $matches[1];
            $emailPattern = 'ug' . $batch . '%';
            
            $countSql = "SELECT COUNT(*) as total FROM $studentTable WHERE email LIKE ?";
            $countStmt = $conn->prepare($countSql);
            $countStmt->bind_param('s', $emailPattern);
            $countStmt->execute();
            $countResult = $countStmt->get_result();
            $countRow = $countResult->fetch_assoc();
            $studentCount = $countRow['total'];
            $countStmt->close();
        }
    }
    
    $enrollSql = "SELECT COUNT(*) as total FROM enrollments WHERE course_id = ?";
    $enrollStmt = $conn->prepare($enrollSql);
    $enrollStmt->bind_param('i', $courseId);
    $enrollStmt->execute();
    $enrollResult = $enrollStmt->get_result();
    $enrollRow = $enrollResult->fetch_assoc();
    $enrolledCount = $enrollRow['total'];
    $enrollStmt->close();
    
    $row['student_count'] = $studentCount;
    $row['enrolled_count'] = $enrolledCount;
    $courses[] = $row;
}

echo json_encode(['success' => true, 'courses' => $courses]);

$stmt->close();
$conn->close();
?>
