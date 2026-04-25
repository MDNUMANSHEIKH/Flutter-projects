<?php
header('Content-Type: application/json');

require_once 'db_config.php';

$sql = "CREATE TABLE IF NOT EXISTS `assignment_comment_messages` (
    id INT AUTO_INCREMENT PRIMARY KEY,
    assignment_id INT NOT NULL,
    course_id INT NOT NULL,
    sender_email VARCHAR(100) NOT NULL,
    sender_name VARCHAR(120) NOT NULL,
    sender_role VARCHAR(20) NOT NULL,
    target_audience VARCHAR(20) NOT NULL DEFAULT 'everyone',
    target_student_email VARCHAR(100) NULL,
    message TEXT NOT NULL,
    reply_to_message_id INT NULL,
    reply_to_sender_name VARCHAR(120) NULL,
    reply_to_message TEXT NULL,
    is_edited TINYINT(1) NOT NULL DEFAULT 0,
    edited_at DATETIME NULL,
    created_at DATETIME NOT NULL,
    INDEX idx_assignment_created (assignment_id, created_at),
    INDEX idx_assignment_course (course_id),
    INDEX idx_sender_email (sender_email),
    INDEX idx_sender_role (sender_role),
    INDEX idx_target_audience (target_audience),
    INDEX idx_target_student_email (target_student_email)
)";

if ($conn->query($sql) === TRUE) {
    echo json_encode(['success' => true, 'message' => 'Assignment comment table created/verified successfully']);
} else {
    echo json_encode(['success' => false, 'message' => 'Error creating table: ' . $conn->error]);
}

$conn->close();
?>
