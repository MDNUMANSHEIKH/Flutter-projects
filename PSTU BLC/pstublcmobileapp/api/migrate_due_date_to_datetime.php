<?php
header('Content-Type: application/json');
require_once 'db_config.php';

$sql = "ALTER TABLE `Assignment` MODIFY COLUMN due_date DATETIME NOT NULL";

if ($conn->query($sql) === TRUE) {
    echo json_encode(['success' => true, 'message' => 'Assignment due_date column migrated to DATETIME successfully']);
} else {
    echo json_encode(['success' => false, 'message' => 'Error migrating column: ' . $conn->error]);
}

$conn->close();
?>
