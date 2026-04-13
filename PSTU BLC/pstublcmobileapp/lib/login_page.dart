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

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showStatus('Please fill in all fields', false);
      return;
    }

    setState(() => _isLoading = true);
    final result = await _apiService.login(email, password);
    setState(() => _isLoading = false);

    if (!mounted) return;

    if (result['success'] == true) {
      final role = (result['role'] ?? 'teacher').toString();
      _showStatus('Login successful', true);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => role == 'student'
              ? const StudentDashboardPage()
              : const TeacherDashboardPage(),
        ),
      );
    } else {
      _showStatus(result['message'] ?? 'Login failed', false);
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

  void _showStatus(String text, bool success) {
    setState(() {
      _statusText = text;
      _statusColor = success ? Colors.green : Colors.red;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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
              const SizedBox(height: 20),
              const Text(
                'Patuakhali Science and Technology University\nPSTU BLC',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 30),
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
              if (_statusText.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  _statusText,
                  style: TextStyle(
                    color: _statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
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
          ),
        ),
      ),
    );
  }
}
