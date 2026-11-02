import 'package:flutter_test/flutter_test.dart';
import 'package:jianyin_app/config/api_config.dart';
import 'package:jianyin_app/features/auth/auth_validators.dart';
import 'package:jianyin_app/session/session_models.dart';

void main() {
  test('phone and password validators', () {
    expect(validatePhone('13800138000'), isNull);
    expect(validatePhone('123'), isNotNull);
    expect(validatePassword('short', isNew: true), isNotNull);
    expect(validatePassword('password1', isNew: true), isNull);
    expect(validatePasswordConfirm('a', 'b'), isNotNull);
    expect(
      authErrorMessage(
        const ApiException(code: 'phone_taken', message: 'x'),
      ),
      '该手机号已注册',
    );
  });

  test('appWsUri does not put JWT in query', () {
    final uri = ApiConfig.appWsUri(
      wsUrl: 'ws://186.241.105.178:8800/ws/app',
      deviceId: 'app-demo',
      sessionId: 'sess-1',
    );
    // 握手地址取自 REST 返回的 wsUrl（此处即传入值）；默认地址见 ApiConfig。
    expect(uri.scheme, 'ws');
    expect(uri.host, '186.241.105.178');
    expect(uri.port, 8800);
    expect(uri.path, '/ws/app');
    expect(uri.queryParameters.containsKey('token'), isFalse);
    expect(uri.queryParameters['deviceId'], 'app-demo');
    expect(uri.queryParameters['protocolVersion'], '1');
    expect(uri.queryParameters['sessionId'], 'sess-1');
  });

  test('AuthToken parses JWT response with user', () {
    final auth = AuthToken.fromJson({
      'token': 'eyJhbGciOiJIUzI1NiJ9.e30.x',
      'role': 'app',
      'deviceId': 'app-1',
      'protocolVersion': 1,
      'expiresInSec': 86400,
      'user': {
        'userId': 'u-1',
        'username': '林晓',
        'phone': '13800138000',
        'sex': 'female',
        'plan': 'free',
      },
    });
    expect(auth.user?.userId, 'u-1');
    expect(auth.user?.maskedPhone, '138****8000');

    final session = SessionInfo.fromJson({
      'sessionId': 'sess-x',
      'protocolVersion': 1,
      'wsUrl': 'ws://186.241.105.178:8800/ws/app',
    });
    expect(session.sessionId, 'sess-x');
  });
}
