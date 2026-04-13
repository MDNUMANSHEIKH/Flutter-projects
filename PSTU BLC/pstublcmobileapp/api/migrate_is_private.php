<?php
header('Content-Type: application/json');
require_once 'db_config.php';

$sql = "ALTER TABLE attendance_sessions ADD COLUMN is_private TINYINT(1) DEFAULT 0";

if ($conn->query($sql) === TRUE) {
    echo json_encode(['success' => true, 'message' => 'Column is_private added successfully']);
} else {
    echo json_encode(['success' => false, 'message' => 'Error adding column: ' . $conn->error]);
}

$conn->close();
?>
