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
$email = trim(strtolower($data['email'] ?? $_GET['email'] ?? ''));

if (empty($email)) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Email is required']);
    exit();
}

$facultyCode = null;
foreach ($facultyMap as $code => $info) {
    $domain = $info['domain'];
    if (strpos($email, '@' . $domain) !== false) {
        $facultyCode = $code;
        break;
    }
}

if (!$facultyCode) {
    $match = preg_match('/^ug\d{2}(\d{2})\d{3}@/', $email, $matches);
    if ($match) {
        $facultyCode = $matches[1];
    }
}

$batchYear = null;
if (preg_match('/^ug(\d{2})/', $email, $matches)) {
    $batchYear = $matches[1];
}

if (!$facultyCode || !$batchYear) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Could not determine faculty or batch for this student']);
    exit();
}

$sessionPrefix = '20' . $batchYear . '-%';

$sql = "SELECT c.id as course_id, c.course_code, c.course_name, c.session, f.faculty_name, t.name as teacher_name,
    (CASE WHEN e.student_email IS NOT NULL AND e.is_blocked = 0 THEN 1 ELSE 0 END) as is_enrolled
    FROM courses c 
    JOIN faculties f ON c.faculty_code = f.faculty_code 
    JOIN teachers t ON c.teacher_id = t.id 
    LEFT JOIN enrollments e ON (e.course_id = c.id AND e.student_email = ?)
    WHERE (
        c.faculty_code = ? AND c.session LIKE ? AND c.is_private = 0
    )
    AND (e.is_blocked IS NULL OR e.is_blocked = 0)
    ORDER BY c.created_at DESC";

$stmt = $conn->prepare($sql);
if (!$stmt) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Prepare failed: ' . $conn->error]);
    exit();
}

$stmt->bind_param('sss', $email, $facultyCode, $sessionPrefix);
$stmt->execute();
$result = $stmt->get_result();

$courses = [];
while ($row = $result->fetch_assoc()) {
    $courses[] = $row;
}

echo json_encode(['success' => true, 'courses' => $courses]);

$stmt->close();
$conn->close();
?>
