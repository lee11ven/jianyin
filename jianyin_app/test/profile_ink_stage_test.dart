import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianyin_app/features/profile/profile_widgets.dart';
import 'package:jianyin_app/session/session_models.dart';
import 'package:jianyin_app/theme/tokens.dart';

void main() {
  testWidgets('ProfileInkStage builds in sliver', (tester) async {
    const user = UserProfile(
      userId: '1',
      phone: '13800138000',
      username: '测试',
      sex: 'unknown',
      plan: 'free',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          textTheme: const TextTheme(
            titleLarge: TextStyle(fontSize: 22),
            bodyMedium: TextStyle(fontSize: 14),
            bodyLarge: TextStyle(fontSize: 16),
          ),
        ),
        home: Scaffold(
          backgroundColor: AppTokens.paper,
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: ProfileInkStage(
                  user: user,
                  padTopSafeArea: true,
                  actionLabel: '查看与编辑资料',
                  onTap: () {},
                  leading: const SizedBox(width: 48, height: 48),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('你好'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ProfileInkStage compact builds', (tester) async {
    const user = UserProfile(
      userId: '1',
      phone: '13800138000',
      username: '测试',
      sex: 'unknown',
      plan: 'free',
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProfileInkStage(
              user: user,
              compact: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('你好'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
