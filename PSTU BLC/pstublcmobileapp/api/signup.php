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

function validateEmail($email, &$faculty) {
    global $facultyMap;
    
    // Check format: ugYYFFNNN@faculty.pstu.ac.bd
    if (!preg_match('/^ug(\d{2})(\d{2})(\d{3})@([a-z]+)\.pstu\.ac\.bd$/i', $email, $matches)) {
        return ['valid' => false, 'error' => 'Invalid email format. Must be ugYYFFNNN@faculty.pstu.ac.bd'];
    }
    
    $year = $matches[1];
    $facultyCode = $matches[2];
    $studentNum = $matches[3];
    $domain = strtolower($matches[4]);
    
    // Check if faculty code exists
    if (!isset($facultyMap[$facultyCode])) {
        return ['valid' => false, 'error' => 'Invalid faculty code in email'];
    }
    
    $expectedDomain = $facultyMap[$facultyCode]['domain'];
    
    if ($domain !== explode('.', $expectedDomain)[0]) {
        return ['valid' => false, 'error' => 'Faculty code does not match email domain. Expected: ug' . $year . $facultyCode . $studentNum . '@' . $expectedDomain];
    }
    
    $faculty = $facultyMap[$facultyCode];
    return ['valid' => true];
}

function hashPassword($password) {
    return encryptPassword($password);
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

$name = trim($data['name'] ?? '');
$email = trim(strtolower($data['email'] ?? ''));
$phone = trim($data['phone'] ?? '');
$category = trim(strtolower($data['category'] ?? ''));
$hex = trim($data['hex'] ?? '');
$password = $data['password'] ?? '';
$confirmPassword = $data['confirm-password'] ?? $data['confirmPassword'] ?? '';
$validateOnly = isset($data['validate_only']) && ($data['validate_only'] === true || $data['validate_only'] === 'true');
$faculty = null;

$errors = [];

if (empty($name)) {
    $errors['name'] = 'Name is required';
} elseif (strlen($name) < 3 || strlen($name) > 15) {
    $errors['name'] = 'Name must be 3-15 characters';
}

if (empty($email)) {
    $errors['email'] = 'Email is required';
} elseif ($category === 'student') {
    $emailValidation = validateEmail($email, $faculty);
    
    if (!$emailValidation['valid']) {
        $errors['email'] = $emailValidation['error'];
    }
}

if (empty($phone)) {
    $errors['phone'] = 'Phone is required';
} elseif (!preg_match('/^(\+?88)?01[0-9]{9}$/', $phone)) {
    $errors['phone'] = 'Invalid phone format. Must be 01xxxxxxxxx';
}

if ($category !== 'student' && $category !== 'teacher') {
    $errors['category'] = 'Invalid category selected';
}

if ($category === 'teacher') {
    if (empty($hex)) {
        $errors['hex'] = 'Hex code is required for teachers';
    }
}

if (empty($password)) {
    $errors['password'] = 'Password is required';
} elseif (strlen($password) < 3) {
    $errors['password'] = 'Password must be at least 3 characters';
}

if ($password !== $confirmPassword) {
    $errors['password'] = 'Passwords do not match';
}

if (!empty($errors)) {
    http_response_code(400);
    logActivity($conn, $email, $category, 'signup_failed', 'Validation failed: ' . array_values($errors)[0]);
    echo json_encode(['success' => false, 'errors' => $errors, 'message' => array_values($errors)[0]]);
    exit();
}


try {
    if ($category === 'teacher') {
        $hexId = null;
        $stmt = $conn->prepare("SELECT id FROM teacher_hex_codes WHERE hex_code = ? LIMIT 1");
        $stmt->bind_param("s", $hex);
        $stmt->execute();
        $result = $stmt->get_result();
        if ($row = $result->fetch_assoc()) {
            $hexId = (int)$row['id'];
        }
        $stmt->close();

        if (!$hexId) {
            http_response_code(400);
            logActivity($conn, $email, 'teacher', 'signup_failed', 'Invalid HEX code');
            echo json_encode(['success' => false, 'message' => 'In valid hex']);
            exit();
        }

        $stmt = $conn->prepare("SELECT id FROM teachers WHERE hex_code_id = ? LIMIT 1");
        $stmt->bind_param("i", $hexId);
        $stmt->execute();
        $stmt->store_result();
        $alreadyUsed = $stmt->num_rows > 0;
        $stmt->close();

        if ($alreadyUsed) {
            http_response_code(400);
            logActivity($conn, $email, 'teacher', 'signup_failed', 'HEX code already used');
            echo json_encode(['success' => false, 'message' => 'In valid hex']);
            exit();
        }

        if ($validateOnly) {
            // Also check if teacher email already exists
            $stmt = $conn->prepare("SELECT id FROM teachers WHERE email = ? LIMIT 1");
            $stmt->bind_param("s", $email);
            $stmt->execute();
            $stmt->store_result();
            if ($stmt->num_rows > 0) {
                $stmt->close();
                http_response_code(400);
                echo json_encode(['success' => false, 'message' => 'User already exist']);
                exit();
            }
            $stmt->close();

            echo json_encode(['success' => true, 'message' => 'Teacher validation successful']);
            exit();
        }

        $passwordHash = hashPassword($password);
        $stmt = $conn->prepare("INSERT INTO teachers (name, email, phone, password_hash, hex_code_id) VALUES (?, ?, ?, ?, ?)");
        $stmt->bind_param("ssssi", $name, $email, $phone, $passwordHash, $hexId);
        
        if ($stmt->execute()) {
            $updateHexStmt = $conn->prepare("UPDATE teacher_hex_codes SET used_by = ? WHERE id = ?");
            $updateHexStmt->bind_param("si", $email, $hexId);
            $updateHexStmt->execute();
            $updateHexStmt->close();
            logActivity($conn, $email, 'teacher', 'signup');

            echo json_encode(['success' => true, 'message' => 'Teacher registration successful']);
        } else {
            if (strpos($stmt->error, 'Duplicate entry') !== false) {
                http_response_code(400);
                logActivity($conn, $email, 'teacher', 'signup_failed', 'User already exist');
                echo json_encode(['success' => false, 'message' => 'User already exist']);
            } else {
                http_response_code(500);
                logActivity($conn, $email, 'teacher', 'signup_failed', 'Registration failed: ' . $stmt->error);
                echo json_encode(['success' => false, 'message' => 'Registration failed: ' . $stmt->error]);
            }
        }
        $stmt->close();
    } else {
        if (!$faculty || !isset($faculty['table'])) {
            http_response_code(400);
            echo json_encode(['success' => false, 'message' => 'Invalid student faculty']);
            exit();
        }
        $table = $faculty['table'];

        if ($validateOnly) {
            // Check for duplicate student email before finishing validation
            $stmt = $conn->prepare("SELECT id FROM $table WHERE email = ? LIMIT 1");
            $stmt->bind_param("s", $email);
            $stmt->execute();
            $stmt->store_result();
            if ($stmt->num_rows > 0) {
                $stmt->close();
                http_response_code(400);
                echo json_encode(['success' => false, 'message' => 'User already exist']);
                exit();
            }
            $stmt->close();

            echo json_encode(['success' => true, 'message' => 'Student validation successful']);
            exit();
        }

        $passwordHash = hashPassword($password);
        $stmt = $conn->prepare("INSERT INTO $table (name, email, phone, password_hash) VALUES (?, ?, ?, ?)");
        $stmt->bind_param("ssss", $name, $email, $phone, $passwordHash);
        
        if ($stmt->execute()) {            logActivity($conn, $email, 'student', 'signup');

            echo json_encode(['success' => true, 'message' => 'Student registration successful']);
        } else {
            if (strpos($stmt->error, 'Duplicate entry') !== false) {
                http_response_code(400);
                logActivity($conn, $email, 'student', 'signup_failed', 'User already exist');
                echo json_encode(['success' => false, 'message' => 'User already exist']);
            } else {
                http_response_code(500);
                logActivity($conn, $email, 'student', 'signup_failed', 'Registration failed: ' . $stmt->error);
                echo json_encode(['success' => false, 'message' => 'Registration failed: ' . $stmt->error]);
            }
        }
        $stmt->close();
    }
} catch (Exception $e) {
    http_response_code(500);
    logActivity($conn, $email, $category, 'signup_failed', 'Database error: ' . $e->getMessage());
    echo json_encode(['success' => false, 'message' => 'Database error: ' . $e->getMessage()]);
}

$conn->close();
?>
