<?php
header('Content-Type: application/json');
require_once 'db_config.php';

$queries = [
    "ALTER TABLE attendance_sessions ADD COLUMN is_dynamic_qr TINYINT(1) DEFAULT 0",
    "ALTER TABLE attendance_sessions ADD COLUMN qr_interval INT DEFAULT 3",
    "ALTER TABLE attendance_sessions ADD COLUMN qr_code_hex VARCHAR(64) DEFAULT NULL"
];

$results = [];
foreach ($queries as $sql) {
    if ($conn->query($sql) === TRUE) {
        $results[] = 'Success: ' . $sql;
    } else {
        $results[] = 'Notice/Error: ' . $conn->error;
    }
}

echo json_encode(['success' => true, 'details' => $results]);
$conn->close();
?>
