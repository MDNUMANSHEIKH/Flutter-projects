<?php
require_once 'db_config.php';

$sql = "CREATE TABLE IF NOT EXISTS notifications (
    id INT AUTO_INCREMENT PRIMARY KEY,
    student_email VARCHAR(100) NOT NULL,
    course_id INT,
    title VARCHAR(100),
    message TEXT,
    type VARCHAR(50),
    is_read TINYINT DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_student_email (student_email),
    INDEX idx_is_read (is_read),
    INDEX idx_created_at (created_at)
)";

if ($conn->query($sql) === TRUE) {
    echo json_encode(['success' => true, 'message' => 'Notifications table created/verified successfully']);
} else {
    echo json_encode(['success' => false, 'message' => 'Error creating table: ' . $conn->error]);
}

$conn->close();
?>
