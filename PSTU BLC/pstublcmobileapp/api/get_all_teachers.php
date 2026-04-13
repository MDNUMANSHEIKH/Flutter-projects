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

$allTeachers = [];

$sql = "SELECT id, name, email, phone FROM teachers ORDER BY name ASC";
$result = $conn->query($sql);

if ($result) {
    while ($row = $result->fetch_assoc()) {
        $allTeachers[] = $row;
    }
}

echo json_encode([
    'success' => true,
    'teachers' => $allTeachers
]);

$conn->close();
?>
