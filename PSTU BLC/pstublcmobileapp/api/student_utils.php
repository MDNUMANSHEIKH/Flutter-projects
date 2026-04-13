<?php
require_once 'db_config.php';

function getStudentTable($email) {
    global $facultyMap;
    
    if (preg_match('/^ug(\d{2})(\d{2})(\d{3})@([a-z]+)\.pstu\.ac\.bd$/i', $email, $matches)) {
        $facultyCode = $matches[2];
        if (isset($facultyMap[$facultyCode])) {
            return $facultyMap[$facultyCode]['table'];
        }
    }
    
    $parts = explode('@', $email);
    if (count($parts) === 2) {
        $domain = strtolower($parts[1]);
        foreach ($facultyMap as $faculty) {
            if ($faculty['domain'] === $domain) {
                return $faculty['table'];
            }
        }
    }
    
    return null;
}
?>
