<?php
function ensureActivityLogsTable($conn) {
    $sql = "CREATE TABLE IF NOT EXISTS activity_logs (
        id INT AUTO_INCREMENT PRIMARY KEY,
        user_email VARCHAR(150) DEFAULT NULL,
        user_role VARCHAR(20) DEFAULT NULL,
        action VARCHAR(120) NOT NULL,
        details TEXT DEFAULT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_user_email (user_email),
        INDEX idx_action (action),
        INDEX idx_created_at (created_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci";

    if (!$conn->query($sql)) {
        error_log("Failed to ensure activity_logs table: " . $conn->error);
        return false;
    }

    return true;
}

function logActivity($conn, $user_email, $user_role, $action, $details = null) {
    if (!$conn || $conn->connect_error) {
        error_log("Database connection error in logActivity");
        return false;
    }

    if (!ensureActivityLogsTable($conn)) {
        return false;
    }

    $email = trim((string)($user_email ?? ''));
    $role = trim((string)($user_role ?? 'unknown'));
    $act = trim((string)($action ?? 'unknown_action'));
    $logDetails = $details;

    if ($email === '') {
        $email = null;
    }

    if ($role === '') {
        $role = 'unknown';
    }

    if ($act === '') {
        $act = 'unknown_action';
    }

    $stmt = $conn->prepare("INSERT INTO activity_logs (user_email, user_role, action, details) VALUES (?, ?, ?, ?)");
    if ($stmt) {
        // SECURITY: Redact explicit password values, but keep generic messages readable.
        if ($logDetails && preg_match('/password\s*[:=]\s*\S+/i', $logDetails)) {
            $logDetails = preg_replace('/(password\s*[:=]\s*)\S+/i', '$1[REDACTED]', $logDetails);
        }

        $stmt->bind_param("ssss", $email, $role, $act, $logDetails);
        if (!$stmt->execute()) {
            error_log("Execute failed in logActivity: " . $stmt->error);
            $stmt->close();
            return false;
        }
        $stmt->close();
        return true;
    } else {
        error_log("Prepare failed in logActivity: " . $conn->error);
        return false;
    }
}
?>
