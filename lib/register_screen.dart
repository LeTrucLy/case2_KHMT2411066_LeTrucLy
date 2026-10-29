
import 'package:flutter/material.dart';
import 'services/api_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _hidePassword = true;
  bool _hideConfirm = true;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  InputDecoration _decoration(
      String hint,
      IconData icon,
      ) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  Future<void> _register() async {
    if (_isSaving) return;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final name = _nameController.text.trim();
      final email =
      _emailController.text.trim().toLowerCase();
      final password = _passwordController.text;

      // Gửi tài khoản đến Backend Node.js.
      // Backend chịu trách nhiệm mã hóa mật khẩu
      // và lưu thông tin vào MongoDB.
      await ApiService.register(
        fullName: name,
        email: email,
        password: password,
      );

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(
                  Icons.check_circle,
                  color: Colors.green,
                ),
                SizedBox(width: 10),
                Text('Thành công'),
              ],
            ),
            content: const Text(
              'Đăng ký tài khoản thành công! '
                  'Bạn có thể đăng nhập ngay.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                },
                child: const Text('Đến đăng nhập'),
              ),
            ],
          );
        },
      );

      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      final message = e.toString().replaceFirst(
        'Exception: ',
        '',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Đăng ký'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(25),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),

                const Icon(
                  Icons.person_add_alt_1_rounded,
                  size: 75,
                  color: Color(0xFF1769E8),
                ),

                const SizedBox(height: 20),

                const Text(
                  'Tạo tài khoản',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 10),

                const Text(
                  'Tham gia quản lý công việc cùng nhóm',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey,
                  ),
                ),

                const SizedBox(height: 30),

                // HỌ VÀ TÊN
                const Text('Họ và tên'),
                const SizedBox(height: 8),

                TextFormField(
                  controller: _nameController,
                  textCapitalization:
                  TextCapitalization.words,
                  decoration: _decoration(
                    'Nhập họ và tên',
                    Icons.person_outline,
                  ),
                  validator: (value) {
                    if (value == null ||
                        value.trim().isEmpty) {
                      return 'Vui lòng nhập họ tên';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 20),

                // EMAIL
                const Text('Email'),
                const SizedBox(height: 8),

                TextFormField(
                  controller: _emailController,
                  keyboardType:
                  TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: _decoration(
                    'Nhập địa chỉ email',
                    Icons.email_outlined,
                  ),
                  validator: (value) {
                    final email = value?.trim() ?? '';

                    if (!RegExp(
                      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                    ).hasMatch(email)) {
                      return 'Email không hợp lệ';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 20),

                // MẬT KHẨU
                const Text('Mật khẩu'),
                const SizedBox(height: 8),

                TextFormField(
                  controller: _passwordController,
                  obscureText: _hidePassword,
                  decoration: _decoration(
                    'Nhập mật khẩu',
                    Icons.lock_outline,
                  ).copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _hidePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          _hidePassword = !_hidePassword;
                        });
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null ||
                        value.length < 8) {
                      return 'Mật khẩu phải có ít nhất 8 ký tự';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 20),

                // XÁC NHẬN MẬT KHẨU
                const Text('Xác nhận mật khẩu'),
                const SizedBox(height: 8),

                TextFormField(
                  controller: _confirmController,
                  obscureText: _hideConfirm,
                  decoration: _decoration(
                    'Nhập lại mật khẩu',
                    Icons.lock_reset,
                  ).copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _hideConfirm
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          _hideConfirm = !_hideConfirm;
                        });
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value !=
                        _passwordController.text) {
                      return 'Mật khẩu không khớp';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 30),

                // NÚT ĐĂNG KÝ
                SizedBox(
                  height: 55,
                  child: ElevatedButton(
                    onPressed:
                    _isSaving ? null : _register,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                      const Color(0xFF1769E8),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                        BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                      width: 24,
                      height: 24,
                      child:
                      CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                        : const Text(
                      'Đăng ký',
                      style: TextStyle(
                        fontSize: 17,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text(
                    'Đã có tài khoản? Đăng nhập',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
