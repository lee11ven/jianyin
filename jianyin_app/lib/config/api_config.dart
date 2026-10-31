/// Local / LAN gateway endpoints (protocolVersion: 1).
///
/// Override at build time:
/// `flutter run --dart-define=API_BASE_URL=http://186.241.105.178:8800`
abstract final class ApiConfig {
  static const protocolVersion = 1;

  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
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
