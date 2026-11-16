
import 'package:flutter/material.dart';
import 'services/api_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState
    extends State<ForgotPasswordScreen> {
  final emailController = TextEditingController();
  final codeController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmController = TextEditingController();

  bool isLoading = false;
  bool codeSent = false;
  bool hidePassword = true;

  @override
  void dispose() {
    emailController.dispose();
    codeController.dispose();
    passwordController.dispose();
    confirmController.dispose();
    super.dispose();
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ===== GỬI MÃ XÁC MINH =====
  Future<void> sendCode() async {
    final email = emailController.text.trim();

    if (!RegExp(
      r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
    ).hasMatch(email)) {
      showMessage('Vui lòng nhập email hợp lệ');
      return;
    }

    setState(() => isLoading = true);

    try {
      final result = await ApiService.forgotPassword(
        email: email,
      );

      if (!mounted) return;

      setState(() => codeSent = true);

      showMessage(
        result['message']?.toString() ??
            'Nếu email đã đăng ký, mã sẽ được gửi đến bạn.',
      );
    } catch (error) {
      showMessage('Không gửi được yêu cầu: $error');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  // ===== ĐẶT LẠI MẬT KHẨU =====
  Future<void> resetPassword() async {
    final code = codeController.text.trim();
    final password = passwordController.text;
    final confirm = confirmController.text;

    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      showMessage('Vui lòng nhập mã xác minh gồm 6 số');
      return;
    }

    if (password.length < 8) {
      showMessage('Mật khẩu phải có ít nhất 8 ký tự');
      return;
    }

    if (password != confirm) {
      showMessage('Mật khẩu xác nhận không khớp');
      return;
    }

    setState(() => isLoading = true);

    try {
      await ApiService.resetPassword(
        email: emailController.text.trim(),
        resetCode: code,
        newPassword: password,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Đổi mật khẩu thành công! Hãy đăng nhập lại.',
          ),
        ),
      );

      Navigator.pop(context);
    } catch (error) {
      showMessage('Không thể đặt lại mật khẩu: $error');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FF),
      appBar: AppBar(
        title: const Text('Quên mật khẩu'),
        backgroundColor: const Color(0xFF1769E8),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),

            const Icon(
              Icons.lock_reset,
              size: 76,
              color: Color(0xFF1769E8),
            ),

            const SizedBox(height: 15),

            Text(
              codeSent
                  ? 'Đặt lại mật khẩu'
                  : 'Khôi phục mật khẩu',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            Text(
              codeSent
                  ? 'Nhập mã xác minh từ email và mật khẩu mới.'
                  : 'Nhập email đã đăng ký để nhận mã xác minh.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
            ),

            const SizedBox(height: 30),

            TextField(
              controller: emailController,
              enabled: !codeSent && !isLoading,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 18),

            if (codeSent) ...[
              TextField(
                controller: codeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'Mã xác minh 6 số',
                  prefixIcon: Icon(Icons.verified_user),
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 12),

              TextField(
                controller: passwordController,
                obscureText: hidePassword,
                decoration: InputDecoration(
                  labelText: 'Mật khẩu mới',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      hidePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() {
                        hidePassword = !hidePassword;
                      });
                    },
                  ),
                ),
              ),

              const SizedBox(height: 18),

              TextField(
                controller: confirmController,
                obscureText: hidePassword,
                decoration: const InputDecoration(
                  labelText: 'Xác nhận mật khẩu mới',
                  prefixIcon: Icon(Icons.lock),
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 12),

              TextButton(
                onPressed: isLoading
                    ? null
                    : () {
                  setState(() {
                    codeSent = false;
                    codeController.clear();
                  });
                },
                child: const Text(
                  'Quay lại để yêu cầu mã mới',
                ),
              ),
            ],

            const SizedBox(height: 16),

            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: isLoading
                    ? null
                    : (codeSent ? resetPassword : sendCode),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                  const Color(0xFF1769E8),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius.circular(14),
                  ),
                ),
                child: isLoading
                    ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
                    : Text(
                  codeSent
                      ? 'Đặt lại mật khẩu'
                      : 'Gửi mã xác minh',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
