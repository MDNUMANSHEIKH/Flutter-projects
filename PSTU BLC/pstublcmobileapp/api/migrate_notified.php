<?php
require_once 'db_config.php';

$sql = "ALTER TABLE attendance_sessions ADD COLUMN notified TINYINT(1) DEFAULT 0";

if ($conn->query($sql) === TRUE) {
    echo "Column 'notified' added successfully.\n";
} else {
    echo "Error or column already exists: " . $conn->error . "\n";
}

$conn->close();
?>
