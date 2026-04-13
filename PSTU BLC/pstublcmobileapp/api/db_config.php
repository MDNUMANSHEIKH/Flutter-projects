<?php

define('DB_HOST', '127.0.0.1');
define('DB_USER', 'root');
define('DB_PASS', '');
define('DB_NAME', 'pstublcmobileapp');


define('ENCRYPTION_KEY', 'pstu_blc_secret_key_12345');


$conn = new mysqli(DB_HOST, DB_USER, DB_PASS, DB_NAME);


if ($conn->connect_error) {
    die(json_encode(['success' => false, 'message' => 'Database connection failed: ' . $conn->connect_error]));
}


$conn->set_charset("utf8");


function encryptPassword($password) {
    $key = hash('sha256', ENCRYPTION_KEY, true);
    $iv = openssl_random_pseudo_bytes(16);
    $encrypted = openssl_encrypt($password, 'AES-256-CBC', $key, OPENSSL_RAW_DATA, $iv);
    return base64_encode($iv . $encrypted);
}


function decryptPassword($encryptedPassword) {
    try {
        $key = hash('sha256', ENCRYPTION_KEY, true);
        $data = base64_decode($encryptedPassword);
        $iv = substr($data, 0, 16);
        $encrypted = substr($data, 16);
        return openssl_decrypt($encrypted, 'AES-256-CBC', $key, OPENSSL_RAW_DATA, $iv);
    } catch (Exception $e) {
        return '';
    }
}


$facultyMap = [
    '01' => ['code' => '01', 'name' => 'AGRI', 'domain' => 'agri.pstu.ac.bd', 'table' => 'students_agri'],
    '02' => ['code' => '02', 'name' => 'CSE', 'domain' => 'cse.pstu.ac.bd', 'table' => 'students_cse'],
    '03' => ['code' => '03', 'name' => 'FBA', 'domain' => 'fba.pstu.ac.bd', 'table' => 'students_fba'],
    '04' => ['code' => '04', 'name' => 'Fisheries', 'domain' => 'fish.pstu.ac.bd', 'table' => 'students_fish'],
    '05' => ['code' => '05', 'name' => 'NFS', 'domain' => 'nfs.pstu.ac.bd', 'table' => 'students_nfs'],
    '06' => ['code' => '06', 'name' => 'ESDM', 'domain' => 'esdm.pstu.ac.bd', 'table' => 'students_esdm']
];
?>
