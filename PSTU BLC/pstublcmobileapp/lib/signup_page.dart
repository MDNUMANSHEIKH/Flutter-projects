import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pstublc/login_page.dart';
import 'package:pstublc/services/api_service.dart';
import 'package:pstublc/student_dashboard_page.dart';
import 'package:pstublc/teacher_dashboard_page.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _hexController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String _category = 'student';
  bool _isLoading = false;
  String _statusText = '';
  Color _statusColor = Colors.transparent;

  // OTP Support
  bool _showOtpField = false;
  final List<TextEditingController> _otpControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());
  Timer? _resendTimer;
  int _resendSeconds = 60;
  String _maskedEmail = '';
  String? _appwriteUserId;
  DateTime? _otpSentTime;
  Map<String, dynamic>? _signupPayload;

  final ApiService _apiService = ApiService();

  static final RegExp _studentEmailRegExp = RegExp(
    r'^ug(\d{2})(\d{2})(\d{3})@([a-z]+)\.pstu\.ac\.bd$',
    caseSensitive: false,
  );

  static const Map<String, String> _facultyDomainByCode = {
    '01': 'agri',
    '02': 'cse',
    '03': 'fba',
    '04': 'fish',
    '05': 'nfs',
    '06': 'esdm',
  };

  String? _validateStudentEmail(String email) {
    final match = _studentEmailRegExp.firstMatch(email.toLowerCase());
    if (match == null) {
      return 'Invalid format. Use ugYYFFNNN@faculty.pstu.ac.bd';
    }

    final facultyCode = match.group(2)!;
    final domainPart = match.group(4)!;
    final expectedDomain = _facultyDomainByCode[facultyCode];

    if (expectedDomain == null) {
      return 'Invalid faculty code. Must be 01-06';
    }

    if (domainPart != expectedDomain) {
      return 'Faculty code does not match domain';
    }

    return null;
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

  Future<void> _handleSignup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    _signupPayload = {
      'name': _nameController.text.trim(),
      'email': _emailController.text.trim().toLowerCase(),
      'phone': _phoneController.text.trim(),
      'category': _category,
      'hex': _hexController.text.trim(),
      'password': _passwordController.text,
      'confirmPassword': _confirmPasswordController.text,
    };

    try {
      final validateResult = await _apiService.validateSignup(_signupPayload!);

      if (!mounted) return;

      if (validateResult['success'] == true) {
        final email = _signupPayload!['email'];
        final otpResult = await _apiService.sendAppwriteOtp(email);

        if (otpResult['success'] == true) {
          setState(() {
            _showOtpField = true;
            _maskedEmail = _maskEmail(email);
            _appwriteUserId = otpResult['userId'];
            _otpSentTime = DateTime.now();
            _statusText = '';
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
        final message = validateResult['message']?.toString() ?? 'Validation failed';
        _showStatus(message, false, showSnackbar: false);
      }
    } catch (e) {
      _showStatus('An error occurred: $e', false);
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

    if (_otpSentTime != null &&
        DateTime.now().difference(_otpSentTime!).inSeconds > 60) {
      _showStatus('invalid otp', false, showSnackbar: false);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final result = await _apiService.verifyAppwriteOtp(
        _appwriteUserId!,
        otp,
        userData: _signupPayload!, // This will be used to save session on success
      );

      if (!mounted) return;

      if (result['success'] == true) {
        // Now perform the ACTUAL signup in DB
        final signupResult = await _apiService.signup(_signupPayload!);
        
        if (signupResult['success'] == true) {
          _showStatus('Registration successful', true);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => _category == 'student'
                  ? const StudentDashboardPage()
                  : const TeacherDashboardPage(),
            ),
          );
        } else {
          _showStatus(signupResult['message'] ?? 'Signup failed', false);
        }
      } else {
        _showStatus('invalid otp', false, showSnackbar: false);
      }
    } catch (e) {
      _showStatus('invalid otp', false, showSnackbar: false);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    _resendSeconds = 60;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
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
    final parts = email.split('@');
    if (parts.length != 2) return email;
    final user = parts[0];
    final domain = parts[1];
    if (user.length <= 3) return email;
    return '${user.substring(0, user.length - 3)}***@$domain';
  }

  Future<void> _refreshPage() async {
    setState(() {
      _isLoading = false;
      _statusText = '';
      _statusColor = Colors.transparent;
    });
    _formKey.currentState?.reset();
    _nameController.clear();
    _emailController.clear();
    _phoneController.clear();
    _hexController.clear();
    _passwordController.clear();
    _confirmPasswordController.clear();
    setState(() {
      _category = 'student';
    });
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _hexController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    for (var c in _otpControllers) {
      c.dispose();
    }
    for (var f in _otpFocusNodes) {
      f.dispose();
    }
    _resendTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PSTU BLC Signup')),
      body: RefreshIndicator(
        onRefresh: _refreshPage,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _showOtpField ? _buildOtpForm() : _buildSignupForm(),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        const SizedBox(height: 10),
        Image.asset('img/rrr.png', height: 100),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color.fromARGB(255, 134, 222, 80).withOpacity(0.15),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
            border: Border.all(color: const Color.fromARGB(255, 134, 222, 80), width: 2),
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
      ],
    );
  }

  Widget _buildSignupForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          const SizedBox(height: 25),
          TextFormField(
            controller: _nameController,
            onChanged: (_) { if (_statusText.isNotEmpty) setState(() => _statusText = ''); },
            decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
            validator: (v) => (v?.trim() ?? '').isEmpty ? 'Name is required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) { if (_statusText.isNotEmpty) setState(() => _statusText = ''); },
            decoration: InputDecoration(
              labelText: 'Email',
              hintText: _category == 'student' ? 'ugxxxxxxx@faculty.pstu.ac.bd' : 'Enter your email',
              border: const OutlineInputBorder(),
            ),
            validator: (v) {
              if ((v?.trim() ?? '').isEmpty) return 'Email is required';
              if (_category == 'student') return _validateStudentEmail(v!.trim());
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder()),
            validator: (v) => (v?.trim() ?? '').isEmpty ? 'Phone is required' : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _category,
            decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'student', child: Text('Student')),
              DropdownMenuItem(value: 'teacher', child: Text('Teacher')),
            ],
            onChanged: (v) => setState(() { _category = v!; _hexController.clear(); }),
          ),
          if (_category == 'teacher') ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _hexController,
              decoration: const InputDecoration(labelText: 'HEX', border: OutlineInputBorder()),
              validator: (v) => (v?.trim() ?? '').isEmpty ? 'HEX is required for teacher' : null,
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
            validator: (v) => (v?.length ?? 0) < 3 ? 'Password must be at least 3 characters' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Confirm Password', border: OutlineInputBorder()),
            validator: (v) => v != _passwordController.text ? 'Passwords do not match' : null,
          ),
          if (_statusText.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(_statusText, style: TextStyle(color: _statusColor, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
          ],
          const SizedBox(height: 18),
          SizedBox(
            height: 46,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleSignup,
              child: _isLoading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Signup'),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Already have an account? '),
              TextButton(
                onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginPage())),
                child: const Text('Login'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOtpForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(),
        const SizedBox(height: 20),
        const Text('OTP Verification', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Text('We have sent a 6-digit code to\n$_maskedEmail', textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
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
                onChanged: (value) {
                  if (_statusText == 'invalid otp') setState(() => _statusText = '');
                  if (value.isNotEmpty && index < 5) _otpFocusNodes[index + 1].requestFocus();
                  else if (value.isEmpty && index > 0) _otpFocusNodes[index - 1].requestFocus();
                },
                decoration: const InputDecoration(counterText: '', border: OutlineInputBorder()),
              ),
            );
          }),
        ),
        const SizedBox(height: 24),
        if (_statusText.isNotEmpty)
          Center(child: Text(_statusText, style: TextStyle(color: _statusColor, fontWeight: FontWeight.bold)))
        else if (_resendSeconds > 0)
          Center(child: Text('OTP sent to your email', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))),
        Center(
          child: TextButton(
            onPressed: _resendSeconds > 0 ? null : _handleSignup,
            child: Text(_resendSeconds > 0 ? 'Resend OTP in $_resendSeconds s' : 'Resend OTP'),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: OutlinedButton(onPressed: () => setState(() => _showOtpField = false), child: const Text('Back'))),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton(
                onPressed: (_isLoading || _otpControllers.any((c) => c.text.isEmpty)) ? null : _handleOtpVerification,
                child: _isLoading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Verify'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
