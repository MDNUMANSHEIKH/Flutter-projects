<?php
header('Content-Type: application/json');

require_once 'db_config.php';

$sql = "CREATE TABLE IF NOT EXISTS `AssignmentSubmission` (
    id INT AUTO_INCREMENT PRIMARY KEY,
    assignment_id INT NOT NULL,
    student_email VARCHAR(100) NOT NULL,
    file_ids TEXT NOT NULL, -- JSON array of Appwrite file IDs
    file_names TEXT NOT NULL, -- JSON array of original file names
    is_turned_in TINYINT(1) DEFAULT 0,
    submitted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_submission_assignment (assignment_id),
    INDEX idx_submission_student (student_email),
    UNIQUE KEY unq_student_assignment (student_email, assignment_id)
)";

if ($conn->query($sql) === TRUE) {
    echo json_encode(['success' => true, 'message' => 'AssignmentSubmission table created/verified successfully']);
} else {
    echo json_encode(['success' => false, 'message' => 'Error creating table: ' . $conn->error]);
}

$conn->close();
?>
