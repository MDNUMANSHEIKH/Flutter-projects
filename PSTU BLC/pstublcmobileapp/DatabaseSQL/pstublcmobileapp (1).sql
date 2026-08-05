-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Host: localhost
-- Generation Time: Mar 30, 2026 at 08:59 PM
-- Server version: 10.4.32-MariaDB
-- PHP Version: 8.2.12

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `pstublcmobileapp`
--

-- --------------------------------------------------------

--
-- Table structure for table `courses`
--

CREATE TABLE `courses` (
  `id` int(11) NOT NULL,
  `course_code` varchar(20) NOT NULL,
  `course_name` varchar(100) NOT NULL,
  `session` varchar(20) NOT NULL,
  `faculty_code` char(2) NOT NULL,
  `teacher_id` int(11) NOT NULL,
  `status` enum('Public','Private') DEFAULT 'Public',
  `created_at` datetime DEFAULT current_timestamp(),
  `is_private` tinyint(1) DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

--
-- Dumping data for table `courses`
--

INSERT INTO `courses` (`id`, `course_code`, `course_name`, `session`, `faculty_code`, `teacher_id`, `status`, `created_at`, `is_private`) VALUES
(1, 'CCE 311', 'Microprocessor', '2022-23', '02', 1, 'Public', '2026-03-03 14:59:32', 0);

-- --------------------------------------------------------

--
-- Table structure for table `enrollments`
--

CREATE TABLE `enrollments` (
  `id` int(11) NOT NULL,
  `student_email` varchar(255) NOT NULL,
  `course_id` int(11) NOT NULL,
  `enrolled_at` timestamp NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `attendance_sessions`
--

CREATE TABLE `attendance_sessions` (
  `id` int(11) NOT NULL,
  `course_id` int(11) NOT NULL,
  `session_date` datetime NOT NULL,
  `session_end` datetime NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `is_private` tinyint(1) DEFAULT 0,
  `is_dynamic_qr` tinyint(1) DEFAULT 0,
  `qr_interval` int(11) DEFAULT NULL,
  `qr_code_hex` varchar(64) DEFAULT NULL,
  `notified` tinyint(1) DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

--
-- Dumping data for table `enrollments`
--

INSERT INTO `enrollments` (`id`, `student_email`, `course_id`, `enrolled_at`) VALUES
(1, 'ug2202053@cse.pstu.ac.bd', 1, '2026-03-03 21:00:00');

-- --------------------------------------------------------

--
-- Table structure for table `faculties`
--

CREATE TABLE `faculties` (
  `faculty_code` char(2) NOT NULL,
  `faculty_name` varchar(30) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

--
-- Dumping data for table `faculties`
--

INSERT INTO `faculties` (`faculty_code`, `faculty_name`) VALUES
('01', 'AGRI'),
('02', 'CSE'),
('03', 'FBA'),
('04', 'FISHERIES'),
('05', 'NFS'),
('06', 'ESDM');

-- --------------------------------------------------------

--
-- Table structure for table `students_agri`
--

CREATE TABLE `students_agri` (
  `id` int(11) NOT NULL,
  `name` varchar(100) NOT NULL,
  `email` varchar(150) NOT NULL,
  `phone` varchar(15) NOT NULL,
  `password_hash` varchar(255) NOT NULL,
  `created_at` datetime DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `students_cse`
--

CREATE TABLE `students_cse` (
  `id` int(11) NOT NULL,
  `name` varchar(100) NOT NULL,
  `email` varchar(150) NOT NULL,
  `phone` varchar(15) NOT NULL,
  `password_hash` varchar(255) NOT NULL,
  `created_at` datetime DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

--
-- Dumping data for table `students_cse`
--

INSERT INTO `students_cse` (`id`, `name`, `email`, `phone`, `password_hash`, `created_at`) VALUES
(1, 'gtrfd', 'ug2202053@cse.pstu.ac.bd', '01711111161', 'Q0Z+pogvk66jnSUtkTX3fT8J8Fi01J1kqE8DRmGAXdw=', '2025-12-27 21:30:57');

-- --------------------------------------------------------

--
-- Table structure for table `students_esdm`
--

CREATE TABLE `students_esdm` (
  `id` int(11) NOT NULL,
  `name` varchar(100) NOT NULL,
  `email` varchar(150) NOT NULL,
  `phone` varchar(15) NOT NULL,
  `password_hash` varchar(255) NOT NULL,
  `created_at` datetime DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `students_fba`
--

CREATE TABLE `students_fba` (
  `id` int(11) NOT NULL,
  `name` varchar(100) NOT NULL,
  `email` varchar(150) NOT NULL,
  `phone` varchar(15) NOT NULL,
  `password_hash` varchar(255) NOT NULL,
  `created_at` datetime DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `students_fish`
--

CREATE TABLE `students_fish` (
  `id` int(11) NOT NULL,
  `name` varchar(100) NOT NULL,
  `email` varchar(150) NOT NULL,
  `phone` varchar(15) NOT NULL,
  `password_hash` varchar(255) NOT NULL,
  `created_at` datetime DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `students_nfs`
--

CREATE TABLE `students_nfs` (
  `id` int(11) NOT NULL,
  `name` varchar(100) NOT NULL,
  `email` varchar(150) NOT NULL,
  `phone` varchar(15) NOT NULL,
  `password_hash` varchar(255) NOT NULL,
  `created_at` datetime DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `teachers`
--

CREATE TABLE `teachers` (
  `id` int(11) NOT NULL,
  `name` varchar(100) NOT NULL,
  `email` varchar(150) NOT NULL,
  `phone` varchar(15) NOT NULL,
  `password_hash` varchar(255) NOT NULL,
  `hex_code_id` int(11) NOT NULL,
  `created_at` datetime DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

--
-- Dumping data for table `teachers`
--

INSERT INTO `teachers` (`id`, `name`, `email`, `phone`, `password_hash`, `hex_code_id`, `created_at`) VALUES
(1, 'gvfdc', 'pipoolxox@gmail.com', '01711111161', 'dMP+TMcO0YgO/Zd820gTrO/rCTiP/xvFPgGKlTdFpdI=', 1, '2025-12-27 21:32:31');

-- --------------------------------------------------------

--
-- Table structure for table `teacher_hex_codes`
--

CREATE TABLE `teacher_hex_codes` (
  `id` int(11) NOT NULL,
  `hex_code` varchar(32) NOT NULL,
  `created_at` datetime DEFAULT current_timestamp(),
  `used_by` varchar(150) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

--
-- Dumping data for table `teacher_hex_codes`
--

INSERT INTO `teacher_hex_codes` (`id`, `hex_code`, `created_at`, `used_by`) VALUES
(1, 'A1B2C3D4E5F60789AABBCCDDEEFF0011', '2025-12-28 05:26:47', 'pipoolxox@gmail.com'),
(2, '11223344556677889900AABBCCDDEEFF', '2025-12-28 05:26:47', NULL),
(3, 'ABCDEF1234567890ABCDEF1234567890', '2025-12-28 05:26:47', NULL),
(4, 'ZXCVBNMASDFGHJKLQWERTYUIOP123456', '2025-12-28 05:26:47', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `activity_logs`
--

CREATE TABLE `activity_logs` (
  `id` int(11) NOT NULL,
  `user_email` varchar(150) DEFAULT NULL,
  `user_role` varchar(20) DEFAULT NULL,
  `action` varchar(120) NOT NULL COMMENT 'login, signup, signout, course_create, account_delete, course_delete, course_enroll, course_unenroll, course_public, course_private',
  `details` text DEFAULT NULL,
  `created_at` datetime DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Indexes for dumped tables
--

--
-- Indexes for table `courses`
--
ALTER TABLE `courses`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uniq_course` (`course_code`,`session`),
  ADD KEY `fk_course_teacher` (`teacher_id`),
  ADD KEY `fk_course_faculty` (`faculty_code`);

--
-- Indexes for table `enrollments`
--
ALTER TABLE `enrollments`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uniq_enrollment` (`student_email`,`course_id`),
  ADD KEY `fk_enrollment_course` (`course_id`);

--
-- Indexes for table `faculties`
--
ALTER TABLE `faculties`
  ADD PRIMARY KEY (`faculty_code`);

--
-- Indexes for table `students_agri`
--
ALTER TABLE `students_agri`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `email` (`email`);

--
-- Indexes for table `students_cse`
--
ALTER TABLE `students_cse`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `email` (`email`);

--
-- Indexes for table `students_esdm`
--
ALTER TABLE `students_esdm`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `email` (`email`);

--
-- Indexes for table `students_fba`
--
ALTER TABLE `students_fba`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `email` (`email`);

--
-- Indexes for table `students_fish`
--
ALTER TABLE `students_fish`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `email` (`email`);

--
-- Indexes for table `students_nfs`
--
ALTER TABLE `students_nfs`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `email` (`email`);

--
-- Indexes for table `teachers`
--
ALTER TABLE `teachers`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `email` (`email`),
  ADD UNIQUE KEY `hex_code_id` (`hex_code_id`);

--
-- Indexes for table `teacher_hex_codes`
--
ALTER TABLE `teacher_hex_codes`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `hex_code` (`hex_code`);

--
-- Indexes for table `activity_logs`
--
ALTER TABLE `activity_logs`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_user_email` (`user_email`),
  ADD KEY `idx_action` (`action`),
  ADD KEY `idx_created_at` (`created_at`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `courses`
--
ALTER TABLE `courses`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `enrollments`
--
ALTER TABLE `enrollments`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `students_agri`
--
ALTER TABLE `students_agri`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `students_cse`
--
ALTER TABLE `students_cse`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `students_esdm`
--
ALTER TABLE `students_esdm`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `students_fba`
--
ALTER TABLE `students_fba`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `students_fish`
--
ALTER TABLE `students_fish`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `students_nfs`
--
ALTER TABLE `students_nfs`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `teachers`
--
ALTER TABLE `teachers`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `teacher_hex_codes`
--
ALTER TABLE `teacher_hex_codes`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT for table `activity_logs`
--
ALTER TABLE `activity_logs`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- Constraints for dumped tables
--

--
-- Constraints for table `courses`
--
ALTER TABLE `courses`
  ADD CONSTRAINT `fk_course_faculty` FOREIGN KEY (`faculty_code`) REFERENCES `faculties` (`faculty_code`) ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_course_teacher` FOREIGN KEY (`teacher_id`) REFERENCES `teachers` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `enrollments`
--
ALTER TABLE `enrollments`
  ADD CONSTRAINT `fk_enrollment_course` FOREIGN KEY (`course_id`) REFERENCES `courses` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `teachers`
--
ALTER TABLE `teachers`
  ADD CONSTRAINT `fk_teacher_hex` FOREIGN KEY (`hex_code_id`) REFERENCES `teacher_hex_codes` (`id`) ON UPDATE CASCADE;

--
-- Constraints for table `attendance_sessions`
--
ALTER TABLE `attendance_sessions`
  ADD CONSTRAINT `fk_attendance_course` FOREIGN KEY (`course_id`) REFERENCES `courses` (`id`) ON DELETE CASCADE;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
