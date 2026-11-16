import 'package:flutter/material.dart';
import 'services/api_service.dart';

class TaskHistoryScreen extends StatefulWidget {
  final String token;
  final String taskId;
  final bool canViewEmailLogs;
  const TaskHistoryScreen({super.key, required this.token,
    required this.taskId, required this.canViewEmailLogs});
  @override
  State<TaskHistoryScreen> createState() => _TaskHistoryScreenState();
}

class _TaskHistoryScreenState extends State<TaskHistoryScreen> {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> activities = [];
  List<Map<String, dynamic>> logs = [];

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final a = await ApiService.getActivities(widget.token, widget.taskId);
      final e = widget.canViewEmailLogs
        ? await ApiService.getEmailLogs(widget.token, widget.taskId)
        : <Map<String, dynamic>>[];
      if (mounted) setState(() { activities = a; logs = e; loading = false; });
    } catch (ex) {
      if (mounted) setState(() { error = '$ex'; loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Lịch sử công việc'),
      backgroundColor: const Color(0xFF1769E8), foregroundColor: Colors.white),
    body: loading ? const Center(child: CircularProgressIndicator())
      : error != null ? Center(child: Text('Không tải được lịch sử: $error'))
      : RefreshIndicator(onRefresh: load, child: ListView(
        padding: const EdgeInsets.all(16), children: [
          const Text('Hoạt động', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          if (activities.isEmpty) const ListTile(title: Text('Chưa có lịch sử hoạt động')),
          ...activities.map((a) => ListTile(
            leading: const Icon(Icons.history),
            title: Text(a['action']?.toString() ?? 'Hoạt động'),
            subtitle: Text(a['createdAt']?.toString() ?? ''),
          )),
          if (widget.canViewEmailLogs) ...[
            const Divider(height: 30),
            const Text('Lịch sử gửi email',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (logs.isEmpty) const ListTile(title: Text('Chưa có email nào được ghi nhận')),
            ...logs.map((e) => ListTile(
              leading: Icon(e['status'] == 'sent' ? Icons.mark_email_read : Icons.mail_outline),
              title: Text(e['recipientEmail']?.toString() ?? ''),
              subtitle: Text('${e['eventType'] ?? ''} - ${e['status'] ?? ''}'),
              trailing: e['status'] == 'failed' && (e['attempts'] ?? 0) < 3
                ? IconButton(icon: const Icon(Icons.refresh),
                    tooltip: 'Gửi lại email',
                    onPressed: () async {
                      try {
                        await ApiService.retryEmail(widget.token, e['_id'].toString());
                        await load();
                      } catch (err) {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$err')));
                      }
                    }) : null,
            )),
          ],
        ])),
  );
}
