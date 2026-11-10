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
  String? currentUserId;

  // JWT chỉ dùng để ẩn/hiện nút trên giao diện.
  // Backend vẫn là nơi quyết định quyền truy cập thực sự.
  String? userIdFromToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final decoded = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final payload = jsonDecode(decoded);
      if (payload is! Map) return null;
      return payload['userId']?.toString();
    } catch (_) {
      return null;
    }
  }

  String? objectIdOf(dynamic value) {
    if (value is Map) return value['_id']?.toString();
    return value?.toString();
  }

  bool isTaskOwner(Map<String, dynamic> task) {
    final ownerId = objectIdOf(task['owner']);
    return currentUserId != null &&
        ownerId != null &&
        ownerId == currentUserId;
  }

  // Backend trả về canEdit = true khi tài khoản có quyền sửa.
  // Không suy ra quyền sửa chỉ từ việc được phân công công việc.
  bool canEditTask(Map<String, dynamic> task) {
    return isTaskOwner(task) || task['canEdit'] == true;
  }

  @override
  void initState() {
    super.initState();
    currentUserId = userIdFromToken(widget.token);
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
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => TaskFormScreen(
          token: widget.token,
          task: task,
          canManageAssignees: task == null || isTaskOwner(task),
        ),
      ),
    );

    if (mounted) {
      await loadTasks();
    }
  }

  // Chủ công việc và người được giao đều có thể đổi trạng thái.
  Future<void> changeTaskStatus(Map<String, dynamic> task) async {
    // Chặn thao tác ngay cả khi hàm được gọi từ nơi khác trong giao diện.
    if (!canEditTask(task)) {
      showMessage('Bạn không có quyền cập nhật trạng thái công việc');
      return;
    }

    final taskId = task['_id']?.toString();
    if (taskId == null || taskId.isEmpty) {
      showMessage('Không tìm thấy mã công việc');
      return;
    }

    const statuses = ['pending', 'in_progress', 'completed'];
    final oldStatus = task['status']?.toString() ?? 'pending';
    String selectedStatus = statuses.contains(oldStatus) ? oldStatus : 'pending';

    final nextStatus = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Cập nhật trạng thái'),
          content: DropdownButtonFormField<String>(
            initialValue: selectedStatus,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Trạng thái công việc',
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
            onChanged: (value) {
              if (value != null) {
                setDialogState(() => selectedStatus = value);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, selectedStatus),
              child: const Text('Lưu trạng thái'),
            ),
          ],
        ),
      ),
    );

    if (nextStatus == null || nextStatus == oldStatus || !mounted) return;

    try {
      final response = await http.patch(
        Uri.parse(
          '${ApiService.baseUrl}/api/tasks/'
              '${Uri.encodeComponent(taskId)}/status',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: jsonEncode({'status': nextStatus}),
      ).timeout(const Duration(seconds: 15));

      final decoded = jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          decoded is Map
              ? (decoded['message'] ?? 'Cập nhật trạng thái thất bại')
              : 'Cập nhật trạng thái thất bại',
        );
      }

      if (!mounted) return;
      showMessage('Cập nhật trạng thái thành công');
      await loadTasks();
    } catch (e) {
      if (!mounted) return;
      showMessage('Lỗi: $e');
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
            final isOwner = isTaskOwner(task);
            final canEdit = canEditTask(task);

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
                          if (canEdit)
                            IconButton(
                              tooltip: 'Cập nhật trạng thái',
                              icon: const Icon(
                                Icons.sync_alt,
                                color: Colors.teal,
                              ),
                              onPressed: () => changeTaskStatus(task),
                            ),
                          if (canEdit)
                            IconButton(
                              tooltip: 'Sửa',
                              icon: const Icon(
                                Icons.edit_outlined,
                                color: Colors.blue,
                              ),
                              onPressed: () => openTaskForm(task: task),
                            ),
                          if (isOwner)
                            IconButton(
                              tooltip: 'Xóa',
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                              ),
                              onPressed: () => deleteTask(task),
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

// ========== MÀN HÌNH THÊM / SỬA + PHÂN CÔNG BUỔI 2 ==========

class TaskFormScreen extends StatefulWidget {
  final String token;
  final Map<String, dynamic>? task;
  final bool canManageAssignees;

  const TaskFormScreen({
    super.key,
    required this.token,
    this.task,
    this.canManageAssignees = true,
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
  bool isLoadingUsers = true;
  String? usersError;
  List<Map<String, dynamic>> users = [];
  final Set<String> selectedAssigneeIds = <String>{};
  bool assignmentsTouched = false;

  // Giữ ID sau khi tạo thành công để nếu bước phân công lỗi,
  // bấm Lưu lại sẽ không tạo trùng công việc.
  String? createdTaskId;

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

    final initialStatus = widget.task?['status']?.toString() ?? 'pending';
    if (['pending', 'in_progress', 'completed'].contains(initialStatus)) {
      status = initialStatus;
    }

    final existingAssignees = widget.task?['assigneeIds'];
    if (existingAssignees is List) {
      for (final value in existingAssignees) {
        final id = value is Map ? value['_id']?.toString() : value?.toString();
        if (id != null && id.isNotEmpty) selectedAssigneeIds.add(id);
      }
    }
    if (selectedAssigneeIds.isEmpty) {
      final assignedTo = widget.task?['assignedTo'];
      final id = assignedTo is Map
          ? assignedTo['_id']?.toString()
          : assignedTo?.toString();
      if (id != null && id.isNotEmpty) selectedAssigneeIds.add(id);
    }
    if (widget.canManageAssignees) {
      loadUsers();
    } else {
      isLoadingUsers = false;
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  Future<void> loadUsers() async {
    if (!mounted) return;
    setState(() {
      isLoadingUsers = true;
      usersError = null;
    });
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/users'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      ).timeout(const Duration(seconds: 15));

      final decoded = jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(decoded is Map
            ? (decoded['message'] ?? 'Không tải được người dùng')
            : 'Không tải được người dùng');
      }
      if (decoded is! Map || decoded['users'] is! List) {
        throw const FormatException('Dữ liệu người dùng không hợp lệ');
      }
      final result = (decoded['users'] as List)
          .whereType<Map>()
          .map((u) => Map<String, dynamic>.from(u))
          .toList();

      if (!mounted) return;
      setState(() {
        users = result;
        isLoadingUsers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        usersError = e.toString();
        isLoadingUsers = false;
      });
    }
  }

  void toggleAssignee(String id, bool selected) {
    setState(() {
      if (selected) {
        if (selectedAssigneeIds.length >= 20) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Chỉ được phân công tối đa 20 người')),
          );
          return;
        }
        selectedAssigneeIds.add(id);
      } else {
        selectedAssigneeIds.remove(id);
      }
      assignmentsTouched = true;
    });
  }

  Future<void> saveTask() async {
    if (isSaving || !formKey.currentState!.validate()) return;
    setState(() => isSaving = true);

    try {
      final existingId = widget.task?['_id']?.toString();
      final taskId = createdTaskId ?? existingId;
      final shouldUpdate = isEditing || createdTaskId != null;
      if (shouldUpdate && (taskId == null || taskId.isEmpty)) {
        throw Exception('Không tìm thấy mã công việc');
      }

      final url = shouldUpdate
          ? '${ApiService.baseUrl}/api/tasks/${Uri.encodeComponent(taskId!)}'
          : '${ApiService.baseUrl}/api/tasks';
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${widget.token}',
      };
      final body = jsonEncode({
        'title': titleController.text.trim(),
        'description': descriptionController.text.trim(),
        'status': status,
      });

      final response = await (shouldUpdate
          ? http.put(Uri.parse(url), headers: headers, body: body)
          : http.post(Uri.parse(url), headers: headers, body: body))
          .timeout(const Duration(seconds: 15));
      final decoded = jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(decoded is Map
            ? (decoded['message'] ?? 'Lưu công việc thất bại')
            : 'Lưu công việc thất bại');
      }
      if (decoded is! Map || decoded['task'] is! Map) {
        throw const FormatException('Máy chủ không trả về công việc');
      }
      final savedId = (decoded['task'] as Map)['_id']?.toString();
      if (savedId == null || savedId.isEmpty) {
        throw const FormatException('Không tìm thấy ID công việc đã lưu');
      }
      if (!isEditing) createdTaskId = savedId;

      // Khi tạo mới: chỉ gọi API phân công nếu có chọn người.
      // Khi sửa: chỉ gọi nếu danh sách phân công thực sự thay đổi.
      final needAssign = isEditing
          ? assignmentsTouched
          : selectedAssigneeIds.isNotEmpty;
      if (widget.canManageAssignees && needAssign) {
        final assignResponse = await http.put(
          Uri.parse(
            '${ApiService.baseUrl}/api/tasks/'
                '${Uri.encodeComponent(savedId)}/assignees',
          ),
          headers: headers,
          body: jsonEncode({'userIds': selectedAssigneeIds.toList()}),
        ).timeout(const Duration(seconds: 15));
        final assignData = jsonDecode(assignResponse.body);
        if (assignResponse.statusCode < 200 ||
            assignResponse.statusCode >= 300) {
          throw Exception(assignData is Map
              ? (assignData['message'] ?? 'Phân công thất bại')
              : 'Phân công thất bại');
        }
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi: $e')),
      );
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FF),
      appBar: AppBar(
        title: Text(isEditing ? 'Sửa công việc' : 'Thêm công việc'),
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
                  final text = value?.trim() ?? '';
                  if (text.length < 2 || text.length > 150) {
                    return 'Tên công việc phải có từ 2 đến 150 ký tự';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: descriptionController,
                maxLines: 4,
                maxLength: 2000,
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
                  if (value != null) setState(() => status = value);
                },
              ),
              const SizedBox(height: 20),
              if (widget.canManageAssignees)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Người được phân công',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Đã chọn ${selectedAssigneeIds.length}/20 người',
                          style: const TextStyle(color: Colors.grey),
                        ),
                        if (isLoadingUsers)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (usersError != null) ...[
                          const SizedBox(height: 8),
                          Text('Không tải được người dùng: $usersError'),
                          TextButton.icon(
                            onPressed: loadUsers,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Thử lại'),
                          ),
                        ] else if (users.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text('Chưa có tài khoản để phân công'),
                          )
                        else
                          ...users.map((user) {
                            final id = user['_id']?.toString() ?? '';
                            final name = user['fullName']?.toString() ?? 'Người dùng';
                            return CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: Text(name),
                              value: selectedAssigneeIds.contains(id),
                              onChanged: isSaving || id.isEmpty
                                  ? null
                                  : (checked) => toggleAssignee(id, checked ?? false),
                            );
                          }),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: isSaving ? null : saveTask,
                  icon: isSaving
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Icon(Icons.save),
                  label: Text(isSaving
                      ? 'Đang lưu...'
                      : isEditing
                      ? 'Cập nhật công việc'
                      : 'Thêm công việc'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1769E8),
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
