import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianyin_app/features/home/caption_zone.dart';
import 'package:jianyin_app/features/home/viewpoint_overlay.dart';
import 'package:jianyin_app/perception/viewpoint.dart';

void main() {
  Future<void> pumpChrome(
    WidgetTester tester, {
    required Size size,
    required ValveBand band,
    required String caption,
    double textScale = 1,
    double safeBottom = 0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final captionH = size.height >= CaptionZone.heightDp + 120
        ? CaptionZone.heightDp
        : (size.height * 0.45).clamp(48.0, CaptionZone.heightDp);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
            padding: EdgeInsets.only(bottom: safeBottom),
          ),
          child: Scaffold(
            body: SizedBox(
              width: size.width,
              height: size.height,
              child: Column(
                children: [
                  const SizedBox(height: 56),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 8, 24, 0),
                    child: Text(
                      '请正对镜头，露出上半身',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: ViewpointOverlay(caption: caption, band: band),
                  ),
                  CaptionZone(
                    height: captionH,
                    history: const ['你好'],
                    current: '在',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('绿黄红三档取景框尺寸一致，且落在字幕区上方', (tester) async {
    const size = Size(390, 844);
    const caption = '机位矫正 · 头肩双手入框';
    Rect? frame;

    for (final band in ValveBand.values) {
      await pumpChrome(
        tester,
        size: size,
        band: band,
        caption: band == ValveBand.yellow ? '机位矫正 · 从右下回正' : caption,
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('机位矫正'), findsOneWidget);

      final box = tester.getRect(find.byKey(const ValueKey('vp-frame')));
      final label = tester.getRect(find.textContaining('机位矫正'));
      final captionTop = tester.getTopLeft(find.text('实时字幕')).dy;
      expect(label.bottom, lessThanOrEqualTo(captionTop));
      expect(box.bottom, lessThanOrEqualTo(captionTop));
      expect(box.width, lessThanOrEqualTo(280));
      expect(box.height / box.width, closeTo(4 / 3, 0.02));

      frame ??= box;
      expect(box, frame);
    }
  });

  testWidgets('矮屏与横屏不溢出', (tester) async {
    const cases = <Size>[
      Size(360, 640),
      Size(320, 480),
      Size(800, 360),
      Size(640, 280),
    ];
    for (final size in cases) {
      await pumpChrome(
        tester,
        size: size,
        band: ValveBand.red,
        caption: '机位矫正 · 请正对镜头',
        textScale: 1.4,
        safeBottom: 24,
      );
      expect(tester.takeException(), isNull, reason: '$size');
      expect(find.textContaining('机位矫正'), findsOneWidget);
    }
  });
}
