
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'services/api_service.dart';
import 'task_detail_screen.dart';

class TaskListScreen extends StatefulWidget {
  final String token;

  const TaskListScreen({
    super.key,
    required this.token,
  });

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  bool isLoading = true;
  String? errorMessage;
  List<Map<String, dynamic>> tasks = [];

  @override
  void initState() {
    super.initState();
    loadTasks();
  }

  Future<void> loadTasks() async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final result = await ApiService.getTasks(
        token: widget.token,
      );

      if (!mounted) return;

      setState(() {
        tasks = result;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  String statusText(String status) {
    switch (status) {
      case 'pending':
        return 'Chờ thực hiện';
      case 'in_progress':
        return 'Đang thực hiện';
      case 'completed':
        return 'Hoàn thành';
      default:
        return status;
    }
  }

  Color statusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'in_progress':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Future<void> openTaskDetail(
      Map<String, dynamic> task,
      ) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TaskDetailScreen(
          task: task,
          token: widget.token,
        ),
      ),
    );

    if (mounted) {
      await loadTasks();
    }
  }

  Future<void> openTaskForm({
    Map<String, dynamic>? task,
  }) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => TaskFormScreen(
          token: widget.token,
          task: task,
        ),
      ),
    );

    if (changed == true && mounted) {
      await loadTasks();
    }
  }

  Future<void> deleteTask(
      Map<String, dynamic> task,
      ) async {
    final taskId = task['_id']?.toString();

    if (taskId == null || taskId.isEmpty) {
      showMessage('Không tìm thấy mã công việc');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa công việc?'),
        content: Text(
          'Bạn có chắc muốn xóa "${task['title']}" không?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext, false);
            },
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext, true);
            },
            child: const Text(
              'Xóa',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final response = await http
          .delete(
        Uri.parse(
          '${ApiService.baseUrl}/api/tasks/'
              '${Uri.encodeComponent(taskId)}',
        ),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
        },
      )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode < 200 ||
          response.statusCode >= 300) {
        throw Exception(
          data is Map
              ? data['message'] ?? 'Xóa thất bại'
              : 'Xóa thất bại',
        );
      }

      if (!mounted) return;

      showMessage('Xóa công việc thành công');

      await loadTasks();
    } catch (e) {
      if (!mounted) return;
      showMessage('Lỗi: $e');
    }
  }

  void showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FF),

      appBar: AppBar(
        title: const Text('Danh sách công việc'),
        backgroundColor: const Color(0xFF1769E8),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Tải lại',
            onPressed: loadTasks,
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openTaskForm(),
        backgroundColor: const Color(0xFF1769E8),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Thêm công việc'),
      ),

      body: isLoading
          ? const Center(
        child: CircularProgressIndicator(),
      )
          : errorMessage != null
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Không tải được công việc:\n'
                    '$errorMessage',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: loadTasks,
                child: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      )
          : tasks.isEmpty
          ? RefreshIndicator(
        onRefresh: loadTasks,
        child: ListView(
          physics:
          const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 160),
            Center(
              child: Text(
                'Chưa có công việc nào.\n'
                    'Nhấn + để thêm công việc.',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      )
          : RefreshIndicator(
        onRefresh: loadTasks,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(
            16, 16, 16, 100,
          ),
          itemCount: tasks.length,
          itemBuilder: (context, index) {
            final task = tasks[index];

            final title =
                task['title']?.toString() ??
                    'Không có tiêu đề';

            final description =
                task['description']?.toString() ?? '';

            final status =
                task['status']?.toString() ??
                    'pending';

            return Card(
              margin: const EdgeInsets.only(
                bottom: 14,
              ),
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius:
                BorderRadius.circular(14),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => openTaskDetail(task),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        description,
                        maxLines: 2,
                        overflow:
                        TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              statusText(status),
                              style: TextStyle(
                                color:
                                statusColor(status),
                                fontWeight:
                                FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Sửa',
                            icon: const Icon(
                              Icons.edit_outlined,
                              color: Colors.blue,
                            ),
                            onPressed: () {
                              openTaskForm(task: task);
                            },
                          ),
                          IconButton(
                            tooltip: 'Xóa',
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.red,
                            ),
                            onPressed: () {
                              deleteTask(task);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ========== MÀN HÌNH THÊM / SỬA ==========

class TaskFormScreen extends StatefulWidget {
  final String token;
  final Map<String, dynamic>? task;

  const TaskFormScreen({
    super.key,
    required this.token,
    this.task,
  });

  @override
  State<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends State<TaskFormScreen> {
  final formKey = GlobalKey<FormState>();

  late final TextEditingController titleController;
  late final TextEditingController descriptionController;

  String status = 'pending';
  bool isSaving = false;

  bool get isEditing => widget.task != null;

  @override
  void initState() {
    super.initState();

    titleController = TextEditingController(
      text: widget.task?['title']?.toString() ?? '',
    );

    descriptionController = TextEditingController(
      text: widget.task?['description']?.toString() ?? '',
    );

    final initialStatus =
        widget.task?['status']?.toString() ?? 'pending';

    if ([
      'pending',
      'in_progress',
      'completed',
    ].contains(initialStatus)) {
      status = initialStatus;
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  Future<void> saveTask() async {
    if (!formKey.currentState!.validate()) return;

    setState(() {
      isSaving = true;
    });

    try {
      final taskId = widget.task?['_id']?.toString();

      if (isEditing &&
          (taskId == null || taskId.isEmpty)) {
        throw Exception('Không tìm thấy mã công việc');
      }

      final url = isEditing
          ? '${ApiService.baseUrl}/api/tasks/'
          '${Uri.encodeComponent(taskId!)}'
          : '${ApiService.baseUrl}/api/tasks';

      final body = jsonEncode({
        'title': titleController.text.trim(),
        'description': descriptionController.text.trim(),
        'status': status,
      });

      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${widget.token}',
      };

      final response = await (isEditing
          ? http.put(
        Uri.parse(url),
        headers: headers,
        body: body,
      )
          : http.post(
        Uri.parse(url),
        headers: headers,
        body: body,
      ))
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode < 200 ||
          response.statusCode >= 300) {
        throw Exception(
          data is Map
              ? data['message'] ?? 'Lưu công việc thất bại'
              : 'Lưu công việc thất bại',
        );
      }

      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FF),
      appBar: AppBar(
        title: Text(
          isEditing ? 'Sửa công việc' : 'Thêm công việc',
        ),
        backgroundColor: const Color(0xFF1769E8),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: titleController,
                maxLength: 150,
                decoration: const InputDecoration(
                  labelText: 'Tên công việc',
                  hintText: 'Nhập tên công việc',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.task_alt),
                ),
                validator: (value) {
                  if (value == null ||
                      value.trim().isEmpty) {
                    return 'Vui lòng nhập tên công việc';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: descriptionController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Mô tả công việc',
                  hintText: 'Nhập mô tả',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: status,
                decoration: const InputDecoration(
                  labelText: 'Trạng thái',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'pending',
                    child: Text('Chờ thực hiện'),
                  ),
                  DropdownMenuItem(
                    value: 'in_progress',
                    child: Text('Đang thực hiện'),
                  ),
                  DropdownMenuItem(
                    value: 'completed',
                    child: Text('Hoàn thành'),
                  ),
                ],
                onChanged: isSaving
                    ? null
                    : (value) {
                  if (value != null) {
                    setState(() {
                      status = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 28),
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: isSaving ? null : saveTask,
                  icon: isSaving
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                      : const Icon(Icons.save),
                  label: Text(
                    isSaving
                        ? 'Đang lưu...'
                        : isEditing
                        ? 'Cập nhật công việc'
                        : 'Thêm công việc',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                    const Color(0xFF1769E8),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}