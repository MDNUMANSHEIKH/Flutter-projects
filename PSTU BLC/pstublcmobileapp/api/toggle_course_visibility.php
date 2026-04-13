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
if (!$data) {
    $data = $_POST;
}

$courseId = $data['course_id'] ?? null;
$isPrivate = isset($data['is_private']) ? (int) $data['is_private'] : null;

if ($courseId === null || $isPrivate === null) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Course ID and visibility status are required']);
    exit();
}

$sql = "UPDATE courses SET is_private = ? WHERE id = ?";
$stmt = $conn->prepare($sql);

if (!$stmt) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Prepare failed: ' . $conn->error]);
    exit();
}

$stmt->bind_param('ii', $isPrivate, $courseId);

if ($stmt->execute()) {
    $action = $isPrivate ? 'course_private' : 'course_public';
    logActivity($conn, null, 'system', $action, "Course ID: $courseId");

    // When course is made PUBLIC, notify matching students
    if ($isPrivate == 0) {
        // Get course details for the notification
        $cSql = "SELECT c.course_code, c.course_name, c.session, c.faculty_code
                 FROM courses c WHERE c.id = ?";
        $cStmt = $conn->prepare($cSql);
        $cStmt->bind_param("i", $courseId);
        $cStmt->execute();
        $cRes = $cStmt->get_result()->fetch_assoc();
        $cStmt->close();

        if ($cRes) {
            $courseCode = $cRes['course_code'];
            $courseName = $cRes['course_name'];
            $session = $cRes['session'];
            $facultyCode = $cRes['faculty_code'];

            // Determine target student table from facultyCode
            if (isset($facultyMap[$facultyCode])) {
                $targetTable = $facultyMap[$facultyCode]['table'];

                // Match students from the same batch/year using session prefix
                $YY = substr($session, 2, 2); // "20" from "2020-21"
                $emailPattern = "ug" . $YY . "%";

                $notifTitle = "New Course Launched";
                $notifMsg = "A new course ($courseCode - $courseName) is now available for your session.";

                $nSql = "INSERT INTO notifications (student_email, course_id, title, message, type)
                         SELECT email, ?, ?, ?, 'course_launch'
                         FROM $targetTable
                         WHERE email LIKE ?";
                $nStmt = $conn->prepare($nSql);
                $nStmt->bind_param("isss", $courseId, $notifTitle, $notifMsg, $emailPattern);
                $nStmt->execute();
                $nStmt->close();
            }
        }
    }

    echo json_encode(['success' => true, 'message' => 'Course visibility updated successfully']);
} else {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Update failed: ' . $stmt->error]);
}

$stmt->close();
$conn->close();
?>