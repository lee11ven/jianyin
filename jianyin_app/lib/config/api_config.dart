/// Local / LAN gateway endpoints (protocolVersion: 1).
///
/// 默认值为**局域网示例地址**，端口与网关默认端口保持一致
/// （`websocket-server/src/config.js` 的 `8000`）。真机联调时用 `--dart-define` 覆盖：
/// `flutter run --dart-define=API_BASE_URL=http://192.168.1.100:8000`
///
/// 会话建立后握手地址优先取 REST 返回的 `wsUrl`（服务端按请求 Host 生成），
/// 因此只要 REST 地址正确，WS 地址会自动跟随，无需二次配置。
abstract final class ApiConfig {
  static const protocolVersion = 1;

  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    // defaultValue: 'http://192.168.1.100:8000',
    defaultValue: 'http://186.241.105.178:8800',
  );

  /// Fallback WS path when REST `wsUrl` is missing (should not happen).
  static const wsAppPath = '/ws/app';

  static const heartbeatInterval = Duration(seconds: 15);
  static const deadConnectionTimeout = Duration(seconds: 45);
  static const reconnectMaxBackoff = Duration(seconds: 30);
  static const reconnectInitialBackoff = Duration(milliseconds: 500);

  static Uri restUri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(baseUrl);
    final normalized = path.startsWith('/') ? path : '/$path';
    return base.replace(path: normalized, queryParameters: query);
  }

  /// Prefer REST-returned [wsUrl]; JWT goes in Authorization header, not query.
  static Uri appWsUri({
    required String? wsUrl,
    required String deviceId,
    required String sessionId,
  }) {
    final base = (wsUrl != null && wsUrl.isNotEmpty)
        ? Uri.parse(wsUrl)
        : Uri.parse(baseUrl).replace(
            scheme: baseUrl.startsWith('https') ? 'wss' : 'ws',
            path: wsAppPath,
          );

    final scheme = switch (base.scheme) {
      'http' => 'ws',
      'https' => 'wss',
      'ws' || 'wss' => base.scheme,
      _ => 'ws',
    };

    return base.replace(
      scheme: scheme,
      queryParameters: {
        'deviceId': deviceId,
        'protocolVersion': '$protocolVersion',
        'sessionId': sessionId,
      },
    );
  }
}
