import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'services/api_service.dart';

class TaskDetailScreen extends StatefulWidget {
  final Map<String, dynamic> task;
  final String token;

  const TaskDetailScreen({
    super.key,
    required this.task,
    required this.token,
  });

  @override
  State<TaskDetailScreen> createState() =>
      _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  late Map<String, dynamic> taskDetail;

  bool isLoading = true;
  String? errorMessage;

  Map<String, String> userNames = {};

  @override
  void initState() {
    super.initState();
    taskDetail = widget.task;
    loadTaskDetail();
  }

  String? extractUserId(dynamic value) {
    if (value == null) return null;

    if (value is Map) {
      final id = value['_id'] ?? value['id'];
      return id?.toString();
    }

    return value.toString();
  }

  List<String> getAssignedIds() {
    final ids = <String>{};

    final assigneeIds = taskDetail['assigneeIds'];

    if (assigneeIds is List) {
      for (final value in assigneeIds) {
        final id = extractUserId(value);

        if (id != null && id.isNotEmpty) {
          ids.add(id);
        }
      }
    }

    final assignedTo =
    extractUserId(taskDetail['assignedTo']);

    if (assignedTo != null && assignedTo.isNotEmpty) {
      ids.add(assignedTo);
    }

    final primaryAssigneeId =
    extractUserId(taskDetail['primaryAssigneeId']);

    if (primaryAssigneeId != null &&
        primaryAssigneeId.isNotEmpty) {
      ids.add(primaryAssigneeId);
    }

    return ids.toList();
  }

  Future<Map<String, String>> loadUserNames() async {
    final response = await http.get(
      Uri.parse('${ApiService.baseUrl}/api/users'),
      headers: {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json',
      },
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Không tải được danh sách người dùng');
    }

    final data = jsonDecode(response.body);

    if (data is! Map || data['users'] is! List) {
      throw Exception('Dữ liệu người dùng không hợp lệ');
    }

    final names = <String, String>{};

    for (final user in data['users'] as List) {
      if (user is Map) {
        final id = extractUserId(user);
        final name = user['fullName']?.toString();

        if (id != null &&
            id.isNotEmpty &&
            name != null &&
            name.isNotEmpty) {
          names[id] = name;
        }
      }
    }

    return names;
  }

  Future<void> loadTaskDetail() async {
    final taskId = widget.task['_id']?.toString();

    if (taskId == null || taskId.isEmpty) {
      setState(() {
        isLoading = false;
        errorMessage = 'Không tìm thấy mã công việc';
      });
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final result = await ApiService.getTaskDetail(
        token: widget.token,
        taskId: taskId,
      );

      Map<String, String> names = {};

      try {
        names = await loadUserNames();
      } catch (error) {
        debugPrint('Không tải được tên người dùng: $error');
      }

      if (!mounted) return;

      setState(() {
        taskDetail = result;
        userNames = names;
        isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        errorMessage = error.toString()
            .replaceFirst('Exception: ', '');
        isLoading = false;
      });
    }
  }

  // Quyền hiển thị do API chi tiết trả về; Backend vẫn kiểm tra quyền.
  bool get canManageShares =>
      taskDetail['canManageShares'] == true ||
          taskDetail['myPermission'] == 'owner';

