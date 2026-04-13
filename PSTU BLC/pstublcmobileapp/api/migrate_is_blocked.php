<?php
require_once 'db_config.php';

$sql = "ALTER TABLE enrollments ADD COLUMN IF NOT EXISTS is_blocked TINYINT(1) DEFAULT 0";

if ($conn->query($sql) === TRUE) {
    echo json_encode(['success' => true, 'message' => 'Column is_blocked added successfully']);
} else {
    echo json_encode(['success' => false, 'message' => 'Error: ' . $conn->error]);
}

$conn->close();
?>
