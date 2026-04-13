<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once 'db_config.php';
require_once 'logger.php';

function isStudentEmail($email, &$faculty)
{
    global $facultyMap;
    if (!preg_match('/^ug(\d{2})(\d{2})(\d{3})@([a-z]+)\.pstu\.ac\.bd$/i', $email, $matches)) {
        return false;
    }

    $facultyCode = $matches[2];
    $domain = strtolower($matches[4]);

    if (!isset($facultyMap[$facultyCode])) {
        return false;
    }

    $expectedDomain = $facultyMap[$facultyCode]['domain'];
    if ($domain !== explode('.', $expectedDomain)[0]) {
        return false;
    }

    $faculty = $facultyMap[$facultyCode];
    return true;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Method not allowed']);
    exit();
}

$data = json_decode(file_get_contents('php://input'), true);
if (!$data) {
    $data = $_POST;
}

$email = trim(strtolower($data['email'] ?? ''));
$password = $data['password'] ?? '';

if (empty($email) || empty($password)) {
    http_response_code(400);
    logActivity($conn, $email, 'unknown', 'login_failed', "Empty password provided");
    echo json_encode(['success' => false, 'message' => 'Email and password are required']);
    exit();
}


$role = 'teacher';
$faculty = null;

try {
    if (isStudentEmail($email, $faculty)) {
        $role = 'student';
        $table = $faculty['table'];
        $stmt = $conn->prepare("SELECT id, name, email, password_hash FROM $table WHERE email = ? LIMIT 1");
        $stmt->bind_param('s', $email);
        $stmt->execute();
        $result = $stmt->get_result();
        $user = $result->fetch_assoc();
        $stmt->close();

        if (!$user) {
            http_response_code(401);
            logActivity($conn, $email, 'student', 'login_failed', "User not found. Password provided.");
            echo json_encode(['success' => false, 'message' => 'Invalid email or password']);
            exit();
        }
        
        
        $decryptedPassword = decryptPassword($user['password_hash']);
        if ($password !== $decryptedPassword) {
            http_response_code(401);
            logActivity($conn, $email, 'student', 'login_failed', "Invalid password for student");
            echo json_encode(['success' => false, 'message' => 'Invalid email or password']);
            exit();
        }
        logActivity($conn, $email, 'student', 'login_success', "Correct password verified");

        echo json_encode([
            'success' => true,
            'message' => 'Login successful',
            'role' => $role,
            'faculty' => [
                'code' => $faculty['code'],
                'name' => $faculty['name']
            ]
        ]);
    } else {  
        $stmt = $conn->prepare('SELECT id, name, email, phone, password_hash FROM teachers WHERE email = ? LIMIT 1');
        $stmt->bind_param('s', $email);
        $stmt->execute();
        $result = $stmt->get_result();
        $user = $result->fetch_assoc();
        $stmt->close();

        if (!$user) {
            http_response_code(401);
            logActivity($conn, $email, 'teacher', 'login_failed', "Teacher not found. Password provided.");
            echo json_encode(['success' => false, 'message' => 'Invalid email or password']);
            exit();
        }
        
        $decryptedPassword = decryptPassword($user['password_hash']);
        if ($password !== $decryptedPassword) {
            http_response_code(401);
            logActivity($conn, $email, 'teacher', 'login_failed', "Invalid password for teacher");
            echo json_encode(['success' => false, 'message' => 'Invalid email or password']);
            exit();
        }
        logActivity($conn, $user['email'], 'teacher', 'login_success', "Correct password verified");

        echo json_encode([
            'success' => true,
            'message' => 'Login successful',
            'role' => $role,
            'name' => $user['name'],
            'email' => $user['email'],
            'phone' => $user['phone']
        ]);
    }
} catch (Exception $e) {
    http_response_code(500);
    logActivity($conn, $email, $role, 'login_failed', 'Server error: ' . $e->getMessage());
    echo json_encode(['success' => false, 'message' => 'Server error: ' . $e->getMessage()]);
}

$conn->close();
?>
