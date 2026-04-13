import 'package:flutter/material.dart';
import 'package:pstublc/login_page.dart';
import 'package:pstublc/services/api_service.dart';

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

  final ApiService _apiService = ApiService();

  static final RegExp _phoneRegExp = RegExp(r'^(\+?88)?01[0-9]{9}$');
  static final RegExp _studentEmailRegExp = RegExp(
    r'^ug(\d{2})(\d{2})(\d{3})@([a-z]+)\.pstu\.ac\.bd$',
    caseSensitive: false,
  );

  final Map<String, String> _facultyDomainByCode = const {
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

  Future<void> _handleSignup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final payload = {
      'name': _nameController.text.trim(),
      'email': _emailController.text.trim().toLowerCase(),
      'phone': _phoneController.text.trim(),
      'category': _category,
      'hex': _hexController.text.trim(),
      'password': _passwordController.text,
      'confirmPassword': _confirmPasswordController.text,
    };

    final result = await _apiService.signup(payload);
    setState(() => _isLoading = false);

    if (!mounted) return;

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registration successful. Please login.')),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    } else {
      final errors = result['errors'];
      String message = result['message']?.toString() ?? 'Signup failed';
      if (errors is Map && errors.isNotEmpty) {
        message = errors.values.first.toString();
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _refreshPage() async {
    setState(() {
      _isLoading = false;
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PSTU BLC Signup')),
      body: RefreshIndicator(
        onRefresh: _refreshPage,
        child: Form(
          key: _formKey,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return 'Name is required';
                  if (text.length < 3 || text.length > 15) {
                    return 'Name must be 3-15 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email',
                  hintText: _category == 'student'
                      ? 'ugxxxxxxx@faculty.pstu.ac.bd'
                      : 'Enter your email',
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return 'Email is required';
                  if (_category == 'student') {
                    return _validateStudentEmail(text);
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return 'Phone is required';
                  if (!_phoneRegExp.hasMatch(text)) {
                    return 'Invalid phone format (01xxxxxxxxx)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'student', child: Text('Student')),
                  DropdownMenuItem(value: 'teacher', child: Text('Teacher')),
                ],
                onChanged: (value) {
                  setState(() {
                    _category = value ?? 'student';
                    _hexController.clear();
                  });
                },
              ),
              if (_category == 'teacher') ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _hexController,
                  decoration: const InputDecoration(
                    labelText: 'HEX',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (_category != 'teacher') return null;
                    if ((value?.trim() ?? '').isEmpty) {
                      return 'HEX is required for teacher';
                    }
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final text = value ?? '';
                  if (text.isEmpty) return 'Password is required';
                  if (text.length < 3) {
                    return 'Password must be at least 3 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm Password',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if ((value ?? '') != _passwordController.text) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 46,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleSignup,
                  child: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Signup'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                ),
                child: const Text('Already have an account? Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
