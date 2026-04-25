<?php
header('Content-Type: application/json');
require_once 'db_config.php';

$sql = "ALTER TABLE `AssignmentSubmission` ADD COLUMN IF NOT EXISTS `is_turned_in` TINYINT(1) DEFAULT 0 AFTER `file_names`";

if ($conn->query($sql) === TRUE) {
    echo json_encode(['success' => true, 'message' => 'Migration successful: is_turned_in column added']);
} else {
    echo json_encode(['success' => false, 'message' => 'Migration failed: ' . $conn->error]);
}

$conn->close();
?>
