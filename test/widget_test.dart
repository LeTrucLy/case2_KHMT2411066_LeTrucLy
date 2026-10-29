
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/main.dart';

void main() {
  testWidgets('Task Manager khởi động thành công', (tester) async {
    await tester.pumpWidget(const TaskManagerApp());

    expect(find.text('TASK MANAGER'), findsOneWidget);
  });
}
