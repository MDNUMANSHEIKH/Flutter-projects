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

$data = json_decode(file_get_contents('php://input'), true);
$email = trim(strtolower($data['email'] ?? $_GET['email'] ?? ''));
$scopes = $data['scopes'] ?? [];

if (!is_array($scopes)) {
    $scopes = [];
}

$scopes = array_values(array_unique(array_filter(array_map(function ($value) {
    return trim((string)$value);
}, $scopes), function ($value) {
    return $value !== '';
})));

if (empty($email)) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => 'Email is required']);
    exit();
}

if (empty($scopes)) {
    echo json_encode(['success' => true, 'courses' => []]);
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

$sql = "SELECT id as course_id, course_code, course_name, session, is_private
        FROM courses
        WHERE faculty_code = ? AND session LIKE ?";
$stmt = $conn->prepare($sql);
if (!$stmt) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Prepare failed: ' . $conn->error]);
    exit();
}

$stmt->bind_param('ss', $facultyCode, $sessionPrefix);
$stmt->execute();
$result = $stmt->get_result();

$scopeSet = array_fill_keys($scopes, true);
$courses = [];

while ($row = $result->fetch_assoc()) {
    $courseId = (int)($row['course_id'] ?? 0);
    $code = trim((string)($row['course_code'] ?? ''));
    $name = trim((string)($row['course_name'] ?? ''));
    $session = trim((string)($row['session'] ?? ''));

    $scope = '';
    if ($courseId > 0) {
        $scope = (string)$courseId;
    } else {
        $raw = strtolower($code . '_' . $session);
        $scope = preg_replace('/[^a-z0-9]+/', '_', $raw);
        $scope = trim((string)$scope, '_');
        if ($scope === '') {
            $scope = 'unknown_course';
        }
    }

    if (!isset($scopeSet[$scope])) {
        continue;
    }

    $courses[] = [
        'scope' => $scope,
        'course_id' => $courseId,
        'course_code' => $code,
        'course_name' => $name,
        'is_private' => (int)($row['is_private'] ?? 0),
    ];
}

echo json_encode(['success' => true, 'courses' => $courses]);

$stmt->close();
$conn->close();
?>
