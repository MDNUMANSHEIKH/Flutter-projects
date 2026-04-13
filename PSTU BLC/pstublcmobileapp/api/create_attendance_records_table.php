<?php
require_once 'db_config.php';

$sql = "CREATE TABLE IF NOT EXISTS attendance_records (
    id INT AUTO_INCREMENT PRIMARY KEY,
    session_id INT NOT NULL,
    student_email VARCHAR(255) NOT NULL,
    marked_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY unique_participation (session_id, student_email),
    FOREIGN KEY (session_id) REFERENCES attendance_sessions(id) ON DELETE CASCADE
)";

if ($conn->query($sql) === TRUE) {
    echo json_encode(['success' => true, 'message' => 'Table attendance_records created successfully']);
} else {
    echo json_encode(['success' => false, 'message' => 'Error creating table: ' . $conn->error]);
}

$conn->close();
?>
