import 'package:flutter/material.dart';
import 'package:pstublc/services/api_service.dart';
import 'dart:async';

class DeleteAccountDialog extends StatefulWidget {
  final String email;
  final String role;
  final ApiService apiService;

  const DeleteAccountDialog({
    super.key,
    required this.email,
    required this.role,
    required this.apiService,
  });

  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  final _passwordController = TextEditingController();
  final List<TextEditingController> _otpControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());

  int _step = 1; // 1: Password, 2: OTP
  bool _isLoading = false;
  bool _otpSent = false;
  String _errorText = '';
  String? _appwriteUserId;
  int _resendSeconds = 0;
  Timer? _resendTimer;

  @override
  void dispose() {
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

  void _showError(String msg) {
    setState(() {
      _errorText = msg;
    });
  }

  Future<void> _verifyPassword() async {
    final password = _passwordController.text;
    if (password.isEmpty) {
      _showError('Password is required');
      return;
    }

    setState(() => _isLoading = true);
    _showError('');

    try {
      final result = await widget.apiService.deleteAccount(
        role: widget.role,
        email: widget.email,
        password: password,
        verifyOnly: true,
      );

      if (result['success'] == true) {
        setState(() => _step = 2);
      } else {
        _showError(result['message'] ?? 'Incorrect password');
      }
    } catch (e) {
      _showError('Connection error');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _sendOtp() async {
    setState(() => _isLoading = true);
    _showError('');

    try {
      final result = await widget.apiService.sendAppwriteOtp(widget.email);
      if (result['success'] == true) {
        setState(() {
          _otpSent = true;
          _appwriteUserId = result['userId'];
          _resendSeconds = 60;
        });
        _startResendTimer();
      } else {
        _showError(result['message'] ?? 'Failed to send OTP');
      }
    } catch (e) {
      _showError('Failed to send OTP');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_resendSeconds > 0) {
          _resendSeconds--;
        } else {
          timer.cancel();
        }
      });
    });
  }

  Future<void> _verifyOtpAndDelete() async {
    final otp = _otpControllers.map((c) => c.text).join();
    if (otp.length < 6) {
      _showError('Enter 6-digit OTP');
      return;
    }

    setState(() => _isLoading = true);
    _showError('');

    try {
      // 1. Verify OTP
      final otpResult = await widget.apiService.verifyAppwriteOtp(
        _appwriteUserId!,
        otp,
        userData: null,
      );

      if (otpResult['success'] == true) {
        // 2. Perform actual deletion
        final deleteResult = await widget.apiService.deleteAccount(
          role: widget.role,
          email: widget.email,
          password: _passwordController.text,
          verifyOnly: false,
        );

        if (deleteResult['success'] == true) {
          if (!mounted) return;
          Navigator.pop(context, true);
        } else {
          _showError(deleteResult['message'] ?? 'Deletion failed');
        }
      } else {
        _showError('Invalid OTP');
      }
    } catch (e) {
      _showError('Verification failed');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_step == 1 ? 'Delete Account' : 'OTP Verification'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_step == 1) ...[
              const Text(
                'Are you sure you want to delete your account? This action cannot be undone.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Current Password',
                  border: OutlineInputBorder(),
                ),
              ),
            ] else ...[
              Text(
                'We will send a 6-digit code to\n${_maskEmail(widget.email)}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(6, (index) {
                  return SizedBox(
                    width: 35,
                    height: 45,
                    child: TextField(
                      controller: _otpControllers[index],
                      focusNode: _otpFocusNodes[index],
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      maxLength: 1,
                      onChanged: (value) {
                        setState(() {});
                        if (value.isNotEmpty && index < 5) {
                          _otpFocusNodes[index + 1].requestFocus();
                        } else if (value.isEmpty && index > 0) {
                          _otpFocusNodes[index - 1].requestFocus();
                        }
                      },
                      decoration: const InputDecoration(
                        counterText: '',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  );
                }),
              ),
              if (_otpSent) ...[
                const SizedBox(height: 16),
                if (_resendSeconds > 0 && _errorText.isEmpty)
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
                    onPressed: _resendSeconds > 0 ? null : _sendOtp,
                    child: Text(
                      _resendSeconds > 0
                          ? 'Resend OTP in $_resendSeconds s'
                          : 'Resend OTP',
                      style: TextStyle(
                        color: _resendSeconds > 0 ? Colors.grey : Colors.blue,
                      ),
                    ),
                  ),
                ),
              ],
            ],
            if (_errorText.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                _errorText,
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (_step == 1)
          ElevatedButton(
            onPressed: _isLoading ? null : _verifyPassword,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: _isLoading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Next'),
          )
        else
          ElevatedButton(
            onPressed: _isLoading
                ? null
                : (_otpSent
                    ? (_otpControllers.every((c) => c.text.isNotEmpty)
                        ? _verifyOtpAndDelete
                        : null)
                    : _sendOtp),
            style: ElevatedButton.styleFrom(
              backgroundColor: _otpSent ? Colors.green : Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ))
                : Text(_otpSent ? 'Verify & Delete' : 'Send OTP'),
          ),
      ],
    );
  }

  String _maskEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2) return email;
    final name = parts[0];
    final domain = parts[1];
    if (name.length <= 2) return '***@$domain';
    return '${name.substring(0, 2)}***@$domain';
  }
}
