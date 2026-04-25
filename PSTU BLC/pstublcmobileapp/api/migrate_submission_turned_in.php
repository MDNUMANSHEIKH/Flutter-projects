<?php
header('Content-Type: application/json');
require_once 'db_config.php';

$sql = "ALTER TABLE `AssignmentSubmission` ADD COLUMN IF NOT EXISTS `turned_in_at` DATETIME NULL AFTER `is_turned_in`";

if ($conn->query($sql) === TRUE) {
    echo json_encode(['success' => true, 'message' => 'Migration successful: turned_in_at column added']);
} else {
    echo json_encode(['success' => false, 'message' => 'Migration failed: ' . $conn->error]);
}

$conn->close();
?>
