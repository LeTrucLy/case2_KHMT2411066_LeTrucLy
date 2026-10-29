
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // Địa chỉ Backend dành cho Android Emulator
  static const String baseUrl = 'http://10.0.2.2:3000';

  // ================= ĐĂNG KÝ =================

  static Future<Map<String, dynamic>> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final response = await http
        .post(
      Uri.parse('$baseUrl/api/register'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'fullName': fullName.trim(),
        'email': email.trim().toLowerCase(),
        'password': password,
      }),
    )
        .timeout(const Duration(seconds: 15));

    final data = _parseResponse(response);

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      throw Exception(data['message'] ?? 'Đăng ký thất bại');
    }

    return data;
  }

  // ================= ĐĂNG NHẬP =================

  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await http
        .post(
      Uri.parse('$baseUrl/api/login'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'email': email.trim().toLowerCase(),
        'password': password,
      }),
    )
        .timeout(const Duration(seconds: 15));

    final data = _parseResponse(response);

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      throw Exception(data['message'] ?? 'Đăng nhập thất bại');
    }

    return data;
  }

  // ============ XỬ LÝ PHẢN HỒI JSON ============

  static Map<String, dynamic> _parseResponse(
      http.Response response,
      ) {
    try {
      final decoded = jsonDecode(response.body);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      throw const FormatException(
        'Dữ liệu trả về không hợp lệ',
      );
    } catch (e) {
      throw Exception(
        'Không đọc được phản hồi từ máy chủ',
      );
    }
  }

  // ============ DANH SÁCH CÔNG VIỆC ============

  static Future<List<Map<String, dynamic>>> getTasks({
    required String token,
  }) async {
    final response = await http
        .get(
      Uri.parse('$baseUrl/api/tasks'),
      headers: {
        'Authorization': 'Bearer $token',
      },
    )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Không thể tải danh sách công việc');
    }

    final data = _parseResponse(response);

    if (data['tasks'] is List) {
      return (data['tasks'] as List)
          .map(
            (task) => Map<String, dynamic>.from(task as Map),
      )
          .toList();
    }

    throw Exception('Dữ liệu công việc không hợp lệ');
  }

  // ============ CHI TIẾT CÔNG VIỆC ============

  static Future<Map<String, dynamic>> getTaskDetail({
    required String token,
    required String taskId,
  }) async {
    if (taskId.isEmpty) {
      throw Exception('Không tìm thấy mã công việc');
    }

    final response = await http
        .get(
      Uri.parse(
        '$baseUrl/api/tasks/${Uri.encodeComponent(taskId)}',
      ),
      headers: {
        'Authorization': 'Bearer $token',
      },
    )
        .timeout(const Duration(seconds: 15));

    final data = _parseResponse(response);

    if (response.statusCode != 200) {
      throw Exception(
        data['message'] ?? 'Không thể tải chi tiết công việc',
      );
    }

    // Backend có thể trả về { task: {...} }
    if (data['task'] is Map) {
      return Map<String, dynamic>.from(data['task'] as Map);
    }

    // Hoặc trả về trực tiếp đối tượng công việc
    if (data.containsKey('_id') || data.containsKey('title')) {
      return data;
    }

    throw Exception('Dữ liệu chi tiết công việc không hợp lệ');
  }
}