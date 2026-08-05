<?php
// attendance_notify_helper.php

if (!function_exists('notifyStudentsForSession')) {
    function notifyStudentsForSession($conn, $session_id, $course_id) {
        // 1. Get Course info
        $cSql = "SELECT course_code, course_name FROM courses WHERE id = ?";
        $cStmt = $conn->prepare($cSql);
        $cStmt->bind_param("i", $course_id);
        $cStmt->execute();
        $cRes = $cStmt->get_result()->fetch_assoc();
        $course_info = ($cRes['course_code'] ?? 'Course') . ": " . ($cRes['course_name'] ?? '');
        $cStmt->close();

        // 2. Insert notifications for enrolled, unblocked students who are NOT already present in attendance_records
        $nSql = "INSERT INTO notifications (student_email, course_id, title, message, type) 
                 SELECT e.student_email, ?, ?, ?, 'attendance' 
                 FROM enrollments e
                 WHERE e.course_id = ? 
                   AND e.is_blocked = 0
                   AND e.student_email NOT IN (
                       SELECT ar.student_email 
                       FROM attendance_records ar 
                       WHERE ar.session_id = ?
                   )";
        
        $notif_title = "Attendance Session Started";
        $notif_msg = "An active attendance session is now open for $course_info. Please mark your attendance.";
        
        $nStmt = $conn->prepare($nSql);
        $nStmt->bind_param("issii", $course_id, $notif_title, $notif_msg, $course_id, $session_id);
        $nStmt->execute();
        $nStmt->close();

        // 3. Mark session as notified
        $uStmt = $conn->prepare("UPDATE attendance_sessions SET notified = 1 WHERE id = ?");
        $uStmt->bind_param("i", $session_id);
        $uStmt->execute();
        $uStmt->close();
    }
}

if (!function_exists('checkAndNotifyActiveSessions')) {
    function checkAndNotifyActiveSessions($conn) {
        $nowStr = date('Y-m-d H:i:s');
        $sql = "SELECT id, course_id FROM attendance_sessions 
                WHERE (is_private = 0 OR is_private IS NULL) 
                  AND session_date <= ? 
                  AND session_end >= ? 
                  AND (notified = 0 OR notified IS NULL)";
        
        $stmt = $conn->prepare($sql);
        $stmt->bind_param("ss", $nowStr, $nowStr);
        $stmt->execute();
        $result = $stmt->get_result();
        
        while ($row = $result->fetch_assoc()) {
            notifyStudentsForSession($conn, (int)$row['id'], (int)$row['course_id']);
        }
        $stmt->close();
    }
}
?>
