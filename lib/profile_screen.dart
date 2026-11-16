import 'package:flutter/material.dart';
import 'services/api_service.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String token;
  const ProfileScreen({super.key, required this.token});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final name = TextEditingController();
  final oldPassword = TextEditingController();
  final newPassword = TextEditingController();
  String email = '';
  bool loading = true;
  bool saving = false;
  String? error;

  @override
  void initState() { super.initState(); load(); }
  @override
  void dispose() {
    name.dispose(); oldPassword.dispose(); newPassword.dispose(); super.dispose();
  }

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final data = await ApiService.getProfile(widget.token);
      if (!mounted) return;
      setState(() {
        name.text = data['user']['fullName']?.toString() ?? '';
        email = data['user']['email']?.toString() ?? '';
        loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { error = '$e'; loading = false; });
    }
  }

  void message(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> saveProfile() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await ApiService.updateProfile(widget.token, name.text);
      message('Đã cập nhật hồ sơ');
      await load();
    } catch (e) { message('$e'); }
    finally { if (mounted) setState(() => saving = false); }
  }

  Future<void> savePassword() async {
    if (saving) return;
    if (newPassword.text.length < 8) { message('Mật khẩu mới cần ít nhất 8 ký tự'); return; }
    setState(() => saving = true);
    try {
      await ApiService.changePassword(widget.token, oldPassword.text, newPassword.text);
      oldPassword.clear(); newPassword.clear();
      message('Đổi mật khẩu thành công');
    } catch (e) { message('$e'); }
    finally { if (mounted) setState(() => saving = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Hồ sơ cá nhân'),
      backgroundColor: const Color(0xFF1769E8), foregroundColor: Colors.white),
    body: loading ? const Center(child: CircularProgressIndicator())
      : error != null ? Center(child: Text('Không tải được hồ sơ: $error'))
      : ListView(padding: const EdgeInsets.all(16), children: [
        const Icon(Icons.account_circle, size: 70, color: Color(0xFF1769E8)),
        const SizedBox(height: 12),
        Text('Email: $email', textAlign: TextAlign.center),
        const SizedBox(height: 20),
        TextField(controller: name, decoration: const InputDecoration(
          labelText: 'Họ và tên', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        FilledButton(onPressed: saving ? null : saveProfile,
          child: const Text('Cập nhật thông tin')),
        const Divider(height: 40),
        const Text('Đổi mật khẩu', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        TextField(controller: oldPassword, obscureText: true,
          decoration: const InputDecoration(labelText: 'Mật khẩu hiện tại', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: newPassword, obscureText: true,
          decoration: const InputDecoration(labelText: 'Mật khẩu mới (ít nhất 8 ký tự)',
            border: OutlineInputBorder())),
        const SizedBox(height: 10),
        FilledButton(onPressed: saving ? null : savePassword,
          child: const Text('Đổi mật khẩu')),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          icon: const Icon(Icons.logout), label: const Text('Đăng xuất'),
          onPressed: () => Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false)),
      ]),
  );
}
