-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Host: localhost
-- Generation Time: Apr 25, 2026 at 03:36 PM
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
-- Table structure for table `activity_logs`
--

CREATE TABLE `activity_logs` (
  `id` int(11) NOT NULL,
  `user_email` varchar(150) DEFAULT NULL,
  `user_role` varchar(20) DEFAULT NULL,
  `action` varchar(120) NOT NULL,
  `details` text DEFAULT NULL,
  `created_at` datetime DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `activity_logs`
--

INSERT INTO `activity_logs` (`id`, `user_email`, `user_role`, `action`, `details`, `created_at`) VALUES
(1, 'rgrgr', 'teacher', 'login_failed', 'Teacher not found. Password provided.', '2026-04-25 08:00:11'),
(2, 'pipoolxox@gmail.com', 'teacher', 'login_failed', 'Teacher not found. Password provided.', '2026-04-25 08:00:24'),
(3, 'pipoolxox@gmail.com', 'teacher', 'signup', NULL, '2026-04-25 08:01:42'),
(4, 'pipoolxox@gmail.com', 'teacher', 'signout', NULL, '2026-04-25 08:03:42'),
(5, 'ug2202053@cse.pstu.ac.bd', 'student', 'signup', NULL, '2026-04-25 08:04:37'),
(6, 'pipoolxox@gmail.com', 'teacher', 'login_success', 'Correct password verified', '2026-04-25 08:06:06'),
(7, 'ug2202053@cse.pstu.ac.bd', 'teacher', 'signout', NULL, '2026-04-25 08:10:37'),
(8, 'pipoolxox@gmail.com', 'teacher', 'login_success', 'Correct password verified', '2026-04-25 08:33:21'),
(9, 'pipoolxox@gmail.com', 'teacher', 'course_create', 'Course Code: CIT 311', '2026-04-25 08:34:51');

-- --------------------------------------------------------

--
-- Table structure for table `Assignment`
--

CREATE TABLE `Assignment` (
  `id` int(11) NOT NULL,
  `course_id` int(11) NOT NULL,
  `teacher_email` varchar(100) NOT NULL,
  `title` varchar(255) NOT NULL,
  `description` text NOT NULL,
  `due_date` datetime NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `edited_at` datetime DEFAULT NULL,
  `is_private` tinyint(1) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `AssignmentSubmission`
--

CREATE TABLE `AssignmentSubmission` (
  `id` int(11) NOT NULL,
  `assignment_id` int(11) NOT NULL,
  `student_email` varchar(100) NOT NULL,
  `file_ids` text NOT NULL,
  `file_names` text NOT NULL,
  `is_turned_in` tinyint(1) DEFAULT 0,
  `turned_in_at` datetime DEFAULT NULL,
  `submitted_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `assignment_comment_messages`
--

CREATE TABLE `assignment_comment_messages` (
  `id` int(11) NOT NULL,
  `assignment_id` int(11) NOT NULL,
  `course_id` int(11) NOT NULL,
  `sender_email` varchar(100) NOT NULL,
  `sender_name` varchar(120) NOT NULL,
  `sender_role` varchar(20) NOT NULL,
  `target_audience` varchar(20) NOT NULL DEFAULT 'everyone',
  `target_student_email` varchar(100) DEFAULT NULL,
  `message` text NOT NULL,
  `reply_to_message_id` int(11) DEFAULT NULL,
  `reply_to_sender_name` varchar(120) DEFAULT NULL,
  `reply_to_message` text DEFAULT NULL,
  `is_edited` tinyint(1) NOT NULL DEFAULT 0,
  `edited_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `attendance_records`
--

CREATE TABLE `attendance_records` (
  `id` int(11) NOT NULL,
  `session_id` int(11) NOT NULL,
  `student_email` varchar(255) NOT NULL,
  `marked_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

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
  `is_private` tinyint(1) DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

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
(25, 'CIT 311', 'Microprocessor', '2022-23', '02', 3, 'Public', '2026-04-25 08:34:51', 1);

-- --------------------------------------------------------

--
-- Table structure for table `course_discussion_messages`
--

CREATE TABLE `course_discussion_messages` (
  `id` int(11) NOT NULL,
  `course_id` int(11) NOT NULL,
  `sender_email` varchar(100) NOT NULL,
  `sender_name` varchar(120) NOT NULL,
  `sender_role` varchar(20) NOT NULL,
  `target_audience` varchar(20) NOT NULL DEFAULT 'everyone',
  `target_student_email` varchar(100) DEFAULT NULL,
  `message` text NOT NULL,
  `reply_to_message_id` int(11) DEFAULT NULL,
  `reply_to_sender_name` varchar(120) DEFAULT NULL,
  `reply_to_message` text DEFAULT NULL,
  `is_edited` tinyint(1) NOT NULL DEFAULT 0,
  `edited_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `course_discussion_messages`
--

INSERT INTO `course_discussion_messages` (`id`, `course_id`, `sender_email`, `sender_name`, `sender_role`, `target_audience`, `target_student_email`, `message`, `reply_to_message_id`, `reply_to_sender_name`, `reply_to_message`, `is_edited`, `edited_at`, `created_at`) VALUES
(48, 25, 'pipoolxox@gmail.com', 'Rana', 'teacher', 'everyone', '', 'hi', NULL, NULL, NULL, 0, NULL, '2026-04-25 19:35:09');

-- --------------------------------------------------------

--
-- Table structure for table `course_results`
--

CREATE TABLE `course_results` (
  `id` int(11) NOT NULL,
  `course_id` int(11) NOT NULL,
  `teacher_id` int(11) NOT NULL,
  `file_name` varchar(255) NOT NULL,
  `file_path` varchar(255) NOT NULL,
  `file_type` varchar(120) DEFAULT NULL,
  `file_size` int(11) DEFAULT 0,
  `is_private` tinyint(1) NOT NULL DEFAULT 1,
  `uploaded_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `enrollments`
--

CREATE TABLE `enrollments` (
  `id` int(11) NOT NULL,
  `student_email` varchar(255) NOT NULL,
  `course_id` int(11) NOT NULL,
  `enrolled_at` timestamp NULL DEFAULT current_timestamp(),
  `is_blocked` tinyint(1) DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

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
-- Table structure for table `notifications`
--

CREATE TABLE `notifications` (
  `id` int(11) NOT NULL,
  `student_email` varchar(100) NOT NULL,
  `course_id` int(11) DEFAULT NULL,
  `title` varchar(100) DEFAULT NULL,
  `message` text DEFAULT NULL,
  `type` varchar(50) DEFAULT NULL,
  `is_read` tinyint(4) DEFAULT 0,
  `created_at` datetime DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

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
(11, 'Numan', 'ug2202053@cse.pstu.ac.bd', '01732646578', 'R5FlKYYmhCcCuFNsZffUH+6tPNaENo27hdPfas1RdNs=', '2026-04-25 08:04:37');

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
(3, 'Rana', 'pipoolxox@gmail.com', '01746395734', '6YzOqveHFfGHw0VD9iLQeGCbJWoycVQ/ctERzOJrsYc=', 1, '2026-04-25 08:01:42');

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

--
-- Indexes for dumped tables
--

--
-- Indexes for table `activity_logs`
--
ALTER TABLE `activity_logs`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_user_email` (`user_email`),
  ADD KEY `idx_action` (`action`),
  ADD KEY `idx_created_at` (`created_at`);

--
-- Indexes for table `Assignment`
--
ALTER TABLE `Assignment`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_assignment_course_created` (`course_id`,`created_at`),
  ADD KEY `idx_assignment_teacher` (`teacher_email`),
  ADD KEY `idx_assignment_due_date` (`due_date`);

--
-- Indexes for table `AssignmentSubmission`
--
ALTER TABLE `AssignmentSubmission`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unq_student_assignment` (`student_email`,`assignment_id`),
  ADD KEY `idx_submission_assignment` (`assignment_id`),
  ADD KEY `idx_submission_student` (`student_email`);

--
-- Indexes for table `assignment_comment_messages`
--
ALTER TABLE `assignment_comment_messages`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_assignment_created` (`assignment_id`,`created_at`),
  ADD KEY `idx_assignment_course` (`course_id`),
  ADD KEY `idx_sender_email` (`sender_email`),
  ADD KEY `idx_sender_role` (`sender_role`),
  ADD KEY `idx_target_audience` (`target_audience`),
  ADD KEY `idx_target_student_email` (`target_student_email`);

--
-- Indexes for table `attendance_records`
--
ALTER TABLE `attendance_records`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_participation` (`session_id`,`student_email`);

--
-- Indexes for table `attendance_sessions`
--
ALTER TABLE `attendance_sessions`
  ADD PRIMARY KEY (`id`),
  ADD KEY `fk_attendance_course` (`course_id`);

--
-- Indexes for table `courses`
--
ALTER TABLE `courses`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uniq_course` (`course_code`,`session`),
  ADD KEY `fk_course_teacher` (`teacher_id`),
  ADD KEY `fk_course_faculty` (`faculty_code`);

--
-- Indexes for table `course_discussion_messages`
--
ALTER TABLE `course_discussion_messages`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_course_created` (`course_id`,`created_at`),
  ADD KEY `idx_sender_email` (`sender_email`),
  ADD KEY `idx_sender_role` (`sender_role`);

--
-- Indexes for table `course_results`
--
ALTER TABLE `course_results`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_course_id` (`course_id`),
  ADD KEY `idx_teacher_id` (`teacher_id`);

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
-- Indexes for table `notifications`
--
ALTER TABLE `notifications`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_student_email` (`student_email`),
  ADD KEY `idx_is_read` (`is_read`),
  ADD KEY `idx_created_at` (`created_at`);

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
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `activity_logs`
--
ALTER TABLE `activity_logs`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=10;

--
-- AUTO_INCREMENT for table `Assignment`
--
ALTER TABLE `Assignment`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=14;

--
-- AUTO_INCREMENT for table `AssignmentSubmission`
--
ALTER TABLE `AssignmentSubmission`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT for table `assignment_comment_messages`
--
ALTER TABLE `assignment_comment_messages`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=31;

--
-- AUTO_INCREMENT for table `attendance_records`
--
ALTER TABLE `attendance_records`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=31;

--
-- AUTO_INCREMENT for table `attendance_sessions`
--
ALTER TABLE `attendance_sessions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=37;

--
-- AUTO_INCREMENT for table `courses`
--
ALTER TABLE `courses`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=26;

--
-- AUTO_INCREMENT for table `course_discussion_messages`
--
ALTER TABLE `course_discussion_messages`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=49;

--
-- AUTO_INCREMENT for table `course_results`
--
ALTER TABLE `course_results`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `enrollments`
--
ALTER TABLE `enrollments`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=17;

--
-- AUTO_INCREMENT for table `notifications`
--
ALTER TABLE `notifications`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=247;

--
-- AUTO_INCREMENT for table `students_agri`
--
ALTER TABLE `students_agri`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `students_cse`
--
ALTER TABLE `students_cse`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=12;

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
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT for table `teacher_hex_codes`
--
ALTER TABLE `teacher_hex_codes`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- Constraints for dumped tables
--

--
-- Constraints for table `attendance_records`
--
ALTER TABLE `attendance_records`
  ADD CONSTRAINT `attendance_records_ibfk_1` FOREIGN KEY (`session_id`) REFERENCES `attendance_sessions` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `attendance_sessions`
--
ALTER TABLE `attendance_sessions`
  ADD CONSTRAINT `fk_attendance_course` FOREIGN KEY (`course_id`) REFERENCES `courses` (`id`) ON DELETE CASCADE;

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
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
