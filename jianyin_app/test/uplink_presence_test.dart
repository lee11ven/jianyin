import 'package:flutter_test/flutter_test.dart';
import 'package:jianyin_app/envelope/csl_channels.dart';
import 'package:jianyin_app/envelope/landmark_point.dart';
import 'package:jianyin_app/session/home_session_controller.dart';

/// 上行 `body` 通道的契约测试。
///
/// 回归背景：会话控制器曾按 `body['points']['nose']` 取值，而上行 `body` 是
/// 扁平结构，导致 presence 恒为 false、「识别中 / 就绪」状态机与取景框人脸
/// 跟随失效。本测试把该契约锁死。
void main() {
  const nose = LandmarkPoint(x: 0.50, y: 0.22, z: -0.10, v: 0.98);
  const shoulderL = LandmarkPoint(x: 0.38, y: 0.42, z: 0.0, v: 0.97);
  const shoulderR = LandmarkPoint(x: 0.62, y: 0.42, z: 0.0, v: 0.97);

  final body = BodyChannel(
    points: const {'nose': nose, 'shoulderL': shoulderL, 'shoulderR': shoulderR},
    frame: const BodyFrame(
      origin: LandmarkPoint(x: 0.50, y: 0.42, z: 0.0, v: 1),
      shoulderWidth: 0.24,
      right: LandmarkPoint(x: 1, y: 0, z: 0, v: 1),
      up: LandmarkPoint(x: 0, y: -1, z: 0, v: 1),
      zSign: 1,
    ),
  );

  group('noseFromUplink', () {
    test('读取 BodyChannel 投影出的扁平 body', () {
      final payload = CslChannelsLandmarks(
        ts: 1710000000000,
        sessionId: 'sess-test',
        body: body,
      ).toJson();

      // 线格式必须是扁平：body['nose']，不是 body['points']['nose']
      expect((payload['body'] as Map).containsKey('nose'), isTrue);
      expect((payload['body'] as Map).containsKey('points'), isFalse);

      final read = noseFromUplink(payload);
      expect(read, isNotNull);
      expect(read!.$1, closeTo(0.50, 1e-9));
      expect(read.$2, closeTo(0.22, 1e-9));
    });

    test('兼容历史嵌套写法 body.points.nose', () {
      final read = noseFromUplink({
        'body': {
          'points': {
            'nose': {'x': 0.4, 'y': 0.3, 'z': 0.0, 'v': 0.9},
          },
        },
      });
      expect(read, isNotNull);
      expect(read!.$1, closeTo(0.4, 1e-9));
      expect(read.$2, closeTo(0.3, 1e-9));
    });

    test('缺失 body 或无 nose → null（保持“就绪”）', () {
      expect(noseFromUplink({}), isNull);
      expect(noseFromUplink({'hands': {}}), isNull);
      expect(
        noseFromUplink({
          'body': {
            'shoulderL': {'x': 0.3, 'y': 0.4, 'z': 0.0, 'v': 0.9},
            'shoulderR': {'x': 0.7, 'y': 0.4, 'z': 0.0, 'v': 0.9},
          },
        }),
        isNull,
      );
    });

    test('可见性为 0 → null', () {
      final read = noseFromUplink({
        'body': {
          'nose': {'x': 0.5, 'y': 0.2, 'z': 0.0, 'v': 0.0},
        },
      });
      expect(read, isNull);
    });

    test('坐标越界（非图像归一化）→ null', () {
      expect(
        noseFromUplink({
          'body': {
            'nose': {'x': 1.4, 'y': 0.2, 'z': 0.0, 'v': 0.9},
          },
        }),
        isNull,
      );
      expect(
        noseFromUplink({
          'body': {
            'nose': {'x': -0.1, 'y': 0.2, 'z': 0.0, 'v': 0.9},
          },
        }),
        isNull,
      );
    });

    test('缺 v 字段时按可见处理', () {
      final read = noseFromUplink({
        'body': {
          'nose': {'x': 0.5, 'y': 0.5},
        },
      });
      expect(read, isNotNull);
    });
  });
}