  Future<void> openShareManagement() async {
    final taskId = taskDetail['_id']?.toString();
    if (taskId == null || taskId.isEmpty) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TaskShareManagementScreen(
          taskId: taskId,
          taskTitle: taskDetail['title']?.toString() ?? 'Công việc',
          ownerId: extractUserId(taskDetail['owner']),
          token: widget.token,
        ),
      ),
    );
    if (mounted) await loadTaskDetail();
  }

  String statusText(String status) {
    switch (status) {
      case 'completed':
      case 'done':
        return 'Đã hoàn thành';
      case 'in_progress':
        return 'Đang thực hiện';
      default:
        return 'Chờ thực hiện';
    }
  }

  Color statusColor(String status) {
    switch (status) {
      case 'completed':
      case 'done':
        return Colors.green;
      case 'in_progress':
        return const Color(0xFF1769E8);
      default:
        return Colors.orange;
    }
  }

  Widget buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.bold,
        color: Color(0xFF333333),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = taskDetail['title']?.toString() ??
        'Không có tiêu đề';

    final description =
        taskDetail['description']?.toString() ?? '';

    final status =
        taskDetail['status']?.toString() ?? 'pending';

    final assignedIds = getAssignedIds();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FF),
      appBar: AppBar(
        title: const Text('Chi tiết công việc'),
        backgroundColor: const Color(0xFF1769E8),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            onPressed: isLoading ? null : loadTaskDetail,
            icon: const Icon(Icons.refresh),
          ),
        ],
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
              const Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                errorMessage!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: loadTaskDetail,
                child: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      )
          : RefreshIndicator(
        onRefresh: loadTaskDetail,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Card(
              color: Colors.white,
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius:
                BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.task_alt,
                          color: Color(0xFF1769E8),
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight:
                              FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const Divider(height: 32),

                    buildSectionTitle(
                      'Mô tả công việc',
                    ),
                    const SizedBox(height: 10),
                    Text(
                      description.trim().isEmpty
                          ? 'Chưa có mô tả'
                          : description,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),

                    const SizedBox(height: 24),

                    buildSectionTitle('Trạng thái'),
                    const SizedBox(height: 10),

                    Container(
                      padding:
                      const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor(status)
                            .withValues(alpha: 0.1),
                        borderRadius:
                        BorderRadius.circular(10),
                      ),
                      child: Text(
                        statusText(status),
                        style: TextStyle(
                          color: statusColor(status),
                          fontWeight:
                          FontWeight.bold,
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    buildSectionTitle(
                      'Người được phân công',
                    ),
                    const SizedBox(height: 12),

                    if (assignedIds.isEmpty)
                      const Text(
                        'Chưa phân công người thực hiện',
                        style: TextStyle(
                          color: Colors.grey,
                        ),
                      )
                    else
                      Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Đã phân công ${assignedIds.length} người',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: assignedIds.map((id) {
                              final name = userNames[id] ??
                                  'Chưa tải được tên';

                              return Chip(
                                avatar: const Icon(
                                  Icons.person,
                                  size: 18,
                                  color: Color(
                                    0xFF1769E8,
                                  ),
                                ),
                                label: Text(name),
                                backgroundColor:
                                const Color(
                                  0xFFEAF2FF,
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            if (canManageShares) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: openShareManagement,
                  icon: const Icon(Icons.people_alt_outlined),
                  label: const Text('Quản lý chia sẻ'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1769E8),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ================= QUẢN LÝ CHIA SẺ BUỔI 2 =================
// Chỉ chủ sở hữu thấy nút mở màn hình này. Mọi thao tác
// vẫn được Backend kiểm tra quyền trước khi cập nhật MongoDB.
class TaskShareManagementScreen extends StatefulWidget {
  final String taskId;
  final String taskTitle;
  final String? ownerId;
  final String token;

  const TaskShareManagementScreen({
    super.key,
    required this.taskId,
    required this.taskTitle,
    required this.ownerId,
    required this.token,
  });

  @override
  State<TaskShareManagementScreen> createState() =>
      _TaskShareManagementScreenState();
}

class _TaskShareManagementScreenState
    extends State<TaskShareManagementScreen> {
  bool isLoading = true;
  bool isSaving = false;
  String? errorMessage;
  String? selectedUserId;
  String selectedPermission = 'viewer';
  List<Map<String, dynamic>> users = [];
  List<Map<String, dynamic>> shares = [];

  @override
  void initState() {
    super.initState();
    loadData();
  }

  String? userIdOf(dynamic user) {
    if (user == null) return null;
    if (user is Map) return (user['_id'] ?? user['id'])?.toString();
    return user.toString();
  }

  String permissionLabel(String permission) =>
      permission == 'editor' ? 'Được sửa' : 'Chỉ xem';

  Future<Map<String, dynamic>> request(
      String method,
      String path, [
        Map<String, dynamic>? body,
      ]) async {
    final request = http.Request(
      method,
      Uri.parse('${ApiService.baseUrl}$path'),
    );
    request.headers.addAll({
      'Authorization': 'Bearer ${widget.token}',
      'Content-Type': 'application/json',
    });
    if (body != null) request.body = jsonEncode(body);

    final streamed = await request.send().timeout(
      const Duration(seconds: 15),
    );
    final response = await http.Response.fromStream(streamed);
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(response.body);
      data = decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      throw Exception('Máy chủ trả về dữ liệu không hợp lệ');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data['message']?.toString() ?? 'Yêu cầu thất bại');
    }
    return data;
  }

  Future<void> loadData() async {
    if (!mounted) return;
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    try {
      final results = await Future.wait([
        request('GET', '/api/users'),
        request('GET', '/api/tasks/${widget.taskId}/shares'),
      ]);
      final userList = results[0]['users'];
      final shareList = results[1]['shares'];
      if (userList is! List || shareList is! List) {
        throw Exception('Dữ liệu chia sẻ không hợp lệ');
      }
      if (!mounted) return;
      setState(() {
        users = userList
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        shares = shareList
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        selectedUserId = null;
        isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        errorMessage = error.toString().replaceFirst('Exception: ', '');
        isLoading = false;
      });
    }
  }

  void notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> addShare() async {
    final userId = selectedUserId;
    if (userId == null || isSaving) return;
    setState(() => isSaving = true);
    try {
      await request('POST', '/api/tasks/${widget.taskId}/shares', {
        'shares': [
          {'userId': userId, 'permission': selectedPermission},
        ],
      });
      notify('Chia sẻ công việc thành công');
      await loadData();
    } catch (error) {
      notify(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  Future<void> updatePermission(String shareId, String permission) async {
    if (isSaving) return;
    setState(() => isSaving = true);
    try {
      await request(
        'PATCH',
        '/api/tasks/${widget.taskId}/shares/$shareId',
        {'permission': permission},
      );
      notify('Cập nhật quyền thành công');
      await loadData();
    } catch (error) {
      notify(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  Future<void> revokeShare(String shareId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Thu hồi quyền chia sẻ?'),
        content: const Text('Người này sẽ không còn quyền chia sẻ công việc.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Thu hồi'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || isSaving) return;
    setState(() => isSaving = true);
    try {
      await request('DELETE', '/api/tasks/${widget.taskId}/shares/$shareId');
      notify('Đã thu hồi quyền chia sẻ');
      await loadData();
    } catch (error) {
      notify(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sharedUserIds = shares
        .map((share) => userIdOf(share['userId']))
        .whereType<String>()
        .toSet();
    final candidates = users.where((user) {
      final id = userIdOf(user);
      return id != null &&
          id != widget.ownerId &&
          !sharedUserIds.contains(id);
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FF),
      appBar: AppBar(
        title: const Text('Quản lý chia sẻ'),
        backgroundColor: const Color(0xFF1769E8),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: isLoading || isSaving ? null : loadData,
            icon: const Icon(Icons.refresh),
            tooltip: 'Làm mới',
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
          ? Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(errorMessage!, textAlign: TextAlign.center),
            ),
            ElevatedButton(
              onPressed: loadData,
              child: const Text('Thử lại'),
            ),
          ],
        ),
      )
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.taskTitle,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Chia sẻ cho người dùng',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: selectedUserId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Chọn tài khoản',
                      border: OutlineInputBorder(),
                    ),
                    hint: Text(candidates.isEmpty
                        ? 'Không còn tài khoản để chia sẻ'
                        : 'Chọn người nhận'),
                    items: candidates.map((user) {
                      final id = userIdOf(user)!;
                      return DropdownMenuItem<String>(
                        value: id,
                        child: Text(
                          user['fullName']?.toString() ?? id,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: isSaving || candidates.isEmpty
                        ? null
                        : (value) => setState(() {
                      selectedUserId = value;
                    }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedPermission,
                    decoration: const InputDecoration(
                      labelText: 'Quyền truy cập',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'viewer',
                        child: Text('Chỉ xem'),
                      ),
                      DropdownMenuItem(
                        value: 'editor',
                        child: Text('Được sửa'),
                      ),
                    ],
                    onChanged: isSaving
                        ? null
                        : (value) => setState(() {
                      selectedPermission = value ?? 'viewer';
                    }),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: selectedUserId == null || isSaving
                          ? null
                          : addShare,
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('Chia sẻ công việc'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Đã chia sẻ (${shares.length})',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          if (shares.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Công việc chưa được chia sẻ cho ai.'),
            ),
          for (final share in shares)
            Card(
              color: Colors.white,
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.person_outline),
                ),
                title: Text(
                  share['userId'] is Map
                      ? (share['userId']['fullName']?.toString() ??
                      'Người dùng')
                      : 'Người dùng',
                ),
                subtitle: Text(permissionLabel(
                  share['permission']?.toString() ?? 'viewer',
                )),
                trailing: PopupMenuButton<String>(
                  enabled: !isSaving,
                  tooltip: 'Quản lý quyền',
                  onSelected: (action) {
                    final shareId = share['_id']?.toString();
                    if (shareId == null) return;
                    if (action == 'revoke') {
                      revokeShare(shareId);
                    } else {
                      updatePermission(shareId, action);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'viewer',
                      child: Text('Đổi thành Chỉ xem'),
                    ),
                    PopupMenuItem(
                      value: 'editor',
                      child: Text('Đổi thành Được sửa'),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'revoke',
                      child: Text('Thu hồi quyền'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
