import 'package:flutter_test/flutter_test.dart';
import 'package:jianyin_app/app.dart';

void main() {
  testWidgets('Login page shows brand', (tester) async {
    await tester.pumpWidget(const JianyinApp());
    await tester.pumpAndSettle();
    expect(find.text('见音'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
  });
}
