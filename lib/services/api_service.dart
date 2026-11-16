
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // Android Emulator truy cập Backend trên máy tính
  static const String baseUrl = 'http://10.0.2.2:3000';

  // ================ XỬ LÝ PHẢN HỒI ================

  static Map<String, dynamic> _parseResponse(
      http.Response response,
      ) {
    try {
      final decoded = jsonDecode(response.body);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      throw const FormatException('JSON không hợp lệ');
    } catch (_) {
      throw Exception('Không đọc được phản hồi từ máy chủ');
    }
  }

  static Map<String, dynamic> _checkResponse(
      http.Response response,
      ) {
    final data = _parseResponse(response);

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      throw Exception(
        data['message'] ?? 'Yêu cầu không thành công',
      );
    }

    return data;
  }

  static Map<String, String> _authHeaders(String token) {
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  // ================= ĐĂNG KÝ =================

  static Future<Map<String, dynamic>> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'fullName': fullName.trim(),
        'email': email.trim().toLowerCase(),
        'password': password,
      }),
    ).timeout(const Duration(seconds: 15));

    return _checkResponse(response);
  }

  // ================= ĐĂNG NHẬP =================

  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email.trim().toLowerCase(),
        'password': password,
      }),
    ).timeout(const Duration(seconds: 15));

    return _checkResponse(response);
  }


  // ===== DANH SÁCH + TÌM KIẾM NÂNG CAO =====
  static Future<List<Map<String, dynamic>>> getTasks({
    required String token,
    String keyword = '',
    String status = '',
    String priority = '',
    String scope = '',
    String assigneeId = '',
    String sortBy = 'createdAt',
    String order = 'desc',
  }) async {
    final queryParameters = <String, String>{};

    if (keyword.trim().isNotEmpty) {
      queryParameters['q'] = keyword.trim();
    }

    if (status.isNotEmpty && status != 'all') {
      queryParameters['status'] = status;
    }

    if (priority.isNotEmpty && priority != 'all') queryParameters['priority'] = priority;
    if (scope.isNotEmpty && scope != 'all') queryParameters['scope'] = scope;
    if (assigneeId.isNotEmpty) queryParameters['assigneeId'] = assigneeId;
    queryParameters['sortBy'] = sortBy;
    queryParameters['order'] = order;

    final uri = Uri.parse('$baseUrl/api/tasks')
        .replace(queryParameters: queryParameters);

    final response = await http.get(
      uri,
      headers: _authHeaders(token),
    ).timeout(const Duration(seconds: 15));

    final data = _checkResponse(response);

    if (data['tasks'] is List) {
      return (data['tasks'] as List)
          .map(
            (task) => Map<String, dynamic>.from(
          task as Map,
        ),
      )
          .toList();
    }

    throw Exception('Dữ liệu công việc không hợp lệ');
  }

  // ============== CHI TIẾT CÔNG VIỆC ==============

  static Future<Map<String, dynamic>> getTaskDetail({
    required String token,
    required String taskId,
  }) async {
    if (taskId.isEmpty) {
      throw Exception('Không tìm thấy mã công việc');
    }

    final response = await http.get(
      Uri.parse(
        '$baseUrl/api/tasks/${Uri.encodeComponent(taskId)}',
      ),
      headers: _authHeaders(token),
    ).timeout(const Duration(seconds: 15));

    final data = _checkResponse(response);

    if (data['task'] is Map) {
      return Map<String, dynamic>.from(data['task'] as Map);
    }

    if (data.containsKey('_id') ||
        data.containsKey('title')) {
      return data;
    }

    throw Exception('Dữ liệu chi tiết không hợp lệ');
  }

  // ================= THÊM CÔNG VIỆC =================

  static Future<Map<String, dynamic>> createTask({
    required String token,
    required String title,
    required String description,
    String status = 'pending',
    String? dueDate,
  }) async {
    final body = <String, dynamic>{
      'title': title.trim(),
      'description': description.trim(),
      'status': status,
    };

    if (dueDate != null && dueDate.isNotEmpty) {
      body['dueDate'] = dueDate;
    }

    final response = await http.post(
      Uri.parse('$baseUrl/api/tasks'),
      headers: _authHeaders(token),
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 15));

    return _checkResponse(response);
  }

  // ================= SỬA CÔNG VIỆC =================

  static Future<Map<String, dynamic>> updateTask({
    required String token,
    required String taskId,
    required String title,
    required String description,
    required String status,
    String? dueDate,
  }) async {
    if (taskId.isEmpty) {
      throw Exception('Không tìm thấy mã công việc');
    }

    final body = <String, dynamic>{
      'title': title.trim(),
      'description': description.trim(),
      'status': status,
    };

    if (dueDate != null && dueDate.isNotEmpty) {
      body['dueDate'] = dueDate;
    }

    final response = await http.put(
      Uri.parse(
        '$baseUrl/api/tasks/${Uri.encodeComponent(taskId)}',
      ),
      headers: _authHeaders(token),
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 15));

    return _checkResponse(response);
  }

  // ================= XÓA CÔNG VIỆC =================

  static Future<Map<String, dynamic>> deleteTask({
    required String token,
    required String taskId,
  }) async {
    if (taskId.isEmpty) {
      throw Exception('Không tìm thấy mã công việc');
    }

    final response = await http.delete(
      Uri.parse(
        '$baseUrl/api/tasks/${Uri.encodeComponent(taskId)}',
      ),
      headers: _authHeaders(token),
    ).timeout(const Duration(seconds: 15));

    return _checkResponse(response);
  }

  static Future<Map<String, dynamic>> updateTaskStatus({
    required String token,
    required String taskId,
    required String status,
  }) async {
    final response = await http.patch(
      Uri.parse(
        '$baseUrl/api/tasks/${Uri.encodeComponent(taskId)}/status',
      ),
      headers: _authHeaders(token),
      body: jsonEncode({
        'status': status,
      }),
    ).timeout(const Duration(seconds: 15));

    return _checkResponse(response);
  }

  // ========== LẤY DANH SÁCH NGƯỜI DÙNG ==========

  static Future<List<Map<String, dynamic>>> getUsers({
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/users'),
      headers: _authHeaders(token),
    ).timeout(const Duration(seconds: 15));

    final data = _checkResponse(response);

    return (data['users'] as List)
        .map((user) => Map<String, dynamic>.from(user as Map))
        .toList();
  }

  // ========== LẤY DANH SÁCH CHIA SẺ ==========

  static Future<List<Map<String, dynamic>>> getTaskShares({
    required String token,
    required String taskId,
  }) async {
    final response = await http.get(
      Uri.parse(
        '$baseUrl/api/tasks/${Uri.encodeComponent(taskId)}/shares',
      ),
      headers: _authHeaders(token),
    ).timeout(const Duration(seconds: 15));

    final data = _checkResponse(response);

    return (data['shares'] as List)
        .map((share) => Map<String, dynamic>.from(share as Map))
        .toList();
  }

  // ========== CHIA SẺ CÔNG VIỆC ==========

  static Future<Map<String, dynamic>> shareTask({
    required String token,
    required String taskId,
    required List<Map<String, dynamic>> shares,
  }) async {
    final response = await http.post(
      Uri.parse(
        '$baseUrl/api/tasks/${Uri.encodeComponent(taskId)}/shares',
      ),
      headers: _authHeaders(token),
      body: jsonEncode({
        'shares': shares,
      }),
    ).timeout(const Duration(seconds: 15));

    return _checkResponse(response);
  }

  // ========== THAY ĐỔI QUYỀN CHIA SẺ ==========

  static Future<Map<String, dynamic>> updateSharePermission({
    required String token,
    required String taskId,
    required String shareId,
    required String permission,
  }) async {
    final response = await http.patch(
      Uri.parse(
        '$baseUrl/api/tasks/${Uri.encodeComponent(taskId)}/shares/${Uri.encodeComponent(shareId)}',
      ),
      headers: _authHeaders(token),
      body: jsonEncode({
        'permission': permission,
      }),
    ).timeout(const Duration(seconds: 15));

    return _checkResponse(response);
  }

  // ========== THU HỒI QUYỀN CHIA SẺ ==========

  static Future<Map<String, dynamic>> revokeTaskShare({
    required String token,
    required String taskId,
    required String shareId,
  }) async {
    final response = await http.delete(
      Uri.parse(
        '$baseUrl/api/tasks/${Uri.encodeComponent(taskId)}/shares/${Uri.encodeComponent(shareId)}',
      ),
      headers: _authHeaders(token),
    ).timeout(const Duration(seconds: 15));

    return _checkResponse(response);
  }

  // ===== CÁ NHÂN, THÔNG BÁO VÀ THỐNG KÊ =====
  static Future<Map<String, dynamic>> getProfile(String token) async {
    final response = await http.get(Uri.parse('$baseUrl/api/auth/me'),
      headers: _authHeaders(token)).timeout(const Duration(seconds: 15));
    return _checkResponse(response);
  }

  static Future<Map<String, dynamic>> updateProfile(String token, String name) async {
    final response = await http.put(Uri.parse('$baseUrl/api/auth/me'),
      headers: _authHeaders(token), body: jsonEncode({'fullName': name.trim()}))
      .timeout(const Duration(seconds: 15));
    return _checkResponse(response);
  }

  static Future<Map<String, dynamic>> changePassword(
    String token, String oldPassword, String newPassword) async {
    final response = await http.put(Uri.parse('$baseUrl/api/auth/change-password'),
      headers: _authHeaders(token),
      body: jsonEncode({'oldPassword': oldPassword, 'newPassword': newPassword}))
      .timeout(const Duration(seconds: 15));
    return _checkResponse(response);
  }

  static Future<List<Map<String, dynamic>>> getNotifications(String token) async {
    final response = await http.get(Uri.parse('$baseUrl/api/notifications'),
      headers: _authHeaders(token)).timeout(const Duration(seconds: 15));
    final data = _checkResponse(response);
    return (data['notifications'] as List)
      .map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<void> readNotification(String token, String id) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/api/notifications/${Uri.encodeComponent(id)}/read'),
      headers: _authHeaders(token)).timeout(const Duration(seconds: 15));
    _checkResponse(response);
  }

  static Future<void> readAllNotifications(String token) async {
    final response = await http.patch(Uri.parse('$baseUrl/api/notifications/read-all'),
      headers: _authHeaders(token)).timeout(const Duration(seconds: 15));
    _checkResponse(response);
  }

  static Future<Map<String, dynamic>> getStatistics(String token, String type) async {
    if (!['tasks', 'assignments', 'deadlines'].contains(type)) {
      throw ArgumentError('Loại thống kê không hợp lệ');
    }
    final response = await http.get(Uri.parse('$baseUrl/api/statistics/$type'),
      headers: _authHeaders(token)).timeout(const Duration(seconds: 15));
    return _checkResponse(response);
  }

  static Future<List<Map<String, dynamic>>> getActivities(
    String token, String taskId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/tasks/${Uri.encodeComponent(taskId)}/activities'),
      headers: _authHeaders(token)).timeout(const Duration(seconds: 15));
    final data = _checkResponse(response);
    return (data['activities'] as List)
      .map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<List<Map<String, dynamic>>> getEmailLogs(
    String token, String taskId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/tasks/${Uri.encodeComponent(taskId)}/email-logs'),
      headers: _authHeaders(token)).timeout(const Duration(seconds: 15));
    final data = _checkResponse(response);
    return (data['logs'] as List)
      .map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<void> retryEmail(String token, String logId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/email-logs/${Uri.encodeComponent(logId)}/retry'),
      headers: _authHeaders(token)).timeout(const Duration(seconds: 20));
    _checkResponse(response);
  }

  // ===== GỬI MÃ QUÊN MẬT KHẨU =====
  static Future<Map<String, dynamic>> forgotPassword({
    required String email,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/forgot-password'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'email': email.trim().toLowerCase(),
      }),
    ).timeout(const Duration(seconds: 20));

    return _checkResponse(response);
  }

  // ===== XÁC MINH MÃ VÀ ĐẶT LẠI MẬT KHẨU =====
  static Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String resetCode,
    required String newPassword,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/reset-password'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'email': email.trim().toLowerCase(),
        'resetCode': resetCode.trim(),
        'newPassword': newPassword,
      }),
    ).timeout(const Duration(seconds: 20));

    return _checkResponse(response);
  }

}
