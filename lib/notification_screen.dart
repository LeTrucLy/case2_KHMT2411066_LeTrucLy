import 'package:flutter/material.dart';
import 'services/api_service.dart';
import 'task_detail_screen.dart';

class NotificationScreen extends StatefulWidget {
  final String token;
  const NotificationScreen({super.key, required this.token});
  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> items = [];

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final result = await ApiService.getNotifications(widget.token);
      if (mounted) setState(() { items = result; loading = false; });
    } catch (e) {
      if (mounted) setState(() { error = '$e'; loading = false; });
    }
  }

  Future<void> openItem(Map<String, dynamic> item) async {
    try {
      await ApiService.readNotification(widget.token, item['_id'].toString());
      final id = item['taskId']?.toString();
      if (id != null && id.isNotEmpty) {
        final task = await ApiService.getTaskDetail(token: widget.token, taskId: id);
        if (!mounted) return;
        await Navigator.push(context, MaterialPageRoute(builder: (_) =>
          TaskDetailScreen(task: task, token: widget.token)));
      }
      await load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thể mở công việc: $e')));
      await load();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Thông báo'),
      backgroundColor: const Color(0xFF1769E8), foregroundColor: Colors.white,
      actions: [
        IconButton(tooltip: 'Đánh dấu tất cả đã đọc', icon: const Icon(Icons.done_all),
          onPressed: () async {
            try { await ApiService.readAllNotifications(widget.token); await load(); }
            catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
          }),
      ]),
    body: loading ? const Center(child: CircularProgressIndicator())
      : error != null ? Center(child: Text('Không tải được thông báo: $error'))
      : RefreshIndicator(onRefresh: load, child: items.isEmpty
        ? ListView(children: const [SizedBox(height: 180),
            Center(child: Text('Chưa có thông báo nào'))])
        : ListView.builder(itemCount: items.length, itemBuilder: (context, i) {
          final item = items[i];
          final read = item['isRead'] == true;
          return Card(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            color: read ? Colors.white : const Color(0xFFE8F1FF),
            child: ListTile(
              leading: Icon(read ? Icons.notifications_none : Icons.notifications_active,
                color: const Color(0xFF1769E8)),
              title: Text(item['title']?.toString() ?? 'Thông báo',
                style: TextStyle(fontWeight: read ? FontWeight.normal : FontWeight.bold)),
              subtitle: Text(item['message']?.toString() ?? ''),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openItem(item),
            ));
        })),
  );
}
