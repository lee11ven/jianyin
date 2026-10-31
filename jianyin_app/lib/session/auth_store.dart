import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'device_id_store.dart';
import 'session_models.dart';

/// Holds JWT + user profile. Never log [token].
class AuthStore {
  AuthStore({
    DeviceIdStore? deviceIdStore,
    ApiClient? apiClient,
  })  : _deviceIds = deviceIdStore ?? DeviceIdStore(),
        _api = apiClient ?? ApiClient();

  static const _tokenKey = 'signspeak.auth.token.v1';
  static const _roleKey = 'signspeak.auth.role.v1';
  static const _deviceKey = 'signspeak.auth.deviceId.v1';
  static const _expiresAtKey = 'signspeak.auth.expiresAt.v1';
  static const _phoneKey = 'signspeak.auth.phone.v1';
  static const _userKey = 'signspeak.auth.user.v1';

  final DeviceIdStore _deviceIds;
  final ApiClient _api;

  AuthToken? _auth;
  UserProfile? _user;

  AuthToken? get auth => _auth;
  String? get token => _auth?.token;
  UserProfile? get user => _user;
  String? get phone => _user?.phone;
  bool get isLoggedIn => _auth != null && (_auth!.token.isNotEmpty);

  Future<String> deviceId() => _deviceIds.getOrCreate();

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token == null || token.isEmpty) return;
    final expiresAt = prefs.getInt(_expiresAtKey) ?? 0;
    if (expiresAt > 0 && DateTime.now().millisecondsSinceEpoch >= expiresAt) {
      await clear();
      return;
    }
    final deviceId = prefs.getString(_deviceKey) ?? await this.deviceId();
    final userRaw = prefs.getString(_userKey);
    UserProfile? user;
    if (userRaw != null && userRaw.isNotEmpty) {
      try {
        user = UserProfile.fromJson(
          Map<String, dynamic>.from(jsonDecode(userRaw) as Map),
        );
      } catch (_) {}
    }
    _user = user;
    _auth = AuthToken(
      token: token,
      role: prefs.getString(_roleKey) ?? 'app',
      deviceId: deviceId,
      protocolVersion: 1,
      expiresInSec: expiresAt > 0
          ? ((expiresAt - DateTime.now().millisecondsSinceEpoch) / 1000)
              .ceil()
              .clamp(0, 86400)
          : 86400,
      user: user,
    );
  }

  Future<void> save(AuthToken auth) async {
    _auth = auth;
    _user = auth.user ?? _user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, auth.token);
    await prefs.setString(_roleKey, auth.role);
    await prefs.setString(_deviceKey, auth.deviceId);
    await prefs.setInt(
      _expiresAtKey,
      DateTime.now().millisecondsSinceEpoch + auth.expiresInSec * 1000,
    );
    if (_user != null) {
      await prefs.setString(_userKey, jsonEncode(_user!.toJson()));
      await prefs.setString(_phoneKey, _user!.phone);
    }
  }

  Future<void> setUser(UserProfile user) async {
    _user = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
    await prefs.setString(_phoneKey, user.phone);
  }

  Future<void> clear() async {
    _auth = null;
    _user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_roleKey);
    await prefs.remove(_deviceKey);
    await prefs.remove(_expiresAtKey);
    await prefs.remove(_userKey);
    // Keep phone for login form convenience.
  }

  Future<String?> rememberedPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_phoneKey);
  }

  /// Sends OTP; returns debug code when present (dev only).
  Future<String?> sendOtp({required String phone}) {
    return _api.sendOtp(phone: phone.trim());
  }

  Future<AuthToken> register({
    required String phone,
    required String password,
    required String code,
  }) async {
    final deviceId = await this.deviceId();
    final issued = await _api.register(
      phone: phone.trim(),
      password: password,
      code: code.trim(),
      deviceId: deviceId,
    );
    await save(issued);
    return issued;
  }

  Future<AuthToken> login({
    required String phone,
    required String password,
  }) async {
    final deviceId = await this.deviceId();
    final issued = await _api.login(
      phone: phone.trim(),
      password: password,
      deviceId: deviceId,
    );
    await save(issued);
    return issued;
  }

  Future<UserProfile> refreshMe() async {
    final t = token;
    if (t == null) {
      throw const ApiException(code: 'unauthorized', message: '请先登录');
    }
    final profile = await _api.me(token: t);
    await setUser(profile);
    return profile;
  }

  Future<UserProfile> updateProfile({
    String? username,
    String? sex,
  }) async {
    final t = token;
    if (t == null) {
      throw const ApiException(code: 'unauthorized', message: '请先登录');
    }
    final profile = await _api.patchMe(
      token: t,
      username: username,
      sex: sex,
    );
    await setUser(profile);
    return profile;
  }

  Future<AuthToken> requireAppToken() async {
    await load();
    if (_auth != null && _auth!.token.isNotEmpty) {
      return _auth!;
    }
    throw const ApiException(
      code: 'unauthorized',
      message: '请先登录',
    );
  }
}
