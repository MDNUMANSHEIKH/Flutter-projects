<?php
header('Content-Type: application/json');

require_once 'db_config.php';

$sql = "CREATE TABLE IF NOT EXISTS `Assignment` (
    id INT AUTO_INCREMENT PRIMARY KEY,
    course_id INT NOT NULL,
    teacher_email VARCHAR(100) NOT NULL,
    title VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    due_date DATE NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    edited_at DATETIME NULL,
    is_private TINYINT(1) NOT NULL DEFAULT 0,
    INDEX idx_assignment_course_created (course_id, created_at),
    INDEX idx_assignment_teacher (teacher_email),
    INDEX idx_assignment_due_date (due_date)
)";

if ($conn->query($sql) === TRUE) {
    $hasEditedAt = false;
    $columnResult = $conn->query("SHOW COLUMNS FROM `Assignment` LIKE 'edited_at'");
    if ($columnResult && $columnResult->num_rows > 0) {
        $hasEditedAt = true;
    }

    if (!$hasEditedAt) {
        $alterSql = "ALTER TABLE `Assignment` ADD COLUMN edited_at DATETIME NULL AFTER created_at";
        if (!$conn->query($alterSql)) {
            echo json_encode(['success' => false, 'message' => 'Table created but failed to add edited_at: ' . $conn->error]);
            $conn->close();
            exit();
        }
    }

    $hasIsPrivate = false;
    $privateColumnResult = $conn->query("SHOW COLUMNS FROM `Assignment` LIKE 'is_private'");
    if ($privateColumnResult && $privateColumnResult->num_rows > 0) {
        $hasIsPrivate = true;
    }

    if (!$hasIsPrivate) {
        $alterPrivateSql = "ALTER TABLE `Assignment` ADD COLUMN is_private TINYINT(1) NOT NULL DEFAULT 0 AFTER edited_at";
        if (!$conn->query($alterPrivateSql)) {
            echo json_encode(['success' => false, 'message' => 'Table created but failed to add is_private: ' . $conn->error]);
            $conn->close();
            exit();
        }
    }

    echo json_encode(['success' => true, 'message' => 'Assignment table created/verified successfully']);
} else {
    echo json_encode(['success' => false, 'message' => 'Error creating table: ' . $conn->error]);
}

$conn->close();
?>
