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

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Method not allowed']);
    exit();
}

$data = json_decode(file_get_contents("php://input"), true);
if (!$data) {
    $data = $_POST;
}

$email = trim($data['email'] ?? '');
$courseCode = trim($data['course_code'] ?? '');
$courseName = trim($data['course_name'] ?? '');
$session = trim($data['session'] ?? '');
$facultyName = strtoupper(trim($data['faculty'] ?? ''));
$isPrivate = (int)($data['is_private'] ?? 1) === 1 ? 1 : 0;

if (empty($email) || empty($courseCode) || empty($courseName) || empty($session) || empty($facultyName)) {
    http_response_code(400);
    logActivity($conn, $email, 'teacher', 'course_create_failed', 'Missing fields');
    echo json_encode(['success' => false, 'message' => 'All fields are required']);
    exit();
}

$nameToCode = [
    'AGRI' => '01',
    'CSE' => '02',
    'FBA' => '03',
    'FISHERIES' => '04',
    'NFS' => '05',
    'ESDM' => '06'
];

if (!isset($nameToCode[$facultyName])) {
    http_response_code(400);
    logActivity($conn, $email, 'teacher', 'course_create_failed', 'Invalid faculty selected');
    echo json_encode(['success' => false, 'message' => 'Invalid faculty selected']);
    exit();
}

$facultyCode = $nameToCode[$facultyName];

$teacherStmt = $conn->prepare("SELECT id FROM teachers WHERE email = ?");
$teacherStmt->bind_param('s', $email);
$teacherStmt->execute();
$teacherResult = $teacherStmt->get_result();
$teacher = $teacherResult->fetch_assoc();

if (!$teacher) {
    http_response_code(404);
    logActivity($conn, $email, 'teacher', 'course_create_failed', 'Teacher not found');
    echo json_encode(['success' => false, 'message' => 'Teacher not found']);
    exit();
}

$teacherId = $teacher['id'];


$stmt = $conn->prepare("INSERT INTO courses (course_code, course_name, session, faculty_code, teacher_id, is_private) VALUES (?, ?, ?, ?, ?, ?)");
if (!$stmt) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Prepare failed: ' . $conn->error]);
    exit();
}

$stmt->bind_param('ssssii', $courseCode, $courseName, $session, $facultyCode, $teacherId, $isPrivate);

if ($stmt->execute()) {
    $courseId = $stmt->insert_id;
    logActivity($conn, $email, 'teacher', 'course_create', "Course Code: $courseCode");

    if ($isPrivate !== 1) {
        // Send notifications to all students in the same faculty and session
        $YY = substr($session, 2, 2); // Extract "20" from "2020-21"
        $targetTable = $facultyMap[$facultyCode]['table'];
        
        $nSql = "INSERT INTO notifications (student_email, course_id, title, message, type) 
                 SELECT email, ?, ?, ?, 'course_launch' 
                 FROM $targetTable 
                 WHERE email LIKE ?";
        
        $notifTitle = "New Course Launched";
        $notifMsg = "A new course ($courseCode - $courseName) has been launched for your session. You can enroll now!";
        $emailPattern = "ug" . $YY . "%";

        $nStmt = $conn->prepare($nSql);
        $nStmt->bind_param("isss", $courseId, $notifTitle, $notifMsg, $emailPattern);
        $nStmt->execute();
        $nStmt->close();

        echo json_encode(['success' => true, 'message' => 'Course created successfully and students notified']);
    } else {
        echo json_encode(['success' => true, 'message' => 'Private course created successfully']);
    }
} else {
    http_response_code(500);
    logActivity($conn, $email, 'teacher', 'course_create_failed', 'Insert failed: ' . $stmt->error);
    echo json_encode(['success' => false, 'message' => 'Insert failed: ' . $stmt->error]);
}

$stmt->close();
$conn->close();
?>
