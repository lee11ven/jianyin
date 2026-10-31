import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'session_models.dart';

class ApiClient {
  ApiClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;

  Future<Map<String, dynamic>> health() async {
    final res = await _http.get(ApiConfig.restUri('/health'));
    return _decodeMap(res);
  }

  /// Returns debug OTP when server includes `code` (non-production only).
  Future<String?> sendOtp({required String phone}) async {
    final res = await _http.post(
      ApiConfig.restUri('/api/v1/auth/send-otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phone': phone}),
    );
    final map = _decodeMap(res);
    final code = map['code'];
    return code is String && code.isNotEmpty ? code : null;
  }

  Future<AuthToken> register({
    required String phone,
    required String password,
    required String code,
    required String deviceId,
  }) async {
    final res = await _http.post(
      ApiConfig.restUri('/api/v1/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'phone': phone,
        'password': password,
        'code': code,
        'deviceId': deviceId,
      }),
    );
    final map = _decodeMap(res, ok: const {200, 201});
    return AuthToken.fromJson(map);
  }

  Future<AuthToken> login({
    required String phone,
    required String password,
    required String deviceId,
  }) async {
    final res = await _http.post(
      ApiConfig.restUri('/api/v1/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'phone': phone,
        'password': password,
        'deviceId': deviceId,
      }),
    );
    final map = _decodeMap(res);
    return AuthToken.fromJson(map);
  }

  Future<UserProfile> me({required String token}) async {
    final res = await _http.get(
      ApiConfig.restUri('/api/v1/me'),
      headers: _authHeaders(token),
    );
    return UserProfile.fromJson(_decodeMap(res));
  }

  Future<UserProfile> patchMe({
    required String token,
    String? username,
    String? sex,
  }) async {
    final res = await _http.patch(
      ApiConfig.restUri('/api/v1/me'),
      headers: _authHeaders(token),
      body: jsonEncode({
        if (username != null) 'username': username,
        if (sex != null) 'sex': sex,
      }),
    );
    return UserProfile.fromJson(_decodeMap(res));
  }

  Future<List<HistoryDay>> history({
    required String token,
    String? from,
    String? to,
  }) async {
    final query = <String, String>{
      if (from != null) 'from': from,
      if (to != null) 'to': to,
    };
    final res = await _http.get(
      ApiConfig.restUri('/api/v1/history', query.isEmpty ? null : query),
      headers: _authHeaders(token),
    );
    final map = _decodeMap(res);
    final days = map['days'];
    if (days is! List) return const [];
    return days
        .whereType<Map>()
        .map((e) => HistoryDay.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  Future<List<MembershipPlan>> membershipPlans({required String token}) async {
    final res = await _http.get(
      ApiConfig.restUri('/api/v1/membership/plans'),
      headers: _authHeaders(token),
    );
    final map = _decodeMap(res);
    final plans = map['plans'];
    if (plans is! List) return const [];
    return plans
        .whereType<Map>()
        .map((e) => MembershipPlan.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  Future<MembershipStatus> membership({required String token}) async {
    final res = await _http.get(
      ApiConfig.restUri('/api/v1/membership'),
      headers: _authHeaders(token),
    );
    return MembershipStatus.fromJson(_decodeMap(res));
  }

  Future<MembershipStatus> subscribe({
    required String token,
    required String planId,
  }) async {
    final res = await _http.post(
      ApiConfig.restUri('/api/v1/membership/subscribe'),
      headers: _authHeaders(token),
      body: jsonEncode({'planId': planId}),
    );
    return MembershipStatus.fromJson(_decodeMap(res));
  }

  Future<SessionInfo> createSession({
    required String token,
    bool usePhoneLandmarks = true,
    String? edgeDeviceId,
  }) async {
    final body = <String, dynamic>{
      'usePhoneLandmarks': usePhoneLandmarks,
      if (edgeDeviceId != null) 'edgeDeviceId': edgeDeviceId,
    };
    final res = await _http.post(
      ApiConfig.restUri('/api/v1/sessions'),
      headers: _authHeaders(token),
      body: jsonEncode(body),
    );
    final map = _decodeMap(res, ok: const {200, 201});
    return SessionInfo.fromJson(map);
  }

  Future<void> stopSession({
    required String token,
    required String sessionId,
  }) async {
    final res = await _http.post(
      ApiConfig.restUri('/api/v1/sessions/$sessionId/stop'),
      headers: _authHeaders(token),
      body: '{}',
    );
    if (res.statusCode == 404) return;
    _decodeMap(res);
  }

  Map<String, String> _authHeaders(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  Map<String, dynamic> _decodeMap(
    http.Response res, {
    Set<int> ok = const {200},
  }) {
    Object? body;
    try {
      body = res.body.isEmpty ? null : jsonDecode(res.body);
    } catch (_) {
      body = res.body;
    }
    if (!ok.contains(res.statusCode)) {
      throw ApiException.fromBody(res.statusCode, body);
    }
    if (body is Map<String, dynamic>) return body;
    if (body is Map) return Map<String, dynamic>.from(body);
    throw ApiException(
      code: 'bad_response',
      message: 'expected JSON object',
      statusCode: res.statusCode,
    );
  }

  void close() => _http.close();
}
