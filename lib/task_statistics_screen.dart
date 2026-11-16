import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'services/api_service.dart';

class TaskStatisticsScreen extends StatefulWidget {
  final String token;

  const TaskStatisticsScreen({super.key, required this.token});

  @override
  State<TaskStatisticsScreen> createState() => _TaskStatisticsScreenState();
}

class _TaskStatisticsScreenState extends State<TaskStatisticsScreen> {
  static const Color primary = Color(0xFF1769E8);
  static const Color pendingColor = Color(0xFFF59E0B);
  static const Color progressColor = Color(0xFF3B82F6);
  static const Color completedColor = Color(0xFF16A34A);

  bool isLoading = true;
  String? errorMessage;
  List<Map<String, dynamic>> tasks = [];
  Map<String, dynamic> assignments = {};
  Map<String, dynamic> deadlines = {};

  @override
  void initState() {
    super.initState();
    loadStatistics();
  }

  Future<void> loadStatistics() async {
    if (!mounted) return;
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      // Cùng API và JWT với danh sách công việc: không vượt quyền Backend.
      final result = await ApiService.getTasks(token: widget.token);
      final assigned = await ApiService.getStatistics(widget.token, 'assignments');
      final deadlineData = await ApiService.getStatistics(widget.token, 'deadlines');
      if (!mounted) return;
      setState(() {
        tasks = result;
        assignments = assigned;
        deadlines = deadlineData;
        isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        errorMessage = error.toString();
        isLoading = false;
      });
    }
  }

  int countStatus(String status) =>
      tasks.where((task) => task['status']?.toString() == status).length;

  @override
  Widget build(BuildContext context) {
    final total = tasks.length;
    final pending = countStatus('pending');
    final inProgress = countStatus('in_progress');
    final completed = countStatus('completed');
    final completionRate = total == 0 ? 0.0 : completed / total;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FF),
      appBar: AppBar(
        title: const Text('Thống kê công việc'),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Tải lại thống kê',
            onPressed: isLoading ? null : loadStatistics,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off_outlined,
                            size: 54, color: Colors.grey),
                        const SizedBox(height: 12),
                        Text(
                          'Không tải được thống kê:\n$errorMessage',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: loadStatistics,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Thử lại'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: loadStatistics,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1769E8), Color(0xFF4F91F7)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'TỔNG QUAN CÔNG VIỆC',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '$total công việc',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 30,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Dữ liệu thuộc phạm vi tài khoản được phép xem',
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: _StatCard(
                              label: 'Chờ thực hiện',
                              value: pending,
                              icon: Icons.schedule_rounded,
                              color: pendingColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _StatCard(
                              label: 'Đang thực hiện',
                              value: inProgress,
                              icon: Icons.autorenew_rounded,
                              color: progressColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _StatCard(
                              label: 'Hoàn thành',
                              value: completed,
                              icon: Icons.task_alt_rounded,
                              color: completedColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _StatCard(
                              label: 'Tỷ lệ hoàn thành',
                              valueText: '${(completionRate * 100).toStringAsFixed(1)}%',
                              icon: Icons.insights_rounded,
                              color: primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _SectionCard(
                        title: 'Biểu đồ trạng thái',
                        child: Column(
                          children: [
                            SizedBox(
                              height: 190,
                              child: Center(
                                child: SizedBox(
                                  width: 176,
                                  height: 176,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      CustomPaint(
                                        size: const Size(176, 176),
                                        painter: _StatusRingPainter(
                                          total: total,
                                          pending: pending,
                                          inProgress: inProgress,
                                          completed: completed,
                                        ),
                                      ),
                                      Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            '${(completionRate * 100).toStringAsFixed(1)}%',
                                            style: const TextStyle(
                                              fontSize: 27,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF16213B),
                                            ),
                                          ),
                                          const Text(
                                            'Hoàn thành',
                                            style: TextStyle(color: Colors.grey),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            _LegendRow(
                              label: 'Chờ thực hiện',
                              count: pending,
                              color: pendingColor,
                            ),
                            _LegendRow(
                              label: 'Đang thực hiện',
                              count: inProgress,
                              color: progressColor,
                            ),
                            _LegendRow(
                              label: 'Hoàn thành',
                              count: completed,
                              color: completedColor,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SectionCard(
                        title: 'Tiến độ theo trạng thái',
                        child: Column(
                          children: [
                            _ProgressRow(
                              label: 'Chờ thực hiện',
                              count: pending,
                              total: total,
                              color: pendingColor,
                            ),
                            const SizedBox(height: 18),
                            _ProgressRow(
                              label: 'Đang thực hiện',
                              count: inProgress,
                              total: total,
                              color: progressColor,
                            ),
                            const SizedBox(height: 18),
                            _ProgressRow(
                              label: 'Hoàn thành',
                              count: completed,
                              total: total,
                              color: completedColor,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _SectionCard(
                        title: 'Phân công và phụ trách',
                        child: Column(children: [
                          ListTile(leading: const Icon(Icons.assignment_ind),
                            title: const Text('Công việc được giao cho tôi'),
                            trailing: Text('${assignments['assigned'] ?? 0}')),
                          ListTile(leading: const Icon(Icons.person_pin),
                            title: const Text('Tôi phụ trách chính'),
                            trailing: Text('${assignments['primary'] ?? 0}')),
                          ListTile(leading: const Icon(Icons.create),
                            title: const Text('Công việc do tôi tạo'),
                            trailing: Text('${assignments['created'] ?? 0}')),
                        ]),
                      ),
                      const SizedBox(height: 14),
                      _SectionCard(
                        title: 'Theo dõi hạn hoàn thành',
                        child: Column(children: [
                          ListTile(leading: const Icon(Icons.warning_amber, color: Colors.red),
                            title: const Text('Đã quá hạn'),
                            trailing: Text('${deadlines['overdue'] ?? 0}')),
                          ListTile(leading: const Icon(Icons.event, color: Colors.orange),
                            title: const Text('Sắp đến hạn (7 ngày)'),
                            trailing: Text('${deadlines['upcoming'] ?? 0}')),
                        ]),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Thống kê được tính từ danh sách công việc API trả về '
                        'cho tài khoản đang đăng nhập. Kéo xuống để cập nhật.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int? value;
  final String? valueText;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    this.value,
    this.valueText,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 122),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFE8EDF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 25),
          const SizedBox(height: 10),
          Text(
            valueText ?? '${value ?? 0}',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Color(0xFF16213B),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8EDF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Color(0xFF16213B),
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _LegendRow({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
          Text(
            '$count',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  final String label;
  final int count;
  final int total;
  final Color color;

  const _ProgressRow({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = total == 0 ? 0.0 : count / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            Text('${(fraction * 100).toStringAsFixed(1)}%'),
          ],
        ),
        const SizedBox(height: 9),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 10,
            backgroundColor: const Color(0xFFEDF2F8),
            color: color,
          ),
        ),
      ],
    );
  }
}

class _StatusRingPainter extends CustomPainter {
  final int total;
  final int pending;
  final int inProgress;
  final int completed;

  const _StatusRingPainter({
    required this.total,
    required this.pending,
    required this.inProgress,
    required this.completed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 12;
    const strokeWidth = 17.0;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final backgroundPaint = Paint()
      ..color = const Color(0xFFE9EEF6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, backgroundPaint);

    if (total == 0) return;

    double start = -math.pi / 2;
    final segments = <(int, Color)>[
      (pending, const Color(0xFFF59E0B)),
      (inProgress, const Color(0xFF3B82F6)),
      (completed, const Color(0xFF16A34A)),
    ];

    for (final segment in segments) {
      if (segment.$1 <= 0) continue;
      final sweep = (segment.$1 / total) * math.pi * 2;
      final paint = Paint()
        ..color = segment.$2
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _StatusRingPainter oldDelegate) =>
      total != oldDelegate.total ||
      pending != oldDelegate.pending ||
      inProgress != oldDelegate.inProgress ||
      completed != oldDelegate.completed;
}
