import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pstublc/signup_page.dart';
import 'package:pstublc/student_dashboard_page.dart';
import 'package:pstublc/teacher_dashboard_page.dart';
import 'package:pstublc/services/api_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _apiService = ApiService();
  bool _isLoading = false;
  bool _rememberMe = false;
  String _statusText = '';
  Color _statusColor = Colors.transparent;

  // OTP Support
  bool _showOtpField = false;
  final List<TextEditingController> _otpControllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());
  Timer? _resendTimer;
  int _resendSeconds = 60;
  String _maskedEmail = '';
  String _loginRole = ''; // Temporarily store role for final transition
  String? _appwriteUserId;
  DateTime? _otpSentTime;
  Map<String, dynamic>? _loginData;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    for (var c in _otpControllers) {
      c.dispose();
    }
    for (var f in _otpFocusNodes) {
      f.dispose();
    }
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    _resendSeconds = 60;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_resendSeconds > 0) {
          _resendSeconds--;
        } else {
          _resendTimer?.cancel();
        }
      });
    });
  }

  String _maskEmail(String email) {
    if (!email.contains('@')) return email;
    final parts = email.split('@');
    final name = parts[0];
    final domain = parts[1];
    if (name.length <= 3) return email;
    final visible = name.substring(name.length - 3);
    return '*******$visible@$domain';
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showStatus('Please fill in all fields', false);
      return;
    }

    setState(() => _isLoading = true);
    try {
      debugPrint('Logging in with $email');
      final result = await _apiService.login(email, password);

      if (!mounted) return;

      if (result['success'] == true) {
        debugPrint('Database match success. Sending OTP...');
        _loginData = result; // Store for final session save
        final otpResult = await _apiService.sendAppwriteOtp(email);

        if (otpResult['success'] == true) {
          setState(() {
            _showOtpField = true;
            _maskedEmail = _maskEmail(email);
            _loginRole = (result['role'] ?? 'teacher').toString();
            _appwriteUserId = otpResult['userId'];
            _otpSentTime = DateTime.now();
            _statusText = ''; // Clear status when switching to OTP field
            for (var c in _otpControllers) {
              c.clear();
            }
          });
          _startResendTimer();
          _showStatus('OTP sent to your email', true, showSnackbar: false);
        } else {
          _showStatus(otpResult['message'] ?? 'Failed to send OTP', false);
        }
      } else {
        _showStatus(result['message'] ?? 'Login failed', false);
      }
    } catch (e) {
      debugPrint('Exception in _handleLogin: $e');
      _showStatus('An unexpected error occurred: $e', false);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleOtpVerification() async {
    final otp = _otpControllers.map((c) => c.text).join();
    if (otp.length < 6) {
      _showStatus('Please enter 6-digit OTP', false);
      return;
    }

    // Requirement: Check if 1 minute has passed
    if (_otpSentTime != null &&
        DateTime.now().difference(_otpSentTime!).inSeconds > 60) {
      _showStatus('Invalid OTP (Expired after 1 minute)', false);
      return;
    }

    setState(() => _isLoading = true);
    try {
      debugPrint('Verifying OTP for $_appwriteUserId');
      final result = await _apiService.verifyAppwriteOtp(
        _appwriteUserId!, 
        otp, 
        userData: _loginData!,
      );
      
      if (!mounted) return;

      if (result['success'] == true) {
        _showStatus('Verification successful', true);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => _loginRole == 'student'
                ? const StudentDashboardPage()
                : const TeacherDashboardPage(),
          ),
        );
      } else {
        _showStatus('invalid otp', false, showSnackbar: false);
      }
    } catch (e) {
      debugPrint('Exception in _handleOtpVerification: $e');
      _showStatus('invalid otp', false, showSnackbar: false);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleResendOtp() async {
    if (_resendSeconds > 0) return;

    setState(() => _isLoading = true);
    final email = _emailController.text.trim().toLowerCase();
    final result = await _apiService.sendAppwriteOtp(email);
    setState(() => _isLoading = false);

    if (!mounted) return;

    if (result['success'] == true) {
      setState(() {
        _appwriteUserId = result['userId'];
        _otpSentTime = DateTime.now();
      });
      _startResendTimer();
      _showStatus('OTP resent to your email', true, showSnackbar: false);
    } else {
      _showStatus('Failed to resend OTP', false);
    }
  }

  Future<void> _showResetDialog() async {
    final emailController = TextEditingController(
      text: _emailController.text.trim(),
    );
    final newPasswordController = TextEditingController();
    final confirmController = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            TextField(
              controller: newPasswordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New Password'),
            ),
            TextField(
              controller: confirmController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirm Password'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final email = emailController.text.trim().toLowerCase();
    final pass = newPasswordController.text;
    final confirm = confirmController.text;

    if (email.isEmpty || pass.isEmpty || confirm.isEmpty) {
      _showStatus('All fields are required', false);
      return;
    }
    if (pass.length < 3) {
      _showStatus('Password must be at least 3 characters', false);
      return;
    }
    if (pass != confirm) {
      _showStatus('Passwords do not match', false);
      return;
    }

    final result = await _apiService.resetPassword(email, pass);
    _showStatus(
      result['message'] ??
          (result['success'] == true
              ? 'Password reset successful'
              : 'Reset failed'),
      result['success'] == true,
    );
  }

  Future<void> _showApiConfigDialog() async {
    final current = await _apiService.getBaseUrl();
    if (!mounted) return;

    final controller = TextEditingController(text: current);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Server API URL'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'http://10.0.2.2/PSTU%20BLC/api',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _apiService.setBaseUrl(controller.text);
      if (!mounted) return;
      _showStatus('Server URL updated', true);
    }
  }

  void _showStatus(String text, bool success, {bool showSnackbar = true}) {
    if (!mounted) return;
    setState(() {
      _statusText = text;
      _statusColor = success ? Colors.green : Colors.red;
    });
    if (showSnackbar) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _refreshPage() async {
    setState(() {
      _statusText = '';
      _statusColor = Colors.transparent;
    });
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PSTU BLC Login'),
        actions: [
          IconButton(
            onPressed: _showApiConfigDialog,
            icon: const Icon(Icons.settings_ethernet),
            tooltip: 'Configure server URL',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshPage,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Image.asset('img/rrr.png', height: 100),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color.fromARGB(
                        255,
                        134,
                        222,
                        80,
                      ).withOpacity(0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                  border: Border.all(
                    color: const Color.fromARGB(255, 134, 222, 80),
                    width: 2,
                  ),
                ),
                child: const Column(
                  children: [
                    Text(
                      'Patuakhali Science and Technology University',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'PSTU BLC',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color.fromARGB(255, 134, 222, 80),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              _showOtpField ? _buildOtpForm() : _buildLoginForm(),
              if (!_showOtpField && _statusText.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  _statusText,
                  style: TextStyle(
                    color: _statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passwordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Checkbox(
                  value: _rememberMe,
                  onChanged: (value) =>
                      setState(() => _rememberMe = value ?? false),
                ),
                const Text('Remember me'),
              ],
            ),
            TextButton(
              onPressed: _showResetDialog,
              child: const Text('Forgot password?'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 46,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleLogin,
            child: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Login'),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("Don't have an account? "),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SignupPage()),
                );
              },
              child: const Text('Sign up'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOtpForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'OTP Verification',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Text(
          'We have sent a 6-digit code to\n$_maskedEmail',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 30),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(6, (index) {
            return SizedBox(
              width: 45,
              height: 55,
              child: TextField(
                controller: _otpControllers[index],
                focusNode: _otpFocusNodes[index],
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                maxLength: 1,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                decoration: const InputDecoration(
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  if (_statusText == 'invalid otp') {
                    setState(() => _statusText = '');
                  } else {
                    setState(() {}); // Trigger rebuild to update button state
                  }
                  if (value.isNotEmpty && index < 5) {
                    _otpFocusNodes[index + 1].requestFocus();
                  } else if (value.isEmpty && index > 0) {
                    _otpFocusNodes[index - 1].requestFocus();
                  }
                },
              ),
            );
          }),
        ),
        const SizedBox(height: 24),
        if (_statusText.isNotEmpty)
          Center(
            child: Text(
              _statusText,
              style: TextStyle(
                color: _statusColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          )
        else if (_resendSeconds > 0)
          const Center(
            child: Text(
              'OTP sent to your email',
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        Center(
          child: TextButton(
            onPressed: _resendSeconds > 0 ? null : _handleResendOtp,
            child: Text(
              _resendSeconds > 0
                  ? 'Resend OTP in $_resendSeconds s'
                  : 'Resend OTP',
              style: TextStyle(
                color: _resendSeconds > 0
                    ? Colors.grey
                    : Theme.of(context).primaryColor,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _showOtpField = false),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                ),
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton(
                onPressed:
                    (_isLoading || _otpControllers.any((c) => c.text.isEmpty))
                    ? null
                    : _handleOtpVerification,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Verify'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
