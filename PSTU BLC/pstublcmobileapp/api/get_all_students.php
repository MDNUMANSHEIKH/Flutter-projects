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

$allStudents = [];

// Iterate through the facultyMap defined in db_config.php
foreach ($facultyMap as $code => $info) {
    $tableName = $info['table'];
    $facultyName = $info['name'];
    
    // Select student basic info
    $sql = "SELECT id, name, email, phone FROM $tableName";
    $result = $conn->query($sql);
    
    if ($result) {
        while ($row = $result->fetch_assoc()) {
            $email = $row['email'];
            
            // Extract session from email format: ugYYXXXX@domain.pstu.ac.bd
            // YY is the 2-digit start year, and we present it as YYYY-YY.
            $session = 'Unknown';
            if (preg_match('/^ug(\d{2})/i', $email, $matches)) {
                $startYearTwo = (int)$matches[1];
                $startYearFull = 2000 + $startYearTwo;
                $endYearTwo = ($startYearTwo + 1) % 100;
                $session = $startYearFull . '-' . str_pad((string)$endYearTwo, 2, '0', STR_PAD_LEFT);
            }
            
            $row['faculty_name'] = $facultyName;
            $row['faculty_code'] = $info['code'];
            $row['session'] = $session;
            
            $allStudents[] = $row;
        }
    }
}

// Sort all students by session (desc) and then name
usort($allStudents, function($a, $b) {
    if ($a['session'] === $b['session']) {
        return strcmp($a['name'], $b['name']);
    }
    return strcmp($b['session'], $a['session']);
});

echo json_encode([
    'success' => true,
    'students' => $allStudents
]);

$conn->close();
?>
