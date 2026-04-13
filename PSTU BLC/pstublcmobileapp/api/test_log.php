<?php
require_once 'db_config.php';
require_once 'logger.php';

ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
error_reporting(E_ALL);

$result = logActivity($conn, 'test@example.com', 'student', 'test_action', 'test details');

if ($result) {
    echo "Logging succeeded.\n";
} else {
    echo "Logging failed.\n";
}
?>
