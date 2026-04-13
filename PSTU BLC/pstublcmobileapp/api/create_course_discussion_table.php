<?php
header('Content-Type: application/json');

require_once 'db_config.php';

$sql = "CREATE TABLE IF NOT EXISTS course_discussion_messages (
    id INT AUTO_INCREMENT PRIMARY KEY,
    course_id INT NOT NULL,
    sender_email VARCHAR(100) NOT NULL,
    sender_name VARCHAR(120) NOT NULL,
    sender_role VARCHAR(20) NOT NULL,
    message TEXT NOT NULL,
    is_edited TINYINT(1) NOT NULL DEFAULT 0,
    edited_at DATETIME NULL,
    created_at DATETIME NOT NULL,
    INDEX idx_course_created (course_id, created_at),
    INDEX idx_sender_email (sender_email),
    INDEX idx_sender_role (sender_role)
)";

if ($conn->query($sql) === TRUE) {
    echo json_encode(['success' => true, 'message' => 'Course discussion table created/verified successfully']);
} else {
    echo json_encode(['success' => false, 'message' => 'Error creating table: ' . $conn->error]);
}

$conn->close();
?>