
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

  // ============== DANH SÁCH CÔNG VIỆC ==============

  static Future<List<Map<String, dynamic>>> getTasks({
    required String token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/tasks'),
      headers: _authHeaders(token),
    ).timeout(const Duration(seconds: 15));

    final data = _checkResponse(response);

    if (data['tasks'] is List) {
      return (data['tasks'] as List)
          .map((task) => Map<String, dynamic>.from(task as Map))
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
}
