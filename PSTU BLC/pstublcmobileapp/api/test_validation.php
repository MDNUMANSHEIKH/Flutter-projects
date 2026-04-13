<?php


$testCases = [
    [
        'email' => 'ug2201053@agri.pstu.ac.bd',
        'expected' => 'valid',
        'description' => 'Valid AGRI student email'
    ],
    [
        'email' => 'ug2202012@cse.pstu.ac.bd',
        'expected' => 'valid',
        'description' => 'Valid CSE student email'
    ],
    [
        'email' => 'ug2203044@fba.pstu.ac.bd',
        'expected' => 'valid',
        'description' => 'Valid FBA student email'
    ],
    [
        'email' => 'ug2204053@fish.pstu.ac.bd',
        'expected' => 'valid',
        'description' => 'Valid Fisheries student email'
    ],
    [
        'email' => 'ug2205012@nfs.pstu.ac.bd',
        'expected' => 'valid',
        'description' => 'Valid NFS student email'
    ],
    [
        'email' => 'ug2206044@esdm.pstu.ac.bd',
        'expected' => 'valid',
        'description' => 'Valid ESDM student email'
    ],
    
    [
        'email' => 'ug2201053@cse.pstu.ac.bd',
        'expected' => 'invalid',
        'description' => 'AGRI code (01) with CSE domain'
    ],
    [
        'email' => 'ug2202012@agri.pstu.ac.bd',
        'expected' => 'invalid',
        'description' => 'CSE code (02) with AGRI domain'
    ],
    [
        'email' => 'ug2203044@fish.pstu.ac.bd',
        'expected' => 'invalid',
        'description' => 'FBA code (03) with Fisheries domain'
    ],
    
    [
        'email' => 'ug2201053@faculty.pstu.ac.bd',
        'expected' => 'invalid',
        'description' => 'Invalid domain (@faculty)'
    ],
    [
        'email' => 'student@email.com',
        'expected' => 'invalid',
        'description' => 'Non-PSTU email'
    ],
    [
        'email' => 'ug22010534@agri.pstu.ac.bd',
        'expected' => 'invalid',
        'description' => 'Wrong format (4-digit number instead of 3)'
    ],
    [
        'email' => 'ug220153@agri.pstu.ac.bd',
        'expected' => 'invalid',
        'description' => 'Missing digits'
    ],
    [
        'email' => 'john.doe@agri.pstu.ac.bd',
        'expected' => 'invalid',
        'description' => 'Missing ug prefix'
    ]
];

function validateEmail($email) {
    $facultyMap = [
        '01' => ['code' => '01', 'name' => 'AGRI', 'domain' => 'agri.pstu.ac.bd'],
        '02' => ['code' => '02', 'name' => 'CSE', 'domain' => 'cse.pstu.ac.bd'],
        '03' => ['code' => '03', 'name' => 'FBA', 'domain' => 'fba.pstu.ac.bd'],
        '04' => ['code' => '04', 'name' => 'Fisheries', 'domain' => 'fish.pstu.ac.bd'],
        '05' => ['code' => '05', 'name' => 'NFS', 'domain' => 'nfs.pstu.ac.bd'],
        '06' => ['code' => '06', 'name' => 'ESDM', 'domain' => 'esdm.pstu.ac.bd']
    ];
    
    if (!preg_match('/^ug(\d{2})(\d{2})(\d{3})@([a-z]+)\.pstu\.ac\.bd$/i', $email, $matches)) {
        return ['valid' => false, 'error' => 'Invalid email format'];
    }
    
    $year = $matches[1];
    $facultyCode = $matches[2];
    $studentNum = $matches[3];
    $domain = strtolower($matches[4]);
    
    if (!isset($facultyMap[$facultyCode])) {
        return ['valid' => false, 'error' => 'Invalid faculty code'];
    }
    
    $expectedDomain = $facultyMap[$facultyCode]['domain'];
    if ($domain !== explode('.', $expectedDomain)[0]) {
        return ['valid' => false, 'error' => 'Faculty code does not match domain'];
    }
    
    return ['valid' => true, 'faculty' => $facultyMap[$facultyCode]];
}

echo "<h2>Email Validation Test Results</h2>";
echo "<table border='1' cellpadding='10' cellspacing='0'>";
echo "<tr><th>Email</th><th>Description</th><th>Expected</th><th>Result</th><th>Status</th></tr>";

$passed = 0;
$failed = 0;

foreach ($testCases as $test) {
    $validation = validateEmail($test['email']);
    $result = $validation['valid'] ? 'valid' : 'invalid';
    $status = ($result === $test['expected']) ? '✓ PASS' : '✗ FAIL';
    
    if ($result === $test['expected']) {
        $passed++;
    } else {
        $failed++;
    }
    
    echo "<tr>";
    echo "<td><code>{$test['email']}</code></td>";
    echo "<td>{$test['description']}</td>";
    echo "<td><strong>{$test['expected']}</strong></td>";
    echo "<td><strong>{$result}</strong></td>";
    echo "<td style='color: " . ($status === '✓ PASS' ? 'green' : 'red') . ";'>{$status}</td>";
    echo "</tr>";
}

echo "</table>";
echo "<h3>Summary: {$passed} passed, {$failed} failed out of " . count($testCases) . " tests</h3>";
?>